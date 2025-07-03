from airflow import DAG
from airflow.utils.dates import days_ago
from airflow.providers.amazon.aws.operators.dms import DmsStartTaskOperator
from airflow.providers.amazon.aws.operators.emr import EmrCreateJobFlowOperator, EmrAddStepsOperator, EmrTerminateJobFlowOperator
from airflow.providers.amazon.aws.sensors.dms import DmsTaskCompletedSensor
from airflow.providers.amazon.aws.sensors.emr import EmrStepSensor
from airflow.utils.trigger_rule import TriggerRule
from datetime import timedelta
from airflow.operators.python import PythonOperator
import boto3
from botocore.exceptions import ClientError

# Constants
DMS_TASK_ARN = "arn:aws:dms:ap-southeast-2:794038230051:task:PFEKC7XIOVGTXBULAGD4BTNCXM"
SCRIPT_S3_PATH = "s3://source-bucket-chien/scripts/pyspark/bronze_to_silver.py"
LOG_URI = "s3://source-bucket-chien/emr-logs/"
EMR_ROLE = "EMR_DefaultRole"
EC2_ROLE = "emr_ec2_instance_profile" # "EMR_EC2_DefaultRole"
SUBNET_ID = "subnet-0e85153f57935e0cd"
EMR_SECURITY_GROUPS = {
    "master": "sg-033e5772afa0c3d12",
    "core": "sg-0decf60199244d66a",
    "service": "sg-07e6dd4da3823202b"
}
EC2_INSTANCE_PROFILE = 'emr_ec2_instance_profile'

default_args = {
    'owner': 'airflow',
    'retry_delay': timedelta(minutes=5),
}


def try_start_dms(**kwargs):
    dms = boto3.client("dms", region_name="ap-southeast-2")
    task_arn = DMS_TASK_ARN

    # Get the current status of the replication task
    task = dms.describe_replication_tasks(
        Filters=[{
            'Name': 'replication-task-arn',
            'Values': [task_arn]
        }]
    )['ReplicationTasks'][0]

    status = task['Status']
    print(f"Current DMS task status: {status}")

    # Decide which start type to use
    if status == "stopped":
        start_type = "resume-processing"
    elif status == "creating":
        raise Exception("DMS task is still creating. Please wait and try again.")
    elif status == "running":
        print("DMS task is already running. No action taken.")
        return
    elif status in ["load completed" "failed"]:
        start_type = "reload-target"
    elif status == ["ready"]:
        start_type = "start-replication"
    else:
        raise Exception(f"Unhandled DMS task status: {status}")

    print(f"Starting task with {start_type}")
    dms.start_replication_task(
        ReplicationTaskArn=task_arn,
        StartReplicationTaskType=start_type
    )


with DAG(
    dag_id="dms_to_emr_pipeline",
    default_args=default_args,
    start_date=days_ago(1),
    schedule_interval=None,  # manual trigger
    catchup=False,
    tags=["dms", "emr", "etl"]
) as dag:

    start_dms_task = PythonOperator(
    task_id="try_start_dms",
    python_callable=try_start_dms,
)
    # start_dms_task = DmsStartTaskOperator(
    # task_id="start_dms_task",
    # replication_task_arn=DMS_TASK_ARN,
    # start_replication_task_type="reload-target",  # "start-replication" or "reload-target", or "resume-processing"
    # aws_conn_id="aws_default",  # or whatever Airflow connection you're using
    # )
    
    wait_for_dms = DmsTaskCompletedSensor(
    task_id="wait_for_dms_completion",
    replication_task_arn=DMS_TASK_ARN,
    aws_conn_id="aws_default",
    poke_interval=60,  # check every 60 seconds
    timeout=60 * 30    # timeout after 30 minutes
)

    create_emr_cluster = EmrCreateJobFlowOperator(
        task_id="create_emr_cluster",
        job_flow_overrides={
            "Name": "airflow-emr-cluster",
            "ReleaseLabel": "emr-7.6.0",
            "Applications": [{"Name": "Spark"}],
            "LogUri": LOG_URI,
            "Instances": {
                "InstanceGroups": [
                    {
                        "InstanceRole": "MASTER",
                        "InstanceType": "m5.xlarge",
                        "InstanceCount": 1,
                    },
                    {
                        "InstanceRole": "CORE",
                        "InstanceType": "m5.xlarge",
                        "InstanceCount": 1,
                    }
                ],
                
                "Ec2SubnetId": SUBNET_ID,
                "EmrManagedMasterSecurityGroup": EMR_SECURITY_GROUPS["master"],
                "EmrManagedSlaveSecurityGroup": EMR_SECURITY_GROUPS["core"],
                "ServiceAccessSecurityGroup": EMR_SECURITY_GROUPS["service"],
                "KeepJobFlowAliveWhenNoSteps": True,   # Keeps the EMR cluster running after all steps are completed.
            },
            "Configurations": [
            {
                "Classification": "spark-hive-site",
                "Properties": {
                    "hive.metastore.client.factory.class": "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory",
                    # Optionally provide catalog ID explicitly:
                    # "hive.metastore.glue.catalogid": "123456789012"
                }
            },
            {
                "Classification": "iceberg-defaults",
                "Properties": {
                    "iceberg.enabled": "true"
                }
            }
        ],
            "JobFlowRole": EC2_ROLE,
            "ServiceRole": EMR_ROLE,
            "VisibleToAllUsers": True,
        }
    )

    add_spark_step = EmrAddStepsOperator(
        task_id="add_spark_step",
        job_flow_id="{{ task_instance.xcom_pull(task_ids='create_emr_cluster', key='return_value') }}",
        steps=[{
            "Name": "Run PySpark ETL",
            "ActionOnFailure": "CONTINUE",
            "HadoopJarStep": {
                "Jar": "command-runner.jar",
                "Args": [
                    "spark-submit",
                    "--deploy-mode", "cluster",
                    "--master", "yarn",
                    SCRIPT_S3_PATH,
                ],
            },
        }]
    )

    watch_spark_step = EmrStepSensor(
        task_id="watch_spark_step",
        job_flow_id="{{ task_instance.xcom_pull(task_ids='create_emr_cluster', key='return_value') }}",
        step_id="{{ task_instance.xcom_pull(task_ids='add_spark_step', key='return_value')[0] }}",
    )

    terminate_emr_cluster = EmrTerminateJobFlowOperator(
        task_id="terminate_emr_cluster",
        job_flow_id="{{ task_instance.xcom_pull(task_ids='create_emr_cluster', key='return_value') }}",
        trigger_rule=TriggerRule.ALL_DONE  # ensure cluster is terminated even if step fails
    )

    # DAG dependencies
    start_dms_task >> wait_for_dms >> create_emr_cluster >> add_spark_step >> watch_spark_step >> terminate_emr_cluster
    # create_emr_cluster >> add_spark_step >> watch_spark_step >> terminate_emr_cluster



