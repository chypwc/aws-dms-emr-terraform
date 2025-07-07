import os
import json
import boto3
import pyarrow as pa
import pyarrow.parquet as pq
import snowflake.connector
from io import BytesIO
from datetime import datetime
import socket

def test_connectivity():
    try:
        socket.create_connection(("snowflakecomputing.com", 443), timeout=5)
        print("✅ Internet connection: OK")
    except Exception as e:
        print("❌ Internet connection error:", e)

def get_snowflake_credentials(secret_name):
    """Fetch Snowflake credentials from AWS Secrets Manager"""
    client = boto3.client("secretsmanager")
    secret_value = client.get_secret_value(SecretId=secret_name)
    return json.loads(secret_value["SecretString"])

def write_parquet_to_s3(table, bucket, key):
    """Write an Arrow Table to S3 in Parquet format"""
    buffer = BytesIO()
    pq.write_table(table, buffer)
    buffer.seek(0)

    s3 = boto3.client("s3")
    s3.upload_fileobj(buffer, bucket, key)
    print(f"✅ Uploaded to s3://{bucket}/{key}")

def lambda_handler(event, context):
    # Optional connectivity check
    # test_connectivity()

    secret_name = os.environ["SNOWFLAKE_SECRET_NAME"]
    s3_bucket = os.environ["S3_OUTPUT_BUCKET"]

    today = datetime.utcnow()
    date_prefix = f"{today.year:04d}/{today.month:02d}/{today.day:02d}"

    tables = [
        "products",
        "aisles",
        "departments",
        "orders",
        "order_products__prior",
        "order_products__train"
    ]

    creds = get_snowflake_credentials(secret_name)

    conn = snowflake.connector.connect(
        user=creds["USERNAME"],
        password=creds["PASSWORD"],
        account=creds["ACCOUNT"],
        warehouse=creds["sfWarehouse"],
        database=creds["sfDatabase"],
        schema=creds["sfSchema"],
        role=creds.get("sfRole")
    )

    try:
        with conn.cursor() as cur:
            for table in tables:
                batch_size = 300000
                print(f"🔄 Fetching {table}...")

                cur.execute(f"SELECT * FROM {table}")
                column_names = [desc[0] for desc in cur.description]

                counter = 0
                while True:
                    rows = cur.fetchmany(batch_size)
                    if not rows:
                        break

                    # Transpose rows to columns
                    columns = list(zip(*rows)) if rows else []
                    arrays = [pa.array(col) for col in columns]
                    batch = pa.record_batch(arrays, names=column_names)
                    table_arrow = pa.Table.from_batches([batch])

                    s3_key = f"snowflake-parquet/{table}/{date_prefix}/part_{counter:05d}.parquet"
                    write_parquet_to_s3(table_arrow, s3_bucket, s3_key)
                    print(f"✅ Uploaded batch {counter} for {table}")
                    counter += 1

        return {
            "statusCode": 200,
            "body": f"Tables saved under snowflake-parquet/{date_prefix}/"
        }

    except Exception as e:
        print("❌ Error:", e)
        return {"statusCode": 500, "body": str(e)}

    finally:
        conn.close()