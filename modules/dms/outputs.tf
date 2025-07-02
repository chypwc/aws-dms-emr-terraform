# output "dms_task_arns" {
#   value = [
#     for k in keys(local.dms_tasks) :
#     aws_dms_replication_task.tables[k].replication_task_arn
#   ]
# }

output "dms_task_arns" {
  value = [aws_dms_replication_task.tables.replication_task_arn]
}
