terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket-steven-eks"
    key            = "global/s3/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-lock-table"
    encrypt        = true
  }
}

#git commit -m "first commit"
#git branch -M main
#git remote add origin git@github.com:Steve4423/my-eks-assessment2.git
#git push -u origin main