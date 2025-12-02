# =============================================================================
# VPC Module - Variables
# =============================================================================

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
}

variable "environment" {
  description = "환경 (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "사용할 가용영역 목록"
  type        = list(string)
  default     = ["ap-northeast-2a"]

  # 비용 최적화: 단일 AZ로 시작
  # 고가용성 필요시: ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "enable_s3_endpoint" {
  description = "S3 VPC Endpoint 활성화 (무료, ECR 이미지 풀링 최적화)"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
