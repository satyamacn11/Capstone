#define variables
locals {
  lambda_src_dir    = "${path.module}/../back-end/"
  lambda_function_zip_path = "${path.module}/lambda/lambda_function.zip"
}


#S3 bucket creation with server-side encryption
resource "aws_s3_bucket" "bucket" {
  bucket = var.user_bucket
  force_destroy = true
  acl = "private"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "alias/aws/s3"
        sse_algorithm = "aws:kms"
      }
    }
  }
}

resource "aws_s3_bucket" "u_bucket" {
  bucket = var.upload_bucket
  force_destroy = true
  acl = "private"
  versioning {
    enabled = true
  }
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = "alias/aws/s3"
        sse_algorithm = "aws:kms"
      }
    }
  }
}

# DynamoDB table creation with server-side encryption
resource "aws_dynamodb_table" "table" {
  name           = var.dynamo_db_table
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "filename"

  attribute {
    name = "filename"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }
}

#Creating an IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "my_lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Creating S3 policy for Lambda function role to get and put objects to S3 bucket
data "aws_iam_policy_document" "policy" {
  statement {
    effect    = "Allow"
    actions   = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:CopyObject",
      "s3:HeadObject",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "dynamodb:PutItem",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "policy" {
  name        = "lambda-policy"
  policy      = data.aws_iam_policy_document.policy.json
}

#Attaching the policy created above to the IAM role
resource "aws_iam_policy_attachment" "lambda_basic_execution" {
  name       = "lambda-basic-execution"
  policy_arn = aws_iam_policy.policy.arn
  roles       = [aws_iam_role.lambda_role.name]
}

#Creating the lambda function
data "archive_file" "lambda" {
  source_dir  = local.lambda_src_dir
  output_path = local.lambda_function_zip_path
  type        = "zip"
}

resource "aws_lambda_function" "file_uploader_lambda" {
  filename      = local.lambda_function_zip_path
  function_name = var.lambda_function_name
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = var.lambda_runtime
  timeout       = 20
  memory_size   = 128
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      USER_BUCKET = var.user_bucket,
      DYNAMO_DB_TABLE = var.dynamo_db_table,
    }
  }

}

#Create an API Gateway for the REST API
resource "aws_api_gateway_rest_api" "demo-api" {
  name        = var.rest_api_name
  binary_media_types = ["*/*"]
}

resource "aws_api_gateway_resource" "upload_resource" {
  parent_id   = aws_api_gateway_rest_api.demo-api.root_resource_id
  path_part   = "upload"
  rest_api_id = aws_api_gateway_rest_api.demo-api.id
}

#Create the POST method for the "upload" resource
resource "aws_api_gateway_method" "upload_method" {
  authorization = "NONE"
  http_method   = "POST"
  resource_id   = aws_api_gateway_resource.upload_resource.id
  rest_api_id   = aws_api_gateway_rest_api.demo-api.id
}

#Configure the integration for the Lambda function
resource "aws_api_gateway_integration" "upload_integration" {
  http_method             = aws_api_gateway_method.upload_method.http_method
  resource_id             = aws_api_gateway_resource.upload_resource.id
  rest_api_id             = aws_api_gateway_rest_api.demo-api.id
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.file_uploader_lambda.invoke_arn
}

# Method Response and Enabling CORS

resource "aws_api_gateway_method_response" "upload_method_response" {
  rest_api_id = aws_api_gateway_rest_api.demo-api.id
  resource_id = aws_api_gateway_resource.upload_resource.id
  http_method = aws_api_gateway_method.upload_method.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true,
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

#Deploy the API and create a stage called "v1"
resource "aws_api_gateway_deployment" "my_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.demo-api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.upload_resource.id,
      aws_api_gateway_method.upload_method.id,
      aws_api_gateway_integration.upload_integration.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "v1" {
  deployment_id = aws_api_gateway_deployment.my_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.demo-api.id
  stage_name    = "v1"
}

# Permission for API Gateway to invoke lambda function
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.file_uploader_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn = "arn:aws:execute-api:${var.aws_region}:${var.aws_account_id}:${aws_api_gateway_rest_api.demo-api.id}/*/${aws_api_gateway_method.upload_method.http_method}${aws_api_gateway_resource.upload_resource.path}"
}


