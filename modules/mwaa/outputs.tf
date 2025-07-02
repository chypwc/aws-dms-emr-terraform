
# Upload your DAG file to s3://<bucket>/dags/dms_to_emr_pipeline.py

output "webserver_url" {
  value = aws_mwaa_environment.this.webserver_url
}

output "dag_s3_path" {
  value = "s3://${var.dag_bucket_name}/mwaa/dags/dms_to_emr_pipeline.py"
}

