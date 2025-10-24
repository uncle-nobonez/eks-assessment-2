#!/bin/bash

# =====================================================
# Create Terraform Remote Backend Resources via AWS CLI
# =====================================================

# Variables
BUCKET_NAME="my-terraform-state-bucket-steven-eks"
DYNAMODB_TABLE="terraform-lock"
AWS_REGION="us-east-1"

echo "🚀 Creating S3 bucket: $BUCKET_NAME ..."
aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $AWS_REGION
  # --create-bucket-configuration LocationConstraint=$AWS_REGION 2>/dev/null || echo "⚠️  Bucket may already exist."

echo "✅ Enabling versioning on S3 bucket ..."
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

echo "✅ Enabling AES256 server-side encryption ..."
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" }
      }
    ]
  }'

echo "✅ Applying basic tags to S3 bucket ..."
aws s3api put-bucket-tagging \
  --bucket $BUCKET_NAME \
  --tagging '{
    "TagSet": [
      {"Key": "Name", "Value": "'"$BUCKET_NAME"'"},
      {"Key": "Environment", "Value": "shared"},
      {"Key": "Purpose", "Value": "terraform-state"}
    ]
  }'

echo "🚀 Creating DynamoDB table for Terraform locks: $DYNAMODB_TABLE ..."
aws dynamodb create-table \
  --table-name $DYNAMODB_TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --tags Key=Name,Value=$DYNAMODB_TABLE Key=Environment,Value=shared Key=Purpose,Value=terraform-locks 2>/dev/null || echo "⚠️  Table may already exist."

echo "✅ Waiting for DynamoDB table to become active..."
aws dynamodb wait table-exists --table-name $DYNAMODB_TABLE

echo "🎯 All resources created successfully!"
echo "======================================"
echo "S3 Bucket: $BUCKET_NAME"
echo "DynamoDB Table: $DYNAMODB_TABLE"
echo "Region: $AWS_REGION"
echo
echo "You can now use this backend in Terraform like so:"
echo
cat <<EOL
terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "dev/terraform.tfstate"
    region         = "$AWS_REGION"
    dynamodb_table = "$DYNAMODB_TABLE"
    encrypt        = true
  }
}
EOL
