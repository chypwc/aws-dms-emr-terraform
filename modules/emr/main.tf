# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# EMR Service Role
resource "aws_iam_role" "emr_service_role" {
  name = "EMR_DefaultRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "elasticmapreduce.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS managed policy for EMR service role
resource "aws_iam_role_policy_attachment" "emr_service_role_policy" {
  role       = aws_iam_role.emr_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole"
}

# EMR EC2 Instance Role
resource "aws_iam_role" "emr_ec2_instance_role" {
  name = "EMR_EC2_DefaultRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS managed policy for EMR EC2 instances
resource "aws_iam_role_policy_attachment" "emr_ec2_instance_role_policy" {
  role       = aws_iam_role.emr_ec2_instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role"
}

# CRITICAL: Add Glue Catalog permissions to EMR EC2 role
resource "aws_iam_role_policy" "emr_glue_catalog_policy" {
  name = "EMRGlueCatalogPolicy"
  role = aws_iam_role.emr_ec2_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:GetCatalog",
          "glue:CreateDatabase",
          "glue:UpdateDatabase",
          "glue:DeleteDatabase",
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:DeleteTable",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetTableVersions",
          "glue:CreatePartition",
          "glue:BatchCreatePartition",
          "glue:UpdatePartition",
          "glue:DeletePartition",
          "glue:BatchDeletePartition",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition",
          "glue:GetCatalogImportStatus"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.raw_data_bucket}/*",
          "arn:aws:s3:::${var.raw_data_bucket}",
          "arn:aws:s3:::${var.silver_data_bucket}/*",
          "arn:aws:s3:::${var.silver_data_bucket}",
          "arn:aws:s3:::${var.log_bucket}/*",
          "arn:aws:s3:::${var.log_bucket}"
        ]
      }
    ]
  })
}

# EMR EC2 Instance Profile
resource "aws_iam_instance_profile" "emr_ec2_instance_profile" {
  name = "emr_ec2_instance_profile"
  role = aws_iam_role.emr_ec2_instance_role.name
}

# EMR cluster
resource "aws_emr_cluster" "transform-cluster" {
  name          = "features-emr-cluster"
  release_label = "emr-7.6.0"
  applications  = ["Hive", "Spark"]

  service_role     = aws_iam_role.emr_service_role.arn
  autoscaling_role = aws_iam_role.emr_service_role.arn

  ec2_attributes {
    subnet_id                         = var.subnet_id
    emr_managed_master_security_group = var.emr_managed_master_security_group
    emr_managed_slave_security_group  = var.emr_core_sg_id
    service_access_security_group     = var.emr_service_access_sg_id
    instance_profile                  = aws_iam_instance_profile.emr_ec2_instance_profile.arn
    key_name                          = var.key_name # ssh key pair
  }

  master_instance_group {
    instance_type  = "m5.xlarge"
    instance_count = 1
  }

  core_instance_group {
    instance_type  = "m5.xlarge"
    instance_count = 1
  }

  log_uri                           = "s3://${var.log_bucket}/emr-logs/"
  termination_protection            = false
  keep_job_flow_alive_when_no_steps = true

  configurations_json = jsonencode([
    {
      Classification = "spark-hive-site"
      Properties = {
        "hive.metastore.client.factory.class" = "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory"
        "hive.metastore.glue.catalogid"       = data.aws_caller_identity.current.account_id
      }
    },
    {
      Classification = "iceberg-defaults"
      Properties = {
        "iceberg.enabled" = "true"
      }
    }
  ])

  step {
    name              = "pyspark_step"
    action_on_failure = "CONTINUE"

    hadoop_jar_step {
      jar = "command-runner.jar"
      args = [
        "spark-submit",
        "--deploy-mode", "cluster",
        "--master", "yarn",
        "s3://${var.script_bucket}/scripts/pyspark/bronze_to_silver.py"
      ]
    }
  }

  tags = {
    Name = "EMRCluster"
    Env  = var.env
  }
}
