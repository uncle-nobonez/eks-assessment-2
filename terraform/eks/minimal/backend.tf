terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket-steven-eks"
    key            = "k8s/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock"
    encrypt        = true
  }
}


