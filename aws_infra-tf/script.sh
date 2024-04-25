#!/bin/bash
yum update -y
yum install -y python3
curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
python3 get-pip.py
pip install boto3 pandas pyarrow


cat <<EOF > /tmp/my_python_script.py
import subprocess

subprocess.run(["chmod", "+x", "/tmp/my_python_script.py"])
import boto3
import pandas as pd
import json
from io import BytesIO

# Initialize SQS and S3 clients
sqs = boto3.client('sqs', region_name='us-east-1')
s3 = boto3.client('s3', region_name='us-east-1')

# SQS Queue URL
queue_url = 'https://sqs.us-east-1.amazonaws.com/767398004979/mss_dev_us-east-1_demo_arya-queue'

# S3 Bucket Name
bucket_name = 'mss-dev-us-east-1-demo-arya-bucket'
target_bucket_name = 'mss-dev-us-east-1-demo-arya-upload-bucket'

def process_message(message):
    print("Recieved message:", message)
    if 'Body' in message:
        body = json.loads(message['Body'])
        if 'Message' in body:
            message_body = json.loads(body['Message'])
            if 'Records' in message_body:
                # Get S3 bucket and key from SQS message
                s3_info = message_body['Records'][0]['s3']
                bucket = s3_info['bucket']['name']
                key = s3_info['object']['key']

                # Download CSV file from S3
                response = s3.get_object(Bucket=bucket, Key=key)
                csv_content = response['Body'].read()
                print(f"Downloaded file {key} from bucket {bucket}")
                # Convert CSV to Pandas DataFrame
                df = pd.read_csv(BytesIO(csv_content))

                # Convert DataFrame to Parquet format
                parquet_buffer = BytesIO()
                df.to_parquet(parquet_buffer, index=False)

                # Upload Parquet file to S3
                parquet_buffer.seek(0)
                parquet_key = key.replace('.csv', '.parquet')
                s3.put_object(Bucket=target_bucket_name, Key=parquet_key, Body=parquet_buffer)
                print(f"Uploaded file {parquet_key} to bucket {target_bucket_name}")
            else:
                print("No Records key found in the message")
        else:
            print("No message key found in the message")
    else:
        print("No, body key found in the message")

def main():
    while True:
        # Receive messages from SQS
        response = sqs.receive_message(
            QueueUrl=queue_url,
            MaxNumberOfMessages=1,
            VisibilityTimeout=60,
            WaitTimeSeconds=20
        )

        if 'Messages' in response:
            for message in response['Messages']:
                process_message(message)
                # Delete processed message from SQS
                sqs.delete_message(
                    QueueUrl=queue_url,
                    ReceiptHandle=message['ReceiptHandle']
                )
        else:
            print("No messages in queue.")
            break

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        # Log any exceptions to a file
        with open("/tmp/script.log", "a") as log_file:
            log_file.write(f"Error: {str(e)}\n")
            sys.exit(1)
EOF
python3 /tmp/my_python_script.py