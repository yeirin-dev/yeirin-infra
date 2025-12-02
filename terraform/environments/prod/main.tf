# =============================================================================
# Yeirin Infrastructure - Production Environment
# =============================================================================
#
# 프로덕션 환경 설정:
# - t3.medium 인스턴스 (월 ~$30)
# - Multi-AZ 구성 (선택적)
# - CloudWatch 로그 30일 보존
# - 상세 모니터링 활성화
# - Elastic IP 사용 (고정 IP)
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
  #   key            = "prod/terraform.tfstate"
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
  environment = "prod"

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
  enable_rds        = var.enable_rds
  common_tags       = local.common_tags
}

# =============================================================================
# ECR Module (프로덕션과 개발이 같은 ECR 사용)
# =============================================================================

# ECR은 dev 환경에서 생성, prod는 동일 ECR 사용
# 별도 ECR 필요 시 아래 주석 해제
#
# module "ecr" {
#   source = "../../modules/ecr"
#
#   project_name = var.project_name
#   service_names = [
#     "api-gateway",
#     "yeirin-ai",
#     "soul-e"
#   ]
#   enable_image_scanning = true
#   common_tags           = local.common_tags
# }

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

  # 프로덕션 모니터링
  enable_detailed_monitoring = var.enable_detailed_monitoring
  enable_cloudwatch_alarms   = true
  alarm_sns_topic_arn        = var.alarm_sns_topic_arn

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

output "ec2_elastic_ip" {
  description = "Elastic IP (생성된 경우)"
  value       = module.ec2.elastic_ip
}

output "ec2_ssh_command" {
  description = "SSH 접속 명령어"
  value       = module.ec2.ssh_connection_string
}

output "security_group_ids" {
  description = "보안 그룹 ID"
  value       = module.security_groups.all_security_group_ids
}

output "api_endpoint" {
  description = "API 엔드포인트 (HTTPS 설정 후)"
  value       = var.backend_domain != "" ? "https://${var.backend_domain}" : "http://${module.ec2.public_ip}"
}
