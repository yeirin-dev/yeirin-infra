# =============================================================================
# EC2 Module
# =============================================================================
#
# Yeirin 백엔드 서비스용 EC2 인스턴스
#
# 비용 최적화:
# - t3.small로 시작 (2 vCPU, 2GB RAM) - 월 ~$15
# - gp3 EBS 볼륨 사용 (gp2 대비 20% 저렴)
# - Spot Instance 옵션 지원 (개발환경용)
#
# 인스턴스 구성:
# - Docker + Docker Compose 사전 설치
# - ECR 접근 권한 (IAM Instance Profile)
# - CloudWatch Agent (모니터링)
# =============================================================================

# =============================================================================
# IAM Role & Instance Profile
# =============================================================================

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-ec2-role"
  })
}

# ECR 접근 권한
resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# CloudWatch Logs 권한
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# SSM 접근 권한 (Session Manager로 SSH 대체 가능)
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# S3 접근 권한 (배포 스크립트, 설정 파일 등)
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.project_name}-${var.environment}-s3-access"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

# =============================================================================
# EC2 Instance
# =============================================================================

resource "aws_instance" "backend" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # 퍼블릭 IP 할당 (Elastic IP 별도 사용 권장)
  associate_public_ip_address = var.associate_public_ip

  # gp3 EBS 볼륨 (gp2 대비 20% 저렴)
  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    iops                  = 3000 # gp3 기본값
    throughput            = 125  # gp3 기본값 (MB/s)
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.common_tags, {
      Name = "${var.project_name}-${var.environment}-root"
    })
  }

  # User Data: 초기 설정 스크립트
  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    project_name = var.project_name
    environment  = var.environment
    aws_region   = var.aws_region
  }))

  # 메타데이터 보안 설정
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 강제
    http_put_response_hop_limit = 1
  }

  # 모니터링 (기본 5분 → 1분 상세 모니터링은 추가 비용)
  monitoring = var.enable_detailed_monitoring

  tags = merge(var.common_tags, {
    Name        = "${var.project_name}-${var.environment}-backend"
    Environment = var.environment
    Role        = "backend"
  })

  lifecycle {
    # 인스턴스 타입 변경 시 재생성 방지
    ignore_changes = [ami]
  }
}

# =============================================================================
# Elastic IP (선택적)
# =============================================================================
#
# 비용: 사용 중일 때는 무료, 미사용 시 시간당 $0.005
# 고정 IP 필요 시 사용 (DNS 설정 등)
# =============================================================================

resource "aws_eip" "backend" {
  count = var.create_elastic_ip ? 1 : 0

  instance = aws_instance.backend.id
  domain   = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-backend-eip"
  })
}

# =============================================================================
# Data Sources
# =============================================================================

# Amazon Linux 2023 최신 AMI (무료)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# CloudWatch Alarms (비용 최적화된 기본 알람)
# =============================================================================

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300 # 5분
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU utilization is above 80% for 10 minutes"

  dimensions = {
    InstanceId = aws_instance.backend.id
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Instance status check failed"

  dimensions = {
    InstanceId = aws_instance.backend.id
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = var.common_tags
}
