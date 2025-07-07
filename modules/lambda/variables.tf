variable "name" {
  description = "Lambda function name"
  type        = string
}

variable "lambda_package" {
  description = "Path to zipped Lambda package"
  type        = string
  default     = "lambda_package.zip"
}

variable "handler" {
  description = "Function entrypoint (e.g. index.handler)"
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "runtime" {
  description = "Lambda runtime (e.g. python3.10)"
  type        = string
  default     = "python3.12"
}

variable "timeout" {
  description = "Lambda timeout in seconds"
  type        = number
  default     = 600
}

variable "s3_bucket" {
  description = "S3 bucket name to access"
  type        = string
}

# variable "secret_arns" {
#   description = "List of Secrets Manager secret ARNs"
#   type        = list(string)
# }

variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
