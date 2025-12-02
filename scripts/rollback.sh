#!/bin/bash
# =============================================================================
# Yeirin Backend - Rollback Script
# =============================================================================
#
# 이전 버전으로 롤백
#
# 사용법:
# ./rollback.sh [environment]
# ./rollback.sh prod
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

PROJECT_DIR="/opt/yeirin"
DOCKER_DIR="${PROJECT_DIR}/docker"
BACKUP_DIR="${PROJECT_DIR}/backups"
LOG_DIR="${PROJECT_DIR}/logs"

ENVIRONMENT="${1:-prod}"

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
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

send_slack_notification() {
    local status="$1"
    local message="$2"

    if [ -n "${SLACK_WEBHOOK_URL}" ]; then
        local color="warning"
        local emoji=":rewind:"

        if [ "$status" = "success" ]; then
            color="good"
        elif [ "$status" = "error" ]; then
            color="danger"
            emoji=":x:"
        fi

        curl -s -X POST "${SLACK_WEBHOOK_URL}" \
            -H 'Content-Type: application/json' \
            -d "{
                \"attachments\": [{
                    \"color\": \"${color}\",
                    \"title\": \"${emoji} Yeirin Rollback [${ENVIRONMENT}]\",
                    \"text\": \"${message}\",
                    \"footer\": \"$(hostname) | $(date '+%Y-%m-%d %H:%M:%S')\"
                }]
            }" > /dev/null 2>&1 || true
    fi
}

# =============================================================================
# Rollback
# =============================================================================

rollback() {
    log_info "=========================================="
    log_info "Yeirin Rollback Started"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "=========================================="

    send_slack_notification "warning" "Rollback initiated for ${ENVIRONMENT}"

    # 최신 백업 확인
    local latest_backup="${BACKUP_DIR}/latest"
    if [ ! -L "${latest_backup}" ] || [ ! -d "$(readlink -f ${latest_backup})" ]; then
        log_error "No backup found to rollback to"
        send_slack_notification "error" "Rollback failed: No backup found"
        exit 1
    fi

    local backup_path=$(readlink -f "${latest_backup}")
    log_info "Rolling back to: ${backup_path}"

    # 이전 이미지 정보 읽기
    if [ -f "${backup_path}/containers.txt" ]; then
        log_info "Previous container states:"
        cat "${backup_path}/containers.txt"
    fi

    cd "${DOCKER_DIR}"

    # 현재 컨테이너 중지
    log_info "Stopping current containers..."
    docker-compose -f docker-compose.yml -f docker-compose.${ENVIRONMENT}.yml down --remove-orphans

    # 백업된 환경 파일 복원
    if [ -f "${backup_path}/.env.backup" ]; then
        log_info "Restoring environment file..."
        cp "${backup_path}/.env.backup" "${DOCKER_DIR}/.env"
    fi

    # 서비스 재시작 (이전 이미지 태그로)
    log_info "Starting services with previous images..."
    docker-compose -f docker-compose.yml -f docker-compose.${ENVIRONMENT}.yml up -d

    # 헬스체크
    log_info "Waiting for services to be healthy..."
    sleep 30

    local all_healthy=true
    for container in yeirin-api-gateway yeirin-ai yeirin-soul-e; do
        if ! docker ps --filter "name=${container}" --filter "status=running" --format "{{.Names}}" | grep -q "${container}"; then
            log_error "Container ${container} is not running"
            all_healthy=false
        fi
    done

    if [ "$all_healthy" = true ]; then
        log_success "=========================================="
        log_success "Rollback completed successfully!"
        log_success "=========================================="
        send_slack_notification "success" "Rollback completed successfully"

        # 롤백 기록
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Rolled back to ${backup_path}" >> "${LOG_DIR}/rollback_history.log"
    else
        log_error "Rollback may have issues, please check manually"
        send_slack_notification "error" "Rollback completed with issues"
        exit 1
    fi
}

# =============================================================================
# List Backups
# =============================================================================

list_backups() {
    log_info "Available backups:"
    ls -lt "${BACKUP_DIR}" | grep -E "^d" | head -10
}

# =============================================================================
# Main
# =============================================================================

if [ "$1" = "--list" ]; then
    list_backups
else
    rollback 2>&1 | tee -a "${LOG_DIR}/rollback_$(date '+%Y%m%d').log"
fi
