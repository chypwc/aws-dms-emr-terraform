#!/bin/bash
set -e

# create log for debugging: /var/log/postgres-init.log
exec > >(tee /var/log/postgres-init.log|logger -t user-data -s 2>/dev/console) 2>&1
set -xe

# Update system packages and enable PostgreSQL
for i in {1..5}; do
  echo "Attempt $i: yum update"
  if sudo yum update -y; then
    echo "yum update succeeded"
    break
  else
    echo "yum update failed, sleeping 30s..."
    sleep 30
  fi
done
sudo yum install -y jq
sudo amazon-linux-extras enable postgresql14
sudo yum clean metadata
sudo yum install -y postgresql-server postgresql-contrib aws-cli

# Stop PostgreSQL if already running
sudo systemctl stop postgresql || true

# Initialize PostgreSQL database
sudo rm -rf /var/lib/pgsql/data
sudo mkdir /var/lib/pgsql/data
sudo chown postgres:postgres /var/lib/pgsql/data
sudo postgresql-setup --initdb

# Modify postgresql.conf for logical replication
sudo sed -i "s/^#*\s*wal_level\s*=.*$/wal_level = logical/" /var/lib/pgsql/data/postgresql.conf
sudo sed -i "s/^#*\s*max_wal_senders\s*=.*$/max_wal_senders = 10/" /var/lib/pgsql/data/postgresql.conf
sudo sed -i "s/^#*\s*max_replication_slots\s*=.*$/max_replication_slots = 10/" /var/lib/pgsql/data/postgresql.conf
sudo sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" /var/lib/pgsql/data/postgresql.conf

# Add pg_hba.conf line for replication, restrict to your VPC
echo "host replication all 0.0.0.0/0 md5" | sudo tee -a /var/lib/pgsql/data/pg_hba.conf
echo "host all all 0.0.0.0/0 md5" | sudo tee -a /var/lib/pgsql/data/pg_hba.conf


# Enable and start PostgreSQL service
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Set environment variables
export DB_NAME="${DB_NAME}"
export AWS_REGION="${AWS_REGION}"
export S3_BUCKET="${S3_BUCKET}"

SECRET_JSON=$(aws secretsmanager get-secret-value --region ${AWS_REGION} --secret-id postgresql_dms --query SecretString --output text)
export DB_USER=$(echo "$SECRET_JSON" | jq -r '.username')
export DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password')

# Create a new user with the specified password
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"

# Create a new database owned by the new user
sudo -u postgres createdb -O "$DB_USER" "$DB_NAME"

# Grant permissions
sudo -u postgres psql -d "$DB_NAME" -c "GRANT CONNECT ON DATABASE $DB_NAME TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT USAGE ON SCHEMA public TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO $DB_USER;"
sudo -u postgres psql -d "$DB_NAME" -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO $DB_USER;"
sudo -u postgres psql -c "ALTER ROLE $DB_USER WITH REPLICATION;"

sudo systemctl restart postgresql

# Fetch data and SQL script from S3
mkdir -p /tmp/data
aws s3 cp --recursive s3://${S3_BUCKET}/postgres/data/ /tmp/data/
aws s3 cp s3://${S3_BUCKET}/postgres/init/init.sql /tmp/init.sql

# Unzip CSVs
gunzip -c /tmp/data/order_products__prior.csv.gz > /tmp/data/order_products__prior.csv
gunzip -c /tmp/data/order_products__train.csv.gz > /tmp/data/order_products__train.csv

# Set permissions and execute SQL
sudo chown postgres:postgres /tmp/init.sql
find /tmp/data -name "*.csv" -exec sudo chown postgres:postgres {} \;
sudo -u postgres psql -d imba -f /tmp/init.sql