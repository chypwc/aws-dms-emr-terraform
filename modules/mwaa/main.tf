# Main Terraform file to deploy MWAA environment that orchestrates:
# 1. A DMS replication task (PostgreSQL -> S3)
# 2. An EMR cluster step (create, run, and auto-terminate)

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

locals {
  mwaa_env_name = "imba-pipeline"
}


resource "aws_mwaa_environment" "this" {
  name                 = local.mwaa_env_name
  airflow_version      = "2.10.3"
  environment_class    = "mw1.micro"
  dag_s3_path          = "scripts/mwaa/dag/"
  requirements_s3_path = "scripts/mwaa/requirements.txt"
  # plugins_s3_path      = "scripts/mwaa/plugins/"
  source_bucket_arn  = var.dag_bucket_arn
  execution_role_arn = aws_iam_role.mwaa_exec.arn
  network_configuration {
    security_group_ids = var.mwaa_security_group_id
    subnet_ids         = var.private_subnet_ids
  }
  webserver_access_mode = "PUBLIC_ONLY"

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }
    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }
    task_logs {
      enabled   = true
      log_level = "INFO"
    }
    webserver_logs {
      enabled   = true
      log_level = "INFO"
    }
    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }

  airflow_configuration_options = {
    "core.load_default_connections" = "false" # prevent MWAA from creating connections
    "core.load_examples"            = "false"
    "webserver.dag_default_view"    = "graph"
    "webserver.dag_orientation"     = "TB"
  }
}

resource "aws_iam_role" "mwaa_exec" {
  name = "MWAAExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement : [
      {
        Effect = "Allow",
        Principal = {
          Service = "airflow-env.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "mwaa_combined_policy" {
  name        = "MWAACombinedAccessPolicy"
  description = "Permissions for MWAA to access S3, EMR, DMS, CloudWatch, SQS, etc."

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [

      # Optional: Block list-all-buckets
      {
        Effect = "Deny",
        Action = "s3:ListAllMyBuckets",
        Resource = [
          var.dag_bucket_arn,
          "${var.dag_bucket_arn}/*"
        ]
      },

      # S3 Access for DAGs, logs, etc.
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject*",
          "s3:GetBucket*",
          "s3:List*"
        ],
        Resource = [
          var.dag_bucket_arn,
          "${var.dag_bucket_arn}/*"
        ]
      },

      # Required when account-level public access is blocked
      {
        Effect   = "Allow",
        Action   = "s3:GetAccountPublicAccessBlock",
        Resource = "*"
      },

      # CloudWatch Logs
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:CreateLogGroup",
          "logs:PutLogEvents",
          "logs:GetLogEvents",
          "logs:GetLogRecord",
          "logs:GetLogGroupFields",
          "logs:GetQueryResults",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents"
        ],
        Resource = [
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:airflow-${local.mwaa_env_name}-*",
          "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:airflow-*:*"
        ]
      },
      {
        Effect   = "Allow",
        Action   = "logs:DescribeLogGroups",
        Resource = "*"
      },

      # CloudWatch Metrics
      {
        Effect   = "Allow",
        Action   = "cloudwatch:PutMetricData",
        Resource = "*"
      },

      # SQS for CeleryExecutor
      {
        Effect = "Allow",
        Action = [
          "sqs:ChangeMessageVisibility",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
          "sqs:SendMessage"
        ],
        Resource = "arn:aws:sqs:${var.region}:*:airflow-celery-*"
      },

      # Optional: airflow:PublishMetrics (if publishing metrics to MWAA env)
      # The WebServer access policy, allow the user/role to access the API.
      {
        Effect = "Allow",
        Action = [
          "airflow:PublishMetrics",
          "airflow:GetEnvironment",
          "airflow:CreateCliToken"
        ],
        Resource = "arn:aws:airflow:${var.region}:${data.aws_caller_identity.current.account_id}:environment/${local.mwaa_env_name}"
      },

      # DMS actions
      {
        Effect = "Allow",
        Action = [
          "dms:StartReplicationTask",
          "dms:DescribeReplicationTasks"
        ],
        Resource = var.dms_task_arn
      },

      # EMR actions (correct service prefix)
      {
        Effect = "Allow",
        Action = [
          "elasticmapreduce:RunJobFlow",
          "elasticmapreduce:DescribeCluster",
          "elasticmapreduce:TerminateJobFlows",
          "elasticmapreduce:AddJobFlowSteps",
          "elasticmapreduce:DescribeStep",
          "iam:PassRole"
        ],
        Resource = "*"
      },


      # Optional: KMS (only if you're using CMKs)
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*",
          "kms:Encrypt"
        ],
        NotResource = "arn:aws:kms:*:${data.aws_caller_identity.current.account_id}:key/*",
        Condition = {
          StringLike = {
            "kms:ViaService" = [
              "sqs.${var.region}.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_combined_policy" {
  role       = aws_iam_role.mwaa_exec.name
  policy_arn = aws_iam_policy.mwaa_combined_policy.arn
}


#-------------------
# DAG script
#-------------------
resource "local_file" "generated_dag" {
  content = templatefile("${path.module}/../../scripts/dag/dms_to_emr_pipeline.py.tmpl", {
    dms_task_arn         = var.dms_task_arn
    script_s3_path       = "s3://${var.dag_bucket_name}/scripts/pyspark/bronze_to_silver.py"
    log_uri              = "s3://${var.dag_bucket_name}/emr-logs/"
    emr_role             = var.emr_role
    ec2_instance_profile = var.emr_ec2_instance_profile
    subnet_id            = var.subnet_id
    emr_sg_master        = var.emr_sg_master
    emr_sg_core          = var.emr_sg_core
    emr_sg_service       = var.emr_sg_service
    # emr_ec2_instance_profile = var.emr_ec2_instance_profile
  })

  filename = "${path.module}/../../scripts/dag/dms_to_emr_pipeline.py"
}


resource "aws_s3_object" "dag_script" {
  bucket = var.dag_bucket_name
  key    = "scripts/mwaa/dag/dms_to_emr_pipeline.py"
  source = "${path.module}/../../scripts/dag/dms_to_emr_pipeline.py"
  etag   = filemd5("${path.module}/../../scripts/dag/dms_to_emr_pipeline.py")
}

resource "aws_s3_object" "requirements_txt" {
  bucket = var.dag_bucket_name
  key    = "scripts/mwaa/requirements.txt"
  source = "${path.module}/../../scripts/requirements"
  etag   = filemd5("${path.module}/../../scripts/requirements.txt")
}


# Replace with your values
# DMS_TASK_ARN = "arn:aws:dms:ap-southeast-2:ACCOUNT_ID:task:PFEKC7XIOVGTXBULAGD4BTNCXM"
# SCRIPT_S3_PATH = "s3://source-bucket-chien/scripts/pyspark/bronze_to_silver.py"
# LOG_URI = "s3://source-bucket-chien/emr-logs/"
# EMR_ROLE = "EMR_DefaultRole"
# EC2_ROLE = "EMR_EC2_DefaultRole"
# SUBNET_ID = "subnet-0e85153f57935e0cd"
# EMR_MASTER_SG_ID = "sg-033e5772afa0c3d12"
# EMR_CORE_SG_ID = "sg-0decf60199244d66a"
# EMR_SERVICE_SG_ID = "sg-07e6dd4da3823202b"

# EMR_SECURITY_GROUPS = {
#     "master": EMR_MASTER_SG_ID,
#     "core": EMR_CORE_SG_ID,
#     "service": EMR_SERVICE_SG_ID
# }
