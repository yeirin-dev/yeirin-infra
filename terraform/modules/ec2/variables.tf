# =============================================================================
# EC2 Module - Variables
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

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.small"

  # 비용 최적화 권장:
  # - dev: t3.small (2 vCPU, 2GB) - 월 ~$15
  # - prod: t3.medium (2 vCPU, 4GB) - 월 ~$30
  #
  # 서비스 3개 (yeirin, yeirin-ai, soul-e) + PostgreSQL + Redis + Nginx
  # t3.small은 최소 사양, 부하 테스트 후 스케일업 결정
}

variable "ami_id" {
  description = "AMI ID (빈 값이면 최신 Amazon Linux 2023 사용)"
  type        = string
  default     = ""
}

variable "key_name" {
  description = "SSH 키 페어 이름"
  type        = string
}

variable "subnet_id" {
  description = "EC2를 배치할 서브넷 ID"
  type        = string
}

variable "security_group_ids" {
  description = "적용할 보안 그룹 ID 목록"
  type        = list(string)
}

variable "associate_public_ip" {
  description = "퍼블릭 IP 할당 여부"
  type        = bool
  default     = true
}

variable "create_elastic_ip" {
  description = "Elastic IP 생성 여부"
  type        = bool
  default     = false

  # 비용: 사용 중일 때 무료, 미사용 시 시간당 $0.005
  # 고정 IP 필요 시 (DNS A 레코드 등) true로 설정
}

variable "root_volume_size" {
  description = "루트 EBS 볼륨 크기 (GB)"
  type        = number
  default     = 30

  # 권장: 30GB (Docker 이미지, 로그 등)
  # gp3 비용: GB당 월 $0.08 → 30GB = 월 $2.4
}

variable "enable_detailed_monitoring" {
  description = "상세 모니터링 활성화 (1분 단위)"
  type        = bool
  default     = false

  # 비용: 인스턴스당 월 $2.1 추가
  # 기본 모니터링(5분)은 무료
}

variable "enable_cloudwatch_alarms" {
  description = "CloudWatch 알람 생성 여부"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "알람 발생 시 알림 보낼 SNS Topic ARN"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}
