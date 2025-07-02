data "aws_secretsmanager_secret" "postgres" {
  name = var.postgresql_secret_name
}

# update host IP
data "external" "updated_secret_json" {
  program = ["python3", "${path.module}/update_secret_host.py"]

  query = {
    secret_name = var.postgresql_secret_name
    host        = var.server_name # the new private IP
  }
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id     = data.aws_secretsmanager_secret.postgres.id
  secret_string = data.external.updated_secret_json.result["updated_secret"]
}

# DMS service role
resource "aws_iam_role" "dms_service_role" {
  name = "DMSExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = [
            "dms.amazonaws.com",
            "dms.ap-southeast-2.amazonaws.com"
          ]
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "dms_custom_policy" {
  name = "DMSCustomPolicy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "kms:Decrypt"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_dms_policy" {
  role       = aws_iam_role.dms_service_role.name
  policy_arn = aws_iam_policy.dms_custom_policy.arn
}

# DMS Subnet Group
resource "aws_dms_replication_subnet_group" "dms_subnet_group" {
  replication_subnet_group_id          = "dms-subnet-group"
  replication_subnet_group_description = "Subnet group for DMS replication instance"
  subnet_ids                           = var.subnet_ids
}


# DMS Replication Instance
resource "aws_dms_replication_instance" "dms_instance" {
  replication_instance_id     = "dms-replication-instance"
  replication_instance_class  = "dms.t3.medium"
  allocated_storage           = 100
  engine_version              = "3.6.0"
  replication_subnet_group_id = aws_dms_replication_subnet_group.dms_subnet_group.replication_subnet_group_id
  vpc_security_group_ids      = var.dms_security_group_ids
  publicly_accessible         = true
  auto_minor_version_upgrade  = true
  multi_az                    = false
  apply_immediately           = true
  tags = {
    Name = "dms-replication-instance"
  }
}

# DMS PostgreSQL Source Endpoint
resource "aws_dms_endpoint" "postgres_source" {
  endpoint_id                     = "postgresql-source"
  endpoint_type                   = "source"
  engine_name                     = "postgres"
  database_name                   = "imba"
  ssl_mode                        = "none"
  secrets_manager_access_role_arn = aws_iam_role.dms_service_role.arn
  secrets_manager_arn             = data.aws_secretsmanager_secret.postgres.arn

  # extra_connection_attributes = join(";", [
  #   "SecretsManagerAccessRoleArn=${aws_iam_role.dms_service_role.arn}",
  #   "SecretsManagerSecretId=${var.postgresql_secret_name}"
  # ])
}


#---------------------
# DMS Tasks and S3 endpoints
#---------------------
# locals {
#   dms_tasks = {
#     "orders" = {
#       table_name = "orders"
#       s3_prefix  = "imba-raw/orders"
#     },
#     "products" = {
#       table_name = "products"
#       s3_prefix  = "imba-raw/products"
#     },
#     "departments" = {
#       table_name = "departments"
#       s3_prefix  = "imba-raw/departments"
#     },
#     "aisles" = {
#       table_name = "aisles"
#       s3_prefix  = "imba-raw/aisles"
#     },
#     "order-products-train" = {
#       table_name = "order_products__train"
#       s3_prefix  = "imba-raw/order_products"
#     },
#     "order-products-prior" = {
#       table_name = "order_products__prior"
#       s3_prefix  = "imba-raw/order_products"
#     }
#   }
# }

# DMS S3 Target Endpoint
resource "aws_dms_s3_endpoint" "s3_target" {
  # for_each = local.dms_tasks

  endpoint_id   = "dms-s3-target" # "dms-s3-target-${each.key}"
  endpoint_type = "target"

  bucket_name   = var.s3_bucket_name
  bucket_folder = var.bucket_folder # each.value.s3_prefix
  # add_column_name          = false  # for cdc 
  # cdc_path                 = "" // <== disables default schema/table suffix
  # date_partition_enabled = true  # cdc
  # date_partition_sequence  = "YYYYMMDD" # cdc optional, default is this format
  # date_partition_delimiter = "SLASH"    # cdc default is "/"
  data_format             = "parquet"
  parquet_version         = "parquet-1-0"
  compression_type        = "gzip" # Only "gzip" or "none" supported for DMS
  enable_statistics       = false
  max_file_size           = 128000
  service_access_role_arn = aws_iam_role.dms_service_role.arn
}

resource "aws_dms_replication_task" "tables" {
  # for_each = local.dms_tasks

  replication_task_id      = "imba-tables" # "${each.key}-table"
  migration_type           = "full-load"   # or full-load-and-cdc
  replication_instance_arn = aws_dms_replication_instance.dms_instance.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.postgres_source.endpoint_arn
  target_endpoint_arn      = aws_dms_s3_endpoint.s3_target.endpoint_arn # aws_dms_s3_endpoint.s3_target[each.key].endpoint_arn

  table_mappings = jsonencode({
    rules = [
      {
        "rule-type" : "selection",
        "rule-id" : "1",
        "rule-name" : "select", # "select-${each.key}",
        "object-locator" : {
          "schema-name" : "public",
          "table-name" : "%" # each.value.table_name
        },
        "rule-action" : "include"
      },
    ]
  })

  replication_task_settings = file("${path.module}/dms-task-settings.json")
  start_replication_task    = false # do not run after creating task

}
