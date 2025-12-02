#!/bin/bash
# =============================================================================
# EC2 User Data Script
# =============================================================================
#
# Amazon Linux 2023 기반 Docker + Docker Compose 설치
# ECR 인증 및 배포 환경 구성
# =============================================================================

set -e

# 로그 설정
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=========================================="
echo "Starting EC2 initialization..."
echo "Project: ${project_name}"
echo "Environment: ${environment}"
echo "Region: ${aws_region}"
echo "=========================================="

# =============================================================================
# System Update
# =============================================================================

echo "Updating system packages..."
dnf update -y

# =============================================================================
# Docker Installation
# =============================================================================

echo "Installing Docker..."
dnf install -y docker

# Docker 서비스 시작 및 자동 시작 설정
systemctl start docker
systemctl enable docker

# ec2-user를 docker 그룹에 추가
usermod -a -G docker ec2-user

# =============================================================================
# Docker Compose Installation
# =============================================================================

echo "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="v2.24.0"
curl -L "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# 버전 확인
docker --version
docker-compose --version

# =============================================================================
# AWS CLI Configuration
# =============================================================================

echo "Configuring AWS CLI..."
# AWS CLI는 Amazon Linux 2023에 기본 설치됨

# ECR 로그인 헬퍼 스크립트 생성
cat > /usr/local/bin/ecr-login.sh << 'ECRLOGIN'
#!/bin/bash
aws ecr get-login-password --region ${aws_region} | docker login --username AWS --password-stdin $(aws sts get-caller-identity --query Account --output text).dkr.ecr.${aws_region}.amazonaws.com
ECRLOGIN

chmod +x /usr/local/bin/ecr-login.sh

# =============================================================================
# Application Directory Setup
# =============================================================================

echo "Setting up application directories..."
mkdir -p /opt/${project_name}/{docker,scripts,logs,data}
chown -R ec2-user:ec2-user /opt/${project_name}

# 로그 디렉토리 심볼릭 링크
ln -sf /opt/${project_name}/logs /var/log/${project_name}

# =============================================================================
# Swap Space (t3.small 메모리 보조)
# =============================================================================

echo "Creating swap space..."
# 2GB 스왑 파일 생성 (메모리 부족 시 대비)
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# =============================================================================
# Security Hardening
# =============================================================================

echo "Applying security hardening..."

# SSH 보안 설정
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# =============================================================================
# CloudWatch Agent (선택적)
# =============================================================================

echo "Installing CloudWatch Agent..."
dnf install -y amazon-cloudwatch-agent

# CloudWatch Agent 설정
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWAGENT'
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
    },
    "metrics": {
        "namespace": "${project_name}/${environment}",
        "metrics_collected": {
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["disk_used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["/"]
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/${project_name}/*.log",
                        "log_group_name": "/${project_name}/${environment}/application",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": ${environment == "prod" ? 30 : 7}
                    },
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/${project_name}/${environment}/user-data",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 7
                    }
                ]
            }
        }
    }
}
CWAGENT

# CloudWatch Agent 시작
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# =============================================================================
# Cron Jobs
# =============================================================================

echo "Setting up cron jobs..."

# Docker 이미지 정리 (매일 3시)
echo "0 3 * * * docker system prune -af --filter 'until=24h'" | crontab -

# =============================================================================
# Environment File Template
# =============================================================================

cat > /opt/${project_name}/.env.example << 'ENVEXAMPLE'
# =============================================================================
# Yeirin Backend Environment Variables
# =============================================================================

# Environment
ENVIRONMENT=${environment}

# Database
DATABASE_HOST=postgres
DATABASE_PORT=5432
DATABASE_NAME=yeirin
DATABASE_USER=yeirin
DATABASE_PASSWORD=changeme

# Redis (if used)
REDIS_HOST=redis
REDIS_PORT=6379

# JWT
JWT_SECRET=changeme
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# API Keys
OPENAI_API_KEY=
INPSYT_API_KEY=

# AWS
AWS_REGION=${aws_region}
AWS_S3_BUCKET=

# Slack (Notifications)
SLACK_WEBHOOK_URL=

# Service URLs (internal)
YEIRIN_API_URL=http://api-gateway:3000
YEIRIN_AI_URL=http://yeirin-ai:8001
SOUL_E_URL=http://soul-e:8000
ENVEXAMPLE

chown ec2-user:ec2-user /opt/${project_name}/.env.example

# =============================================================================
# Completion
# =============================================================================

echo "=========================================="
echo "EC2 initialization completed!"
echo "=========================================="

# 초기화 완료 플래그
touch /opt/${project_name}/.initialized
