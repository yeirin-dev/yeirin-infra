# =============================================================================
# Security Groups Module - Variables
# =============================================================================

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "SSH 접근을 허용할 CIDR 블록 목록"
  type        = list(string)
  default     = []

  # 보안 권장: 특정 IP만 허용
  # 예: ["123.456.789.0/32"] - 사무실 IP
  # 절대 0.0.0.0/0 사용 금지
}

variable "enable_rds" {
  description = "RDS 보안 그룹 생성 여부"
  type        = bool
  default     = false

  # 비용 최적화: 초기에는 EC2 내 Docker PostgreSQL 사용
  # 스케일 필요시 RDS로 마이그레이션
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
