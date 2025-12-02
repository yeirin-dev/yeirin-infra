# =============================================================================
# Development Environment - Outputs
# =============================================================================

# VPC 정보는 main.tf에서 직접 output

# 추가 유틸리티 outputs
output "aws_region" {
  description = "AWS 리전"
  value       = var.aws_region
}

output "environment" {
  description = "환경"
  value       = "dev"
}

output "ecr_login_command" {
  description = "ECR 로그인 명령어"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.${var.aws_region}.amazonaws.com"
}
