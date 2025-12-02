# =============================================================================
# Production Environment - Variables
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
  default     = "10.1.0.0/16" # prod는 dev와 다른 CIDR 사용
}

variable "availability_zones" {
  description = "사용할 가용영역"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]

  # 프로덕션: Multi-AZ 권장 (고가용성)
  # 비용 우선 시: 단일 AZ로 시작
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.medium"

  # t3.medium: 2 vCPU, 4GB RAM - 월 ~$30
  # 프로덕션 권장 최소 사양
}

variable "key_name" {
  description = "SSH 키 페어 이름"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "SSH 접근 허용 CIDR 목록"
  type        = list(string)
  default     = []

  # 보안: 운영팀 IP만 허용
}

variable "create_elastic_ip" {
  description = "Elastic IP 생성 여부"
  type        = bool
  default     = true

  # 프로덕션: true (고정 IP for DNS)
}

variable "root_volume_size" {
  description = "EBS 루트 볼륨 크기 (GB)"
  type        = number
  default     = 50

  # 프로덕션은 더 큰 볼륨 권장
}

variable "enable_detailed_monitoring" {
  description = "상세 모니터링 활성화"
  type        = bool
  default     = true

  # 프로덕션: true 권장 (1분 단위 메트릭)
  # 추가 비용: 월 $2.1
}

variable "enable_rds" {
  description = "RDS 사용 여부"
  type        = bool
  default     = false

  # 초기: false (Docker PostgreSQL)
  # 스케일 필요 시: true로 변경
}

variable "alarm_sns_topic_arn" {
  description = "CloudWatch 알람용 SNS Topic ARN"
  type        = string
  default     = ""
}

variable "backend_domain" {
  description = "백엔드 도메인 (예: api.yeirin.com)"
  type        = string
  default     = ""
}
