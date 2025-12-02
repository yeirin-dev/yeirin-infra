# =============================================================================
# Yeirin Infrastructure - Development Environment
# =============================================================================
#
# 비용 최적화 개발 환경:
# - t3.small 인스턴스 (월 ~$15)
# - 단일 AZ 구성
# - CloudWatch 로그 7일 보존
# - 상세 모니터링 비활성화
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote Backend (초기 설정 후 활성화)
  # backend "s3" {
  #   bucket         = "yeirin-terraform-state-<ACCOUNT_ID>"
  #   key            = "dev/terraform.tfstate"
  #   region         = "ap-northeast-2"
  #   encrypt        = true
  #   dynamodb_table = "yeirin-terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# =============================================================================
# Local Variables
# =============================================================================

locals {
  environment = "dev"

  common_tags = {
    Project     = var.project_name
    Environment = local.environment
    ManagedBy   = "terraform"
    Repository  = "yeirin-infra"
  }
}

# =============================================================================
# VPC Module
# =============================================================================

module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  environment        = local.environment
  aws_region         = var.aws_region
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  enable_s3_endpoint = true
  common_tags        = local.common_tags
}

# =============================================================================
# Security Groups Module
# =============================================================================

module "security_groups" {
  source = "../../modules/security-groups"

  project_name      = var.project_name
  environment       = local.environment
  vpc_id            = module.vpc.vpc_id
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  enable_rds        = false # 개발환경은 Docker PostgreSQL 사용
  common_tags       = local.common_tags
}

# =============================================================================
# ECR Module
# =============================================================================

module "ecr" {
  source = "../../modules/ecr"

  project_name = var.project_name
  service_names = [
    "api-gateway", # yeirin (NestJS)
    "yeirin-ai",   # yeirin-ai (FastAPI)
    "soul-e"       # soul-e (FastAPI)
  ]
  enable_image_scanning = true
  common_tags           = local.common_tags
}

# =============================================================================
# EC2 Module
# =============================================================================

module "ec2" {
  source = "../../modules/ec2"

  project_name       = var.project_name
  environment        = local.environment
  aws_region         = var.aws_region
  instance_type      = var.instance_type
  key_name           = var.key_name
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.security_groups.nginx_security_group_id]
  associate_public_ip = true
  create_elastic_ip  = var.create_elastic_ip
  root_volume_size   = var.root_volume_size

  # 개발환경 비용 최적화
  enable_detailed_monitoring = false
  enable_cloudwatch_alarms   = true
  alarm_sns_topic_arn        = ""

  common_tags = local.common_tags
}

# =============================================================================
# Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "ec2_public_ip" {
  description = "EC2 퍼블릭 IP"
  value       = module.ec2.public_ip
}

output "ec2_ssh_command" {
  description = "SSH 접속 명령어"
  value       = module.ec2.ssh_connection_string
}

output "ecr_repository_urls" {
  description = "ECR 레포지토리 URL"
  value       = module.ecr.repository_urls
}

output "security_group_ids" {
  description = "보안 그룹 ID"
  value       = module.security_groups.all_security_group_ids
}
