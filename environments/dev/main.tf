module "s3_buckets" {
  source       = "../../modules/s3_buckets"
  bucket_names = [var.source_bucket, var.destination_bucket]
}

module "vpc" {
  source               = "../../modules/vpc"
  env                  = "dev"
  vpc_cidr_block       = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
  region               = var.region
}

module "ec2" {
  source                      = "../../modules/ec2"
  env                         = "dev"
  ami_id                      = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_id                      = module.vpc.vpc_id
  public_subnet_id            = module.vpc.public_subnet_ids[0]
  private_subnet_id           = module.vpc.private_subnet_ids[0]
  postgres_security_group_ids = [module.vpc.postgres_security_group_id]
  bastion_security_group_ids  = [module.vpc.bastion_security_group_id]
  region                      = var.region
  depends_on                  = [module.vpc]
}

module "glue_catalog_table" {
  source               = "../../modules/glue_catalog"
  raw_data_bucket      = var.raw_data_bucket
  raw_data_folder      = var.raw_data_folder
  raw_database_name    = var.raw_database_name
  silver_data_bucket   = var.silver_data_bucket
  silver_data_folder   = var.silver_data_folder
  silver_database_name = var.silver_database_name
}

module "dms" {
  source                 = "../../modules/dms"
  postgresql_secret_name = var.postgresql_secret_name
  s3_bucket_name         = var.raw_data_bucket
  bucket_folder          = var.raw_data_folder
  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnet_ids
  region                 = var.region
  dms_security_group_ids = [module.vpc.dms_security_group_id]
  server_name            = module.ec2.postgres_private_ip
}



module "emr" {
  source                            = "../../modules/emr"
  subnet_id                         = module.vpc.private_subnet_ids[0]
  emr_managed_master_security_group = module.vpc.emr_managed_master_security_group
  emr_core_sg_id                    = module.vpc.emr_core_sg_id
  emr_service_access_sg_id          = module.vpc.emr_service_access_sg_id
  key_name                          = var.key_name
  raw_data_bucket                   = var.raw_data_bucket
  silver_data_bucket                = var.silver_data_bucket
  silver_data_folder                = var.silver_data_folder
  log_bucket                        = var.source_bucket
  script_bucket                     = var.source_bucket

  depends_on = [module.vpc]

}

module "mwaa" {
  source                   = "../../modules/mwaa"
  region                   = var.region
  vpc_id                   = module.vpc.vpc_id
  private_subnet_ids       = module.vpc.private_subnet_ids
  dag_bucket_arn           = module.s3_buckets.bucket_arns[0]
  dag_bucket_name          = var.source_bucket
  mwaa_security_group_id   = [module.vpc.mwaa_security_group_id]
  depends_on               = [module.vpc]
  dms_task_arn             = module.dms.dms_task_arn
  emr_role                 = module.emr.emr_role.name
  emr_ec2_instance_profile = module.emr.emr_ec2_instance_profile.name
  subnet_id                = module.vpc.private_subnet_ids[0]
  emr_sg_master            = module.vpc.emr_managed_master_security_group
  emr_sg_core              = module.vpc.emr_core_sg_id
  emr_sg_service           = module.vpc.emr_service_access_sg_id
}


module "lambda" {
  source = "../../modules/lambda"

  name           = "data-ingestion-snowflake"
  lambda_package = "lambda_package.zip"
  handler        = "lambda_function.lambda_handler"
  runtime        = "python3.12"
  timeout        = 600
  s3_bucket      = var.source_bucket
  environment_variables = {
    S3_OUTPUT_BUCKET      = var.raw_data_bucket
    SNOWFLAKE_SECRET_NAME = "snowflake"
  }
  # tags = {
  #   Project = "data-pipeline"
  # }
}
