from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import when, col, lower
from pyspark.sql import functions as F
from pyspark.sql.window import Window
import sys
import logging
import traceback

# Also silence the noisy JVM logs
logger = logging.getLogger("py4j")
logger.setLevel(logging.INFO)

class DataProcessor:
    def __init__(self):
        self.data_bucket = sys.argv[1] if len(sys.argv) > 1 else "destination-bucket-chien" 
        self.raw_database = sys.argv[2] if len(sys.argv) > 2 else "imba_raw"  
        self.silver_database = "imba_silver"  # Always use imba_silver for output
        self.silver_data_folder = sys.argv[3] if len(sys.argv) > 3 else "imba-silver"  
        
        # Validate inputs to prevent empty paths
        if not self.data_bucket or self.data_bucket.strip() == "":
            raise ValueError("Data bucket cannot be empty")
        if not self.silver_data_folder or self.silver_data_folder.strip() == "":
            self.silver_data_folder = "imba_silver"
        
        # Clean up paths to prevent empty strings
        self.data_bucket = self.data_bucket.strip()
        self.silver_data_folder = self.silver_data_folder.strip().strip('/')
        warehouse_path = f"s3://{self.data_bucket}/{self.silver_data_folder}/"
        
        logging.info(f"Initializing Spark with warehouse path: {warehouse_path}")
        
        # There are 2 catalog (for reading and writing)
        # - spark_catalog remains as default Glue/Hive catalog (for Glue default tables),
    	# -	glue_catalog is the Iceberg catalog you use for writing.

        self.spark = SparkSession.builder \
            .appName("DataProcessing") \
            .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
            .config("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog") \
            .config("spark.sql.catalog.glue_catalog.catalog-impl", "org.apache.iceberg.aws.glue.GlueCatalog") \
            .config("spark.sql.catalog.glue_catalog.io-impl", "org.apache.iceberg.aws.s3.S3FileIO") \
            .config("spark.sql.catalog.glue_catalog.warehouse", f"s3://{self.data_bucket}/{self.silver_data_folder}/") \
            .config("spark.hadoop.hive.metastore.client.factory.class", 
                    "com.amazonaws.glue.catalog.metastore.AWSGlueDataCatalogHiveClientFactory") \
            .enableHiveSupport() \
            .getOrCreate()
        
            
        self.spark.sparkContext.setLogLevel("WARN")
                

    def read_table(self, table_name: str) -> DataFrame:
        """Read table from raw database"""
        # Read from spark_catalog, non-iceberg raw data
        return self.spark.read.table(f"spark_catalog.{self.raw_database}.{table_name}")

    def write_table(self, df: DataFrame, table_name: str) -> None:
        # Write to glue_catalog defined in configuration with iceberg
        df.writeTo(f"glue_catalog.{self.silver_database}.{table_name}") \
            .using("iceberg") \
            .tableProperty("format-version", "2") \
            .createOrReplace()
        

    def process_order_products__eval(self, df: DataFrame) -> DataFrame:
        # print("Before transform reordered: ")
        # df.select("reordered").discinct().show(10)
        df = df.withColumn(
            "reordered_int",
            when(lower(col("reordered").cast("string")) == "true", 1)
            .when(lower(col("reordered").cast("string")) == "false", 0)
            .otherwise(None)
        )
        # print("After transform reordered: ")
        # df.select("reordered_int").discinct().show(10)

        return df.drop("reordered").withColumnRenamed("reordered_int", "reordered")

    def process_order_products(self, order_products__prior_df: DataFrame, order_products__train_df: DataFrame) -> DataFrame:
        order_products = order_products__prior_df.unionByName(order_products__train_df)
        return order_products

    def process_order_products_prior(self, orders_df: DataFrame, order_products: DataFrame) -> DataFrame:
        orders_prior_df = orders_df.filter(col('eval_set')=='prior').repartition("order_id")
        order_products = order_products.repartition("order_id")
        return orders_prior_df.join(order_products, on="order_id", how="inner").select(
            orders_prior_df['*'], order_products['product_id'], order_products['add_to_cart_order'], order_products['reordered']
        )

    def process_user_features_1(self, orders_df: DataFrame) -> DataFrame:
        return orders_df.groupBy('user_id').agg(
            F.max('order_number').alias('max_order_num'),
            F.sum('days_since_prior').alias('sum_days_since_prior_order'),
            F.mean('days_since_prior').alias('avg_days_since_prior_order')
        )

    def process_user_features_2(self, order_products_prior: DataFrame) -> DataFrame:
        df = order_products_prior.withColumn(
            'reordered_flag', when(col('reordered') == 1, 1).otherwise(0)
        ).withColumn(
            'repeat_order_flag', when(col('order_number') > 1, 1).otherwise(None)
        )
        return df.groupBy('user_id').agg(
            F.count('product_id').alias('total_number_products'),
            F.countDistinct('product_id').alias('total_number_distinct_products'),
            (F.sum('reordered_flag') / F.count('repeat_order_flag')).alias('user_reorder_ratio')
        )

    def process_up_features(self, order_products_prior: DataFrame) -> DataFrame:
        return order_products_prior.groupBy(['user_id', 'product_id']).agg(
            F.count('order_id').alias('total_number_orders'),
            F.min('order_number').alias('min_order_number'),
            F.max('order_number').alias('max_order_number'),
            F.mean('add_to_cart_order').alias('avg_add_to_cart_order')
        )

    def process_prd_features(self, order_products_prior: DataFrame) -> DataFrame:
        window = Window.partitionBy('user_id', 'product_id').orderBy('order_number')
        df = order_products_prior.withColumn('product_seq_time', F.row_number().over(window))
        return df.groupBy('product_id').agg(
            F.count('*').alias('total_purchases'),
            F.sum(when(col('reordered') == 1, 1).otherwise(0)).alias('total_reorders'),
            F.sum(when(col('product_seq_time') == 1, 1).otherwise(0)).alias('first_time_purchases'),
            F.sum(when(col('product_seq_time') == 2, 1).otherwise(0)).alias('second_time_purchases')
        )

    def run(self):
        logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
        logger = logging.getLogger(__name__)

        try:
            logger.info(f"Reading tables from Glue Catalog database: {self.raw_database}")
            logger.info(f"Writing tables to Glue Catalog database: {self.silver_database}")
            
            # Read all raw tables
            print("🔥 Starting to read first table...")
            order_products__train_df = self.read_table("order_products__train")
            order_products__prior_df = self.read_table("order_products__prior")
            orders_df = self.read_table("orders")
            products_df = self.read_table("products")
            departments_df = self.read_table("departments")
            aisles_df = self.read_table("aisles")
            logger.info("Successfully loaded all raw tables.")
            
            # Process data
            order_products__train_df2 = self.process_order_products__eval(order_products__train_df)
            order_products__prior_df2 = self.process_order_products__eval(order_products__prior_df)
            order_products = self.process_order_products(order_products__prior_df2, order_products__train_df2)
            order_products_prior = self.process_order_products_prior(orders_df, order_products).cache()

            user_features_1 = self.process_user_features_1(orders_df)
            user_features_2 = self.process_user_features_2(order_products_prior)
            up_features = self.process_up_features(order_products_prior)
            prd_features = self.process_prd_features(order_products_prior)

            logger.info("Writing transformed tables to Iceberg format in silver database...")
            
            # Write other tables
            for name, df in [
                ("products", products_df),
                ("aisles", aisles_df),
                ("departments", departments_df),
                ("orders", orders_df),
                ("order_products__prior", order_products__prior_df2),
                ("order_products__train", order_products__train_df2),
                ("order_products", order_products),
                ("order_products_prior", order_products_prior),
                ("user_features_1", user_features_1),
                ("user_features_2", user_features_2),
                ("up_features", up_features),
                ("prd_features", prd_features),
            ]:
                logger.info(f"Writing table: {name}")
                print(f"🔥 Writing {name} to Iceberg format in silver database...")
                self.write_table(df, name)

            logger.info("✅ All processing completed successfully.")
            logger.info(f"✅ All tables written to {self.silver_database} database in Iceberg format")

        except Exception as e:
            logger.error("❌ An error occurred during processing.")
            logger.error(str(e))
            logger.debug(traceback.format_exc())
            raise

        finally:
            logger.info("Stopping Spark session.")
            self.spark.stop()

if __name__ == "__main__":
    processor = DataProcessor()
    processor.run()