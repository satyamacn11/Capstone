variable "aws_region" {
  description = "The region where the infrastructure should be deployed to"
  type = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type = string
}

variable "user_bucket" {
  description = " S3 bucket where files will be uploded"
  type = string
}

variable "lambda_function_name" {
  description = "Lambda Function Name"
  type = string
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type = string
}

variable "dynamo_db_table" {
  description = "Dynamo_db table for storing meta-data"
  type = string
}

variable "sqs" {
  description = "simple queue service"
  type = string
}

variable "sns" {
  description = "simple notification service"
  type = string
}

variable "vpc_cidr_block" {
  description = "cidr block"
  type = string
}

variable "vpc_name" {
  description = "vpc name"
  type = string
}

variable "ami_id" {
  description = "ami ID"
  type = string
}

variable "instance_type" {
  description = "instance type"
  type = string
}

variable "sg_name" {
  description = "sg_name"
  type = string
}

variable "upload_bucket" {
  description = "Bucket to upload parquet file"
  type = string
}

variable "db_name" {
  description = "Name of AWS_Glue_db"
  type = string
}

variable "glue_crawler_name" {
  description = "Name of the Glue Crawler"
  type = string
}

variable "rest_api_name" {
  description = "Name of Rest API"
}