resource "aws_sqs_queue" "queue" {
  name = var.sqs

  policy = <<POLICY
  {
  "Version": "2008-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": [
          "sqs:SendMessage",
          "kms:Encrypt",
          "kms:Decrypt"
      ],
      "Resource": "arn:aws:sqs:${var.aws_region}:${var.aws_account_id}:${var.sqs}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "arn:aws:sns:${var.aws_region}:${var.aws_account_id}:${var.sns}"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_sns_topic" "sns" {
  name = var.sns

  policy = <<POLICY
  {
    "Version": "2012-10-17",
    "Id": "example-ID",
    "Statement": [
        {
            "Sid": "Example SNS topic policy",
            "Effect": "Allow",
            "Principal": {
                "Service": "s3.amazonaws.com"
            },
            "Action": [
                "SNS:Publish"
            ],
            "Resource": "arn:aws:sns:${var.aws_region}:${var.aws_account_id}:${var.sns}",
            "Condition": {
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:s3:::${var.user_bucket}"
                },
                "StringEquals": {
                    "aws:SourceAccount": "${var.aws_account_id}"
                }
            }
        }
    ]
}
POLICY
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.bucket.id

  topic {
    topic_arn     = aws_sns_topic.sns.arn
    events        = ["s3:ObjectCreated:*"]
  }
}

resource "aws_sns_topic_subscription" "sns_to_sqs" {
  topic_arn = aws_sns_topic.sns.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.queue.arn
}


#-------
#VPC

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr_block

  tags = {
    Name = var.vpc_name
  }
}



# Create an Internet Gateway and attach it to the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

# Create a routing table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_subnet" "subnet" {
  vpc_id     = aws_vpc.main.id
  cidr_block = var.vpc_cidr_block
  map_public_ip_on_launch = true

  tags = {
    Name = "my_subnet"
  }
}

# Associate the routing table with the subnet
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet.id
  route_table_id = aws_route_table.public.id
}

resource "aws_iam_policy" "ec2_policy" {
  # Permissions for S3 and SQS
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid    = "VisualEditor0",
      Effect = "Allow",
      Action = ["s3:*", "sqs:*", "ec2:*"],
      Resource = "*"
    },
    {
      Action = [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      Effect   = "Allow",
      Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "my_ec2_role" {
  name = "my-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_policy_attachment" "attach_policy" {
  name       = "attach-policy"
  policy_arn = aws_iam_policy.ec2_policy.arn
  roles      = [aws_iam_role.my_ec2_role.name]
}


resource "aws_iam_instance_profile" "ec2_profile" {
  name = "ec2_profile-1"
  role = aws_iam_role.my_ec2_role.name
}

# Create a security group for the EC2 instance
resource "aws_security_group" "ec2_sg" {
  name        = var.sg_name
  description = "Allow inbound traffic"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# Create an IAM role for Glue Crawler
resource "aws_iam_role" "glue_crawler_role" {
  name = "glue_crawler_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  })
  inline_policy {
    name = "GlueCrawlerS3AccessPolicy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [{
        Effect   = "Allow",
        Action   = "s3:GetObject",
        Resource = "arn:aws:s3:::mss-dev-us-east-1-demo-arya-upload-bucket/uploads/*"
      },
      {
       Effect   = "Allow",
       Action   = "glue:StartCrawler",
       Resource = "*"

      }]
    })
  }
}

# Attach policies to the IAM role
resource "aws_iam_policy_attachment" "glue_crawler_policy_attachment" {
  name       = "attach-glue-policy"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  roles      = [aws_iam_role.glue_crawler_role.name]
}

resource "aws_iam_policy_attachment" "s3_full_access_policy_attachment" {
  name = "Attach_s3_policy"
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  roles      = [aws_iam_role.glue_crawler_role.name]
}

#Create an EC2 instance
resource "aws_instance" "ec2_instance" {
  ami                         = var.ami_id        //"ami-063274182d85cbf14"
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.subnet.id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  user_data = file("script.sh")

  tags = {
    Name = "mss_dev_us-east-1_demo_arya-ec2"
  }
}


# Create an AWS Glue database
resource "aws_glue_catalog_database" "aws_glue_db" {
  name = var.db_name
}

resource "aws_glue_crawler" "crawler" {
  name = var.glue_crawler_name
  database_name = var.db_name
  role          = aws_iam_role.glue_crawler_role.arn

  s3_target{
      path = "s3://mss-dev-us-east-1-demo-arya-upload-bucket/uploads/"
  }
  depends_on = [aws_glue_catalog_database.aws_glue_db]
}

resource "null_resource" "start_crawler" {
  depends_on = [aws_glue_crawler.crawler, aws_instance.ec2_instance]
  provisioner "local-exec" {
    command = "aws glue start-crawler --name ${aws_glue_crawler.crawler.name}"
  }
}

# Define the Glue Table using the Crawler
resource "aws_glue_catalog_table" "my_table" {
  name          = "uploads"
  database_name = aws_glue_catalog_database.aws_glue_db.name
  table_type = "EXTERNAL_TABLE"
  parameters = {
    classification = "parquet"
  }

  storage_descriptor {
    location      = "s3://mss-dev-us-east-1-demo-arya-upload-bucket/uploads/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
  }
}