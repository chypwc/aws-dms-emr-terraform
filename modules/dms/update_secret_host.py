#!/usr/bin/env python3
import json
import boto3
import sys

def main():
    params = json.load(sys.stdin)
    secret_name = params["secret_name"]
    new_host = params["host"]

    client = boto3.client("secretsmanager")
    current_secret = client.get_secret_value(SecretId=secret_name)
    secret_dict = json.loads(current_secret["SecretString"])

    secret_dict["host"] = new_host

    print(json.dumps({"updated_secret": json.dumps(secret_dict)}))

if __name__ == "__main__":
    main()