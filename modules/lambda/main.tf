resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.name}-lambda-role"

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

  tags = var.tags
}

resource "aws_iam_policy" "lambda_s3_secrets_policy" {
  name = "${var.name}-lambda-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::${var.s3_bucket}",
          "arn:aws:s3:::${var.s3_bucket}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = "*"
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

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_s3_secrets_policy.arn
}

resource "aws_s3_object" "snowflake_layer" {
  bucket = var.s3_bucket
  key    = "layers/snowflake-layer.zip"
  source = "${path.module}/layers/snowflake-layer.zip"
  etag   = filemd5("${path.module}/layers/snowflake-layer.zip")
}

resource "aws_s3_object" "pyarrow_layer" {
  bucket = var.s3_bucket
  key    = "layers/pyarrow-layer.zip"
  source = "${path.module}/layers/pyarrow-layer.zip"
  etag   = filemd5("${path.module}/layers/pyarrow-layer.zip")
}


resource "aws_lambda_layer_version" "snowflake" {
  layer_name          = "snowflake-layer"
  s3_bucket           = var.s3_bucket
  s3_key              = aws_s3_object.snowflake_layer.key
  compatible_runtimes = ["python3.12"]
  description         = "Snowflake Connector"
}

resource "aws_lambda_layer_version" "pyarrow" {
  layer_name          = "pyarrow-layer"
  s3_bucket           = var.s3_bucket
  s3_key              = aws_s3_object.pyarrow_layer.key
  compatible_runtimes = ["python3.12"]
  description         = "PyArrow"
}

resource "aws_lambda_function" "this" {
  function_name = var.name
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.timeout
  memory_size   = 512

  filename         = "${path.module}/${var.lambda_package}"
  source_code_hash = filebase64sha256("${path.module}/${var.lambda_package}")

  environment {
    variables = var.environment_variables
  }

  # layers = [
  #   "arn:aws:lambda:ap-southeast-2:794038230051:layer:pyarrow-layer:3",
  #   "arn:aws:lambda:ap-southeast-2:794038230051:layer:snowflake-layer:18"
  # ]

  layers = [
    aws_lambda_layer_version.snowflake.arn,
    aws_lambda_layer_version.pyarrow.arn
  ]

  tags = var.tags
}
