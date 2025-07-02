
resource "aws_glue_catalog_database" "this" {
  name        = var.raw_database_name
  description = "Raw Glue database"
}

resource "aws_glue_catalog_database" "silver" {
  name        = var.silver_database_name
  description = "Silver Glue database"
}

locals {
  raw_data_path    = "s3://${var.raw_data_bucket}/${var.raw_data_folder}"
  silver_data_path = "s3://${var.silver_data_bucket}/${var.silver_data_folder}"
}

module "departments_table" {
  source           = "./table"
  name             = "departments"
  database_name    = var.raw_database_name
  compression_type = "gzip"
  location         = "${local.raw_data_path}/public/departments/"
  columns = [
    { name = "department_id", type = "int" },
    { name = "department", type = "string" }
  ]
  depends_on = [aws_glue_catalog_database.this]
}

module "aisles_table" {
  source           = "./table"
  name             = "aisles"
  database_name    = var.raw_database_name
  compression_type = "gzip"
  location         = "${local.raw_data_path}/public/aisles/"
  columns = [
    { name = "aisle_id", type = "int" },
    { name = "aisle", type = "string" }
  ]
  depends_on = [aws_glue_catalog_database.this]
}

module "products_table" {
  source           = "./table"
  name             = "products"
  database_name    = var.raw_database_name
  compression_type = "gzip"
  location         = "${local.raw_data_path}/public/products/"
  columns = [
    { name = "product_id", type = "int" },
    { name = "product_name", type = "string" },
    { name = "aisle_id", type = "int" },
    { name = "department_id", type = "int" }
  ]
  depends_on = [aws_glue_catalog_database.this]
}

module "orders_table" {
  source           = "./table"
  name             = "orders"
  database_name    = var.raw_database_name
  compression_type = "gzip"
  location         = "${local.raw_data_path}/public/orders/"
  columns = [
    { name = "order_id", type = "int" },
    { name = "user_id", type = "int" },
    { name = "eval_set", type = "string" },
    { name = "order_number", type = "int" },
    { name = "order_dow", type = "int" },
    { name = "order_hour_of_day", type = "int" },
    { name = "days_since_prior", type = "int" }
  ]
  depends_on = [aws_glue_catalog_database.this]
}


module "order_products__prior_table" {
  source           = "./table"
  name             = "order_products__prior"
  database_name    = var.raw_database_name
  compression_type = "gzip"
  location         = "${local.raw_data_path}/public/order_products__prior/"
  columns = [
    { name = "order_id", type = "int" },
    { name = "product_id", type = "int" },
    { name = "add_to_cart_order", type = "int" },
    { name = "reordered", type = "string" }
  ]
  depends_on = [aws_glue_catalog_database.this]
}

module "order_products__train_table" {
  source           = "./table"
  name             = "order_products__train"
  database_name    = var.raw_database_name
  compression_type = "gzip"
  location         = "${local.raw_data_path}/public/order_products__train/"
  columns = [
    { name = "order_id", type = "int" },
    { name = "product_id", type = "int" },
    { name = "add_to_cart_order", type = "int" },
    { name = "reordered", type = "string" }
  ]
  depends_on = [aws_glue_catalog_database.this]
}

# ---------------------------
#           Silver
# ---------------------------



# module "order_products" {
#   source           = "./table"
#   name             = "order_products"
#   database_name    = var.silver_database_name
#   compression_type = "snappy"
#   location         = "${local.silver_data_path}/order_products/"
#   columns = [
#     { name = "order_id", type = "int" },
#     { name = "product_id", type = "int" },
#     { name = "add_to_cart_order", type = "int" },
#     { name = "reordered", type = "tinyint" }
#   ]
#   depends_on = [aws_glue_catalog_database.this]
# }

# module "order_products_prior" {
#   source           = "./table"
#   name             = "order_products_prior"
#   database_name    = var.silver_database_name
#   compression_type = "snappy"
#   location         = "${local.silver_data_path}/order_products_prior/"
#   columns = [
#     { name = "order_id", type = "int" },
#     { name = "user_id", type = "int" },
#     { name = "eval_set", type = "string" },
#     { name = "order_number", type = "int" },
#     { name = "order_dow", type = "int" },
#     { name = "order_hour_of_day", type = "int" },
#     { name = "days_since_prior", type = "int" },
#     { name = "product_id", type = "int" },
#     { name = "add_to_cart_order", type = "int" },
#     { name = "reordered", type = "tinyint" }
#   ]
#   depends_on = [aws_glue_catalog_database.silver]
# }

# module "user_features_1_table" {
#   source           = "./table"
#   name             = "user_feature_1"
#   database_name    = var.silver_database_name
#   compression_type = "snappy"
#   location         = "${local.silver_data_path}/user_features_1/"
#   columns = [
#     { name = "user_id", type = "int" },
#     { name = "max_order_number", type = "int" },
#     { name = "sum_days_since_prior_order", type = "int" },
#     { name = "avg_days_since_prior_order", type = "int" }
#   ]
#   depends_on = [aws_glue_catalog_database.silver]
# }

# module "user_features_2_table" {
#   source           = "./table"
#   name             = "user_feature_2"
#   database_name    = var.silver_database_name
#   compression_type = "snappy"
#   location         = "${local.silver_data_path}/user_features_2/"
#   columns = [
#     { name = "user_id", type = "int" },
#     { name = "total_number_products", type = "int" },
#     { name = "total_number_distinct_products", type = "int" },
#     { name = "user_reorder_ratio", type = "double" }
#   ]
#   depends_on = [aws_glue_catalog_database.silver]
# }

# module "up_features_table" {
#   source           = "./table"
#   name             = "up_features"
#   database_name    = var.silver_database_name
#   compression_type = "snappy"
#   location         = "${local.silver_data_path}/up_features/"
#   columns = [
#     { name = "user_id", type = "int" },
#     { name = "product_id", type = "int" },
#     { name = "total_number_orders", type = "int" },
#     { name = "min_order_number", type = "int" },
#     { name = "max_order_number", type = "int" },
#     { name = "avg_add_to_cart_order", type = "double" }
#   ]
#   depends_on = [aws_glue_catalog_database.silver]
# }


# module "prd_features_table" {
#   source           = "./table"
#   name             = "prd_features"
#   database_name    = var.silver_database_name
#   compression_type = "snappy"
#   location         = "${local.silver_data_path}/prd_features/"
#   columns = [
#     { name = "product_id", type = "int" },
#     { name = "total_purchases", type = "int" },
#     { name = "total_reorders", type = "int" },
#     { name = "first_time_purchases", type = "int" },
#     { name = "second_time_purchases", type = "int" }
#   ]
#   depends_on = [aws_glue_catalog_database.silver]
# }
