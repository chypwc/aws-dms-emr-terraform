variable "name" {
  type = string
}

variable "database_name" {
  type = string
}

variable "location" {
  type = string
}

variable "columns" {
  description = "List of columns for the Glue table"
  type = list(object({
    name = string
    type = string
  }))
}

variable "compression_type" {
  description = "Compression type for Parquet files"
  type        = string
  default     = "snappy"
  validation {
    condition     = contains(["gzip", "snappy"], var.compression_type)
    error_message = "Supported compression types are 'gzip' and 'snappy'."
  }
}
