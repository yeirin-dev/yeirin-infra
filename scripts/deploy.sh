#!/bin/bash
# =============================================================================
# Yeirin Backend - Deployment Script
# =============================================================================
#
# 무중단 배포 스크립트
# - ECR에서 새 이미지 풀
# - Rolling Update 방식으로 서비스 재시작
# - 헬스체크 후 자동 롤백
#
# 사용법:
# ./deploy.sh [environment] [service]
# ./deploy.sh prod              # 전체 서비스 배포
# ./deploy.sh prod api-gateway  # 특정 서비스만 배포
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="/opt/yeirin"
DOCKER_DIR="${PROJECT_DIR}/docker"
LOG_DIR="${PROJECT_DIR}/logs"
BACKUP_DIR="${PROJECT_DIR}/backups"

# 환경 설정
ENVIRONMENT="${1:-prod}"
SERVICE="${2:-all}"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

send_slack_notification() {
    local status="$1"
    local message="$2"

    if [ -n "${SLACK_WEBHOOK_URL}" ]; then
        local color="good"
        local emoji=":rocket:"

        if [ "$status" = "error" ]; then
            color="danger"
            emoji=":x:"
        elif [ "$status" = "warning" ]; then
            color="warning"
            emoji=":warning:"
        fi

        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H 'Content-Type: application/json' \
            -d "{
                \"attachments\": [{
                    \"color\": \"${color}\",
                    \"title\": \"${emoji} Yeirin Deployment [${ENVIRONMENT}]\",
                    \"text\": \"${message}\",
                    \"footer\": \"$(hostname) | $(date '+%Y-%m-%d %H:%M:%S')\"
                }]
            }" > /dev/null 2>&1 || true
    fi
}

# =============================================================================
# Pre-deployment Checks
# =============================================================================

