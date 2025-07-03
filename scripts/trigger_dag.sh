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

# Remove existing aws CLI v1 if needed
sudo rm -rf /usr/bin/aws

# Clean up any previous installs
rm -rf ./aws awscliv2.zip
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -o -q awscliv2.zip
sudo ./aws/install --update
export PATH=/usr/local/bin:$PATH  # ensure the new CLI is found first
aws --version  # should show aws-cli/2.x.x

# Get MWAA CLI token and hostname
CLI_JSON=$(aws mwaa --region "$REGION" create-cli-token --name "$ENV_NAME")

CLI_TOKEN=$(echo "$CLI_JSON" | jq -r '.CliToken')
WEB_SERVER_HOSTNAME=$(echo "$CLI_JSON" | jq -r '.WebServerHostname')

# Unpause the DAG before triggering
UNPAUSE_RESULT=$(curl --silent --request POST "https://${WEB_SERVER_HOSTNAME}/aws_mwaa/cli" \
  --header "Authorization: Bearer ${CLI_TOKEN}" \
  --header "Content-Type: text/plain" \
  --data-raw "dags unpause ${DAG_NAME}")

# Optional: Print unpause output
echo "Unpause Result:"
echo "$UNPAUSE_RESULT" | jq -r '.stdout' | base64 --decode || echo "[No stdout]"
echo -e "\nUnpause Errors:"
echo "$UNPAUSE_RESULT" | jq -r '.stderr' | base64 --decode || echo "[No stderr]"

# Trigger DAG using MWAA CLI endpoint
CLI_RESULTS=$(curl --silent --request POST "https://${WEB_SERVER_HOSTNAME}/aws_mwaa/cli" \
  --header "Authorization: Bearer ${CLI_TOKEN}" \
  --header "Content-Type: text/plain" \
  --data-raw "dags trigger ${DAG_NAME}")

# Output results
echo "Output:" | tee ~/mwaa_dag_output.log
echo "$CLI_RESULTS" | jq -r '.stdout' | base64 --decode | tee -a ~/mwaa_dag_output.log || echo "[No stdout]" | tee -a ~/mwaa_dag_output.log
echo -e "\nErrors:" | tee -a ~/mwaa_dag_output.log
echo "$CLI_RESULTS" | jq -r '.stderr' | base64 --decode | tee -a ~/mwaa_dag_output.log || echo "[No stderr]" | tee -a ~/mwaa_dag_output.log

# chmod +x trigger_dag.sh
# ./trigger_dag.sh

