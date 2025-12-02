# =============================================================================
# Production Environment - Outputs
# =============================================================================

output "aws_region" {
  description = "AWS 리전"
  value       = var.aws_region
}

output "environment" {
  description = "환경"
  value       = "prod"
}

output "ecr_login_command" {
  description = "ECR 로그인 명령어"
  value       = "aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "deployment_checklist" {
  description = "배포 전 체크리스트"
  value       = <<-EOT
    ✅ 프로덕션 배포 체크리스트:
    1. terraform plan 결과 확인
    2. 백업 상태 확인
    3. 모니터링 대시보드 준비
    4. 롤백 계획 확인
    5. 알림 채널 활성화
  EOT
}
