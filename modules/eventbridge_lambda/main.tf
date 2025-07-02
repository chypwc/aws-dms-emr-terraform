# Create an IAM role for lambda function:  "Action": "dms:StartReplicationTask"
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda-dms-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy" "lambda_dms_policy" {
  name = "lambda-dms-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dms:StartReplicationTask",
          "dms:DescribeReplicationTasks"
        ],
        Resource = "*" # Or restrict to known task ARNs
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_dms_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_dms_policy.arn
}

# Zip lambda python script
# -j option means: “junk the directory info” — so only the file is zipped, not the folder structure.

resource "null_resource" "zip_lambda" {
  provisioner "local-exec" {
    command = "zip -j ${path.module}/lambda.zip ${path.module}/lambda_scripts/start_dms_task.py"
  }

  # Terraform uses the SHA1 hash of the script file as a trigger
  triggers = {
    script_hash = filesha1("${path.module}/lambda_scripts/start_dms_task.py")
  }
}

# Create a lambda function to StartReplicationTask
resource "aws_lambda_function" "start_dms_task" {
  filename         = "${path.module}/lambda.zip" # zip your Python script
  function_name    = "start-dms-task"
  handler          = "start_dms_task.lambda_handler"
  role             = aws_iam_role.lambda_exec_role.arn
  runtime          = "python3.12"
  source_code_hash = filebase64sha256("lambda.zip")

  depends_on = [null_resource.zip_lambda]

  environment {
    variables = {
      DMS_TASK_ARNS = join(",", var.dms_task_arns)
    }
  }
}

# Define the CloudWatch Event Rule
resource "aws_cloudwatch_event_rule" "dms_trigger" {
  name                = "trigger-dms-task"
  schedule_expression = "cron(0 1 * * ? *)" # Daily at 1 AM UTC
}

# triggers an AWS Lambda function, which will then call StartReplicationTask.
resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.dms_trigger.name
  target_id = "StartDmsTaskLambda"
  arn       = aws_lambda_function.start_dms_task.arn
}

#  Lambda Permissions for EventBridge
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.start_dms_task.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.dms_trigger.arn
}
