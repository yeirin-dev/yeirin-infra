# =============================================================================
# Terraform Backend Configuration
# =============================================================================
#
# S3 + DynamoDB를 사용한 원격 상태 관리
#
# 초기 설정 순서:
# 1. 먼저 backend 블록을 주석 처리하고 로컬에서 S3 버킷과 DynamoDB 테이블 생성
# 2. 리소스 생성 후 backend 블록 활성화하고 terraform init -migrate-state 실행
#
# 비용 참고:
# - S3: 거의 무료 (상태 파일 크기 매우 작음)
# - DynamoDB: 온디맨드 모드로 거의 무료 (락킹용 최소 사용)
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # =============================================================================
  # Remote Backend (초기 설정 후 활성화)
  # =============================================================================
  #
  # 주의: 처음 설정 시 아래 backend 블록을 주석 처리하고,
  # scripts/init-backend.sh를 실행하여 S3 버킷과 DynamoDB 테이블을 먼저 생성하세요.
  #
  # backend "s3" {
  #   bucket         = "yeirin-terraform-state"
  #   key            = "terraform.tfstate"
  #   region         = "ap-northeast-2"
  #   encrypt        = true
  #   dynamodb_table = "yeirin-terraform-locks"
  # }
}

# =============================================================================
# Backend Infrastructure Resources
# =============================================================================
#
# 이 리소스들은 한 번만 생성하면 됩니다.
# 생성 후 위의 backend "s3" 블록을 활성화하세요.
# =============================================================================

# Terraform 상태 저장용 S3 버킷
resource "aws_s3_bucket" "terraform_state" {
  bucket = "yeirin-terraform-state-${data.aws_caller_identity.current.account_id}"

  # 실수로 삭제 방지
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "Yeirin Terraform State"
    Project     = "yeirin"
    ManagedBy   = "terraform"
    Description = "Terraform 상태 파일 저장소"
  }
}

# S3 버킷 버전 관리 (상태 파일 히스토리 보관)
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 버킷 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 퍼블릭 액세스 차단
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Terraform 락킹용 DynamoDB 테이블
# 비용: 온디맨드 모드로 거의 무료 (동시 작업 방지용 최소 사용)
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "yeirin-terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # 온디맨드 - 사용량 기반 과금 (비용 최소화)
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "Yeirin Terraform Locks"
    Project     = "yeirin"
    ManagedBy   = "terraform"
    Description = "Terraform 상태 락킹용 DynamoDB"
  }
}

# 현재 AWS 계정 정보
data "aws_caller_identity" "current" {}

# =============================================================================
# Outputs
# =============================================================================

output "terraform_state_bucket" {
  description = "Terraform 상태 저장 S3 버킷 이름"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_locks_table" {
  description = "Terraform 락킹 DynamoDB 테이블 이름"
  value       = aws_dynamodb_table.terraform_locks.name
}
