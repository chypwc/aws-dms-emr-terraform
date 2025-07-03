#!/bin/bash

# Exit on error
set -e

# Replace these with your actual values
REGION="ap-southeast-2"
ENV_NAME="imba-pipeline"
DAG_NAME="dms_to_emr_pipeline"

# Optional: Install jq if not already installed
if ! command -v jq &>/dev/null; then
  sudo yum update -y
  sudo amazon-linux-extras enable epel
  sudo yum install -y jq
fi

# Install AWS CLI v2 (if not already available)
if ! command -v aws &> /dev/null; then
  sudo yum install -y unzip
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
fi

# Get MWAA CLI token and hostname
CLI_JSON=$(aws mwaa --region "$REGION" create-cli-token --name "$ENV_NAME")

CLI_TOKEN=$(echo "$CLI_JSON" | jq -r '.CliToken')
WEB_SERVER_HOSTNAME=$(echo "$CLI_JSON" | jq -r '.WebServerHostname')

# Trigger DAG using MWAA CLI endpoint
CLI_RESULTS=$(curl --silent --request POST "https://${WEB_SERVER_HOSTNAME}/aws_mwaa/cli" \
  --header "Authorization: Bearer ${CLI_TOKEN}" \
  --header "Content-Type: text/plain" \
  --data-raw "dags trigger ${DAG_NAME}")

# Output results
echo "Output:"
echo "$CLI_RESULTS" | jq -r '.stdout' | base64 --decode || echo "[No stdout]"
echo -e "\nErrors:"
echo "$CLI_RESULTS" | jq -r '.stderr' | base64 --decode || echo "[No stderr]"

# chmod +x trigger_dag.sh
# ./trigger_dag.sh

