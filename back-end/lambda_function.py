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

USERNAME = "arya11"
PASSWORD = "732741"


def authentication(event):
    auth_header = event.get('headers', {}).get('Authorization')

    if auth_header and auth_header.startswith('Basic '):
        # Extract the base64 encoded username:password pair
        encoded_credentials = auth_header.split(' ')[1]
        decoded_credentials = base64.b64decode(encoded_credentials).decode('utf-8')
        username, password = decoded_credentials.split(':')

        # Authentication logic
        if username == USERNAME and password == PASSWORD:
            return True
        else:
            return False
    else:
        return False

def lambda_handler(event, context):
    # Get the file content from the POST request
    if not authentication(event):
        return{
            'statusCode' : 401,
            'body' : json.dumps('Unauthorized'),
            "headers": {
                "Access-Control-Allow-Origin": "*"
            }
        }
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