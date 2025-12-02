# =============================================================================
# Development Environment - Variables
# =============================================================================

variable "project_name" {
  description = "프로젝트 이름"
  type        = string
  default     = "yeirin"
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
  description = "사용할 가용영역"
  type        = list(string)
  default     = ["ap-northeast-2a"]

  # 비용 최적화: 개발환경은 단일 AZ
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.small"

  # t3.small: 2 vCPU, 2GB RAM - 월 ~$15
  # 개발환경 최소 사양
}

variable "key_name" {
  description = "SSH 키 페어 이름"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "SSH 접근 허용 CIDR 목록"
  type        = list(string)
  default     = []

  # 보안: 개발자 IP만 허용
  # 예: ["123.456.789.0/32"]
}

variable "create_elastic_ip" {
  description = "Elastic IP 생성 여부"
  type        = bool
  default     = false

  # 개발환경: false (동적 IP 사용)
  # 비용 절감
}

variable "root_volume_size" {
  description = "EBS 루트 볼륨 크기 (GB)"
  type        = number
  default     = 30
}
