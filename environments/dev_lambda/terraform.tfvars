
env = "dev"

# S3
source_bucket      = "source-bucket-chien"
destination_bucket = "destination-bucket-chien"

# Glue tables
raw_data_bucket      = "source-bucket-chien"
raw_data_folder      = "imba-raw"
raw_database_name    = "imba_raw"
silver_data_bucket   = "destination-bucket-chien"
silver_data_folder   = "imba-silver"
silver_database_name = "imba_silver"

# EC2
ami_id        = "ami-03e5b56661e12efa2"
instance_type = "t2.micro"
key_name      = "Macbook"

# DMS
postgresql_secret_name = "postgresql_dms"

# lambda functions
