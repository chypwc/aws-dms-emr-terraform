import boto3
import os

def lambda_handler(event, context):
    dms = boto3.client('dms')
    task_arns = os.environ['DMS_TASK_ARNS'].split(",")

    for task_arn in task_arns:
        response = dms.start_replication_task(
            ReplicationTaskArn=task_arn.strip(),
            StartReplicationTaskType='start-replication'
        )
        print(f"Started task: {task_arn}, status: {response['ReplicationTask']['Status']}")