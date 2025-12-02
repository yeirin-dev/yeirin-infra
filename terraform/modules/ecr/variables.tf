# =============================================================================
# ECR Module - Variables
# =============================================================================

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
}

variable "service_names" {
  description = "ECR 레포지토리를 생성할 서비스 이름 목록"
  type        = list(string)
  default = [
    "api-gateway", # yeirin (NestJS)
    "yeirin-ai",   # yeirin-ai (FastAPI)
    "soul-e"       # soul-e (FastAPI)
  ]
}

variable "enable_image_scanning" {
  description = "이미지 푸시 시 취약점 스캔 활성화"
  type        = bool
  default     = true

  # 보안 권장: true
  # 비용: 무료 (Basic scanning)
}

variable "enable_ci_access" {
  description = "CI/CD Role에 ECR 접근 권한 부여"
  type        = bool
  default     = false
}

variable "ci_role_arns" {
  description = "ECR 접근을 허용할 IAM Role ARN 목록"
  type        = list(string)
  default     = []

  # GitHub Actions OIDC Role ARN 등
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
