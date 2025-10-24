#!/bin/bash

# Setup S3 backend and DynamoDB table for Terraform state

echo "Setting up Terraform backend resources..."

# Create S3 bucket for state
aws s3 mb s3://my-terraform-state-bucket-steven-eks --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket my-terraform-state-bucket-steven-eks \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket my-terraform-state-bucket-steven-eks \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

# Create DynamoDB table for locking
aws dynamodb create-table \
  --table-name terraform-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region us-east-1

echo "Backend resources created successfully!"
echo "S3 Bucket: my-terraform-state-bucket-steven-eks"
echo "DynamoDB Table: terraform-lock"