pre_deploy_checks() {
    log_info "Running pre-deployment checks..."

    # Docker 확인
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi

    # Docker Compose 확인
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi

    # 환경 파일 확인
    if [ ! -f "${DOCKER_DIR}/.env" ]; then
        log_error ".env file not found at ${DOCKER_DIR}/.env"
        exit 1
    fi

    # 디스크 공간 확인 (최소 2GB)
    local available_space=$(df -BG "${PROJECT_DIR}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "${available_space}" -lt 2 ]; then
        log_warn "Low disk space: ${available_space}GB available"
    fi

    log_success "Pre-deployment checks passed"
}

# =============================================================================
# ECR Login
# =============================================================================

ecr_login() {
    log_info "Logging in to ECR..."

    local region=$(grep AWS_REGION "${DOCKER_DIR}/.env" | cut -d'=' -f2 || echo "ap-northeast-2")

    aws ecr get-login-password --region "${region}" | \
        docker login --username AWS --password-stdin \
        "$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${region}.amazonaws.com"

    log_success "ECR login successful"
}

# =============================================================================
# Backup Current State
# =============================================================================

backup_current_state() {
    log_info "Backing up current state..."

    local backup_name="backup_$(date '+%Y%m%d_%H%M%S')"
    local backup_path="${BACKUP_DIR}/${backup_name}"
    mkdir -p "${backup_path}"

    # 현재 이미지 태그 저장
    cd "${DOCKER_DIR}"
    docker-compose -f docker-compose.yml -f docker-compose.${ENVIRONMENT}.yml config > "${backup_path}/docker-compose.resolved.yml" 2>/dev/null || true

    # 현재 컨테이너 상태 저장
    docker ps --format "{{.Names}}: {{.Image}}" > "${backup_path}/containers.txt"

    # 환경 파일 백업
    cp "${DOCKER_DIR}/.env" "${backup_path}/.env.backup" 2>/dev/null || true

    # 최근 백업 링크 업데이트
    ln -sfn "${backup_path}" "${BACKUP_DIR}/latest"

    log_success "Backup created at ${backup_path}"
}

# =============================================================================
# Pull New Images
# =============================================================================

pull_images() {
    log_info "Pulling new images..."

    cd "${DOCKER_DIR}"

    if [ "$SERVICE" = "all" ]; then
        docker-compose -f docker-compose.yml -f docker-compose.${ENVIRONMENT}.yml pull
    else
        docker-compose -f docker-compose.yml -f docker-compose.${ENVIRONMENT}.yml pull "${SERVICE}"
    fi

    log_success "Images pulled successfully"
}

# =============================================================================
# Deploy Services
# =============================================================================

deploy_services() {
    log_info "Deploying services..."

    cd "${DOCKER_DIR}"

    local services=()
    if [ "$SERVICE" = "all" ]; then
        services=("api-gateway" "yeirin-ai" "soul-e")
    else
        services=("${SERVICE}")
    fi

    # Rolling Update: 한 서비스씩 재시작
    for svc in "${services[@]}"; do
        log_info "Deploying ${svc}..."

        # 새 컨테이너 시작 (기존 것 유지)
        docker-compose -f docker-compose.yml -f docker-compose.${ENVIRONMENT}.yml up -d --no-deps "${svc}"

        # 헬스체크 대기
        if ! wait_for_health "${svc}"; then
            log_error "Health check failed for ${svc}"
            return 1
        fi

        log_success "${svc} deployed successfully"
        sleep 5  # 서비스 간 간격
    done

    # Nginx 재시작 (설정 변경 반영)
    log_info "Reloading Nginx..."
    docker-compose -f docker-compose.yml -f docker-compose.${ENVIRONMENT}.yml exec -T nginx nginx -s reload || \
        docker-compose -f docker-compose.yml -f docker-compose.${ENVIRONMENT}.yml restart nginx

    log_success "All services deployed successfully"
}

# =============================================================================
# Health Check
# =============================================================================

wait_for_health() {
    local service="$1"
    local max_attempts=30
    local attempt=0

    log_info "Waiting for ${service} to be healthy..."

    while [ $attempt -lt $max_attempts ]; do
        if docker inspect --format='{{.State.Health.Status}}' "yeirin-${service}" 2>/dev/null | grep -q "healthy"; then
            return 0
        fi

        # 컨테이너가 헬스체크 없으면 러닝 상태 확인
        if docker inspect --format='{{.State.Status}}' "yeirin-${service}" 2>/dev/null | grep -q "running"; then
            sleep 2
            attempt=$((attempt + 1))
            continue
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    return 1
}

# =============================================================================
# Post-deployment
# =============================================================================

post_deploy() {
    log_info "Running post-deployment tasks..."

    # 오래된 이미지 정리
    docker image prune -af --filter "until=24h" || true

    # 오래된 백업 정리 (7일 이상)
    find "${BACKUP_DIR}" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

    log_success "Post-deployment tasks completed"
}

# =============================================================================
# Main
# =============================================================================

main() {
    log_info "=========================================="
    log_info "Yeirin Deployment Started"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "Service: ${SERVICE}"
    log_info "=========================================="

    send_slack_notification "info" "Deployment started for ${SERVICE} in ${ENVIRONMENT}"

    # 디렉토리 생성
    mkdir -p "${LOG_DIR}" "${BACKUP_DIR}"

    # 배포 단계
    pre_deploy_checks
    ecr_login
    backup_current_state
    pull_images

    if deploy_services; then
        post_deploy
        send_slack_notification "success" "Deployment completed successfully for ${SERVICE}"
        log_success "=========================================="
        log_success "Deployment completed successfully!"
        log_success "=========================================="
    else
        log_error "Deployment failed, initiating rollback..."
        send_slack_notification "error" "Deployment failed for ${SERVICE}, rolling back..."

        "${SCRIPT_DIR}/rollback.sh" "${ENVIRONMENT}"
        exit 1
    fi
}

# 스크립트 실행
main "$@" 2>&1 | tee -a "${LOG_DIR}/deploy_$(date '+%Y%m%d').log"
