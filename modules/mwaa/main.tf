# Main Terraform file to deploy MWAA environment that orchestrates:
# 1. A DMS replication task (PostgreSQL -> S3)
# 2. An EMR cluster step (create, run, and auto-terminate)

locals {
  mwaa_env_name = "imba-pipeline"
}

resource "aws_mwaa_environment" "this" {
  name                 = local.mwaa_env_name
  airflow_version      = "2.10.1"
  environment_class    = "mw1.micro"
  dag_s3_path          = "mwaa/dags/"
  requirements_s3_path = "mwaa/requirements.txt"
  plugins_s3_path      = "mwaa/plugins/"
  source_bucket_arn    = var.dag_bucket_arn
  execution_role_arn   = aws_iam_role.mwaa_exec.arn
  network_configuration {
    security_group_ids = [] # Optionally add one
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

  assume_role_policy = data.aws_iam_policy_document.mwaa_trust.json
}

data "aws_iam_policy_document" "mwaa_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["airflow.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "dms_access" {
  name        = "MWAADMSAccessPolicy"
  description = "Allow MWAA to trigger DMS"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["dms:StartReplicationTask", "dms:DescribeReplicationTasks"],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "emr_access" {
  name        = "MWAAEMRAccessPolicy"
  description = "Allow MWAA to interact with EMR"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "emr:RunJobFlow",
          "emr:DescribeCluster",
          "emr:TerminateJobFlows",
          "emr:AddJobFlowSteps",
          "iam:PassRole"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_dms" {
  role       = aws_iam_role.mwaa_exec.name
  policy_arn = aws_iam_policy.dms_access.arn
}

resource "aws_iam_role_policy_attachment" "attach_emr" {
  role       = aws_iam_role.mwaa_exec.name
  policy_arn = aws_iam_policy.emr_access.arn
}


