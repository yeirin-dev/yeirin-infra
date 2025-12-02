#!/bin/bash
# =============================================================================
# Yeirin Backend - EC2 Initial Setup Script
# =============================================================================
#
# EC2 인스턴스 초기 설정
# Terraform으로 프로비저닝 후 실행
#
# 사용법:
# scp setup-ec2.sh ec2-user@<EC2_IP>:/tmp/
# ssh ec2-user@<EC2_IP> 'sudo bash /tmp/setup-ec2.sh'
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

PROJECT_NAME="yeirin"
PROJECT_DIR="/opt/${PROJECT_NAME}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Check Root
# =============================================================================

if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (sudo)"
    exit 1
fi

log_info "=========================================="
log_info "Yeirin EC2 Setup Started"
log_info "=========================================="

# =============================================================================
# System Update
# =============================================================================

log_info "Updating system packages..."
dnf update -y

# =============================================================================
# Install Docker
# =============================================================================

log_info "Installing Docker..."
dnf install -y docker

systemctl start docker
systemctl enable docker

usermod -a -G docker ec2-user

log_success "Docker installed"

# =============================================================================
# Install Docker Compose
# =============================================================================

log_info "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="v2.24.0"
curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

log_success "Docker Compose installed: $(docker-compose --version)"

# =============================================================================
# Install AWS CLI (if not present)
# =============================================================================

if ! command -v aws &> /dev/null; then
    log_info "Installing AWS CLI..."
    dnf install -y aws-cli
fi

# =============================================================================
# Install Additional Tools
# =============================================================================

log_info "Installing additional tools..."
dnf install -y \
    git \
    htop \
    jq \
    nc \
    curl \
    wget

# =============================================================================
# Create Project Directory Structure
# =============================================================================

log_info "Creating project directories..."
mkdir -p "${PROJECT_DIR}"/{docker,scripts,logs,backups,data}
mkdir -p "${PROJECT_DIR}/docker/nginx"/{conf.d,ssl}

chown -R ec2-user:ec2-user "${PROJECT_DIR}"

# 로그 심볼릭 링크
ln -sf "${PROJECT_DIR}/logs" "/var/log/${PROJECT_NAME}"

log_success "Project directories created at ${PROJECT_DIR}"

# =============================================================================
# Setup Swap (for t3.small with 2GB RAM)
# =============================================================================

log_info "Setting up swap space..."
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    log_success "Swap space created (2GB)"
else
    log_info "Swap already exists"
fi

# =============================================================================
# Configure SSH Security
# =============================================================================

log_info "Configuring SSH security..."
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

log_success "SSH security configured"

# =============================================================================
# Install CloudWatch Agent
# =============================================================================

log_info "Installing CloudWatch Agent..."
dnf install -y amazon-cloudwatch-agent

# CloudWatch Agent 설정은 Terraform User Data에서 수행

log_success "CloudWatch Agent installed"

# =============================================================================
# Create Helper Scripts
# =============================================================================

log_info "Creating helper scripts..."

# ECR 로그인 스크립트
cat > "${PROJECT_DIR}/scripts/ecr-login.sh" << 'EOF'
#!/bin/bash
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
aws ecr get-login-password --region ${AWS_REGION} | \
    docker login --username AWS --password-stdin \
    $(aws sts get-caller-identity --query Account --output text).dkr.ecr.${AWS_REGION}.amazonaws.com
EOF
chmod +x "${PROJECT_DIR}/scripts/ecr-login.sh"

# Docker 정리 스크립트
cat > "${PROJECT_DIR}/scripts/cleanup.sh" << 'EOF'
#!/bin/bash
echo "Cleaning up Docker resources..."
docker system prune -af --filter "until=24h"
docker volume prune -f
echo "Cleanup completed"
EOF
chmod +x "${PROJECT_DIR}/scripts/cleanup.sh"

chown -R ec2-user:ec2-user "${PROJECT_DIR}/scripts"

log_success "Helper scripts created"

# =============================================================================
# Setup Cron Jobs
# =============================================================================

log_info "Setting up cron jobs..."

# Docker 정리 (매일 3시)
(crontab -l 2>/dev/null || true; echo "0 3 * * * ${PROJECT_DIR}/scripts/cleanup.sh >> ${PROJECT_DIR}/logs/cleanup.log 2>&1") | crontab -

# ECR 로그인 갱신 (12시간마다)
(crontab -l 2>/dev/null || true; echo "0 */12 * * * ${PROJECT_DIR}/scripts/ecr-login.sh >> ${PROJECT_DIR}/logs/ecr-login.log 2>&1") | crontab -

log_success "Cron jobs configured"

# =============================================================================
# Create Environment Template
# =============================================================================

log_info "Creating environment template..."

cat > "${PROJECT_DIR}/docker/.env.template" << 'EOF'
# =============================================================================
# Yeirin Backend - Environment Variables
# =============================================================================
# Copy this file to .env and fill in the values
# cp .env.template .env

# Environment
ENVIRONMENT=production

# ECR Registry
ECR_REGISTRY=<ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com
IMAGE_TAG=latest

# Database
DATABASE_NAME=yeirin
DATABASE_USER=yeirin
DATABASE_PASSWORD=<GENERATE_SECURE_PASSWORD>

# JWT
JWT_SECRET=<GENERATE_SECURE_SECRET_MIN_32_CHARS>
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# External APIs
OPENAI_API_KEY=<YOUR_OPENAI_KEY>
INPSYT_API_KEY=<YOUR_INPSYT_KEY>

# AWS
AWS_REGION=ap-northeast-2
AWS_S3_BUCKET=yeirin-uploads

# Notifications
SLACK_WEBHOOK_URL=<YOUR_SLACK_WEBHOOK>

# Domain (for SSL)
BACKEND_DOMAIN=api.yeirin.com
LETSENCRYPT_EMAIL=admin@yeirin.com

# CORS
FRONTEND_URLS=https://yeirin.vercel.app
EOF

chown ec2-user:ec2-user "${PROJECT_DIR}/docker/.env.template"

log_success "Environment template created"

# =============================================================================
# Final Message
# =============================================================================

log_success "=========================================="
log_success "Yeirin EC2 Setup Completed!"
log_success "=========================================="
echo ""
echo "Next steps:"
echo "1. Copy docker files to ${PROJECT_DIR}/docker/"
echo "2. Copy .env.template to .env and configure"
echo "3. Run: ${PROJECT_DIR}/scripts/ecr-login.sh"
echo "4. Run: cd ${PROJECT_DIR}/docker && docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d"
echo ""
echo "Project directory: ${PROJECT_DIR}"
echo "Logs directory: ${PROJECT_DIR}/logs"
echo ""

# 초기화 완료 플래그
touch "${PROJECT_DIR}/.setup-completed"
