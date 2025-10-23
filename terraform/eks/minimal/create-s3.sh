#!/bin/bash

# ===== CONFIGURATION =====
REGION="us-east-1"
BUCKET_NAME="my-terraform-state-bucket-steven-eks" # Must be globally unique
DDB_TABLE_NAME="terraform-lock-table"

echo "🚀 Creating S3 bucket: $BUCKET_NAME in region: $REGION"

# ===== CREATE S3 BUCKET =====
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" || echo "⚠️ Bucket may already exist, skipping creation"

# ===== ENABLE VERSIONING =====
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

# ===== ENABLE DEFAULT ENCRYPTION =====
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

echo "✅ S3 bucket created and configured."

# ===== CREATE DYNAMODB TABLE =====
echo "🚀 Creating DynamoDB table: $DDB_TABLE_NAME"

aws dynamodb create-table \
  --table-name "$DDB_TABLE_NAME" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" || echo "⚠️ Table may already exist, skipping creation"

echo "✅ DynamoDB table ready."

# ===== OUTPUT CONFIG FOR TERRAFORM BACKEND =====
echo
echo "✅ Use this in your Terraform backend config:"
echo
cat <<EOF
terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "global/s3/terraform.tfstate"
    region         = "$REGION"
    dynamodb_table = "$DDB_TABLE_NAME"
    encrypt        = true
  }
}
EOF
