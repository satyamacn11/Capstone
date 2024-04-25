import base64
import json
import os
import boto3
from botocore.exceptions import ClientError
import logging
import time

LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)

SRC_BUCKET = os.environ.get('USER_BUCKET')
SRC_DYNAMO = os.environ.get('DYNAMO_DB_TABLE')

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(SRC_DYNAMO)

def lambda_handler(event, context):
    # Get the file content from the POST request
    print(event)
    file_content_base64 = event['body']
    file_content = base64.b64decode(file_content_base64)

    # Define S3 bucket and key (file path) to store the uploaded file
    file_key = 'uploads/' + event['queryStringParameters']['filename']  # Define your S3 file path

    try:
        # Upload the file to S3 bucket
        s3.put_object(Body=file_content, Bucket=SRC_BUCKET, Key=file_key)

        #Get the current time
        arrival_time = time.time()

        #Write metadata to DynamoDB
        table.put_item(
            Item={
                'filename': event['queryStringParameters']['filename'],
                'arrival_time': str(arrival_time),
            }
        )

        # Return a success response
        return {
            'statusCode': 200,
            'body': json.dumps('File uploaded successfully to S3 and metadata stored in DynamoDB'),
            "headers": {
                "Access-Control-Allow-Origin": "*"
            }
        }
    except ClientError as e:
        # If upload fails, return an error response
        return {
            'statusCode': 500,
            'body': json.dumps('Failed to upload file to S3 or write to DynamoDB: {}'.format(str(e)))
        }