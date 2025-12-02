#!/bin/bash
# =============================================================================
# Yeirin Backend - Health Check Script
# =============================================================================
#
# 모든 서비스의 헬스 상태 확인
#
# 사용법:
# ./health-check.sh
# ./health-check.sh --verbose
# ./health-check.sh --json
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

# 서비스 엔드포인트
declare -A SERVICES=(
    ["nginx"]="http://localhost/health"
    ["api-gateway"]="http://localhost:3000/api/v1/health"
    ["yeirin-ai"]="http://localhost:8001/health"
    ["soul-e"]="http://localhost:8000/health"
)

# 옵션
VERBOSE=false
JSON_OUTPUT=false

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# =============================================================================
# Parse Arguments
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --json|-j)
            JSON_OUTPUT=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# =============================================================================
# Health Check Functions
# =============================================================================

check_docker_container() {
    local container_name="yeirin-$1"
    local status=$(docker inspect --format='{{.State.Status}}' "${container_name}" 2>/dev/null || echo "not_found")
    local health=$(docker inspect --format='{{.State.Health.Status}}' "${container_name}" 2>/dev/null || echo "none")

    echo "${status}:${health}"
}

check_http_endpoint() {
    local url="$1"
    local timeout=5

    local start_time=$(date +%s%N)
    local response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout ${timeout} "${url}" 2>/dev/null || echo "000")
    local end_time=$(date +%s%N)

    local response_time=$(( (end_time - start_time) / 1000000 ))  # ms

    echo "${response}:${response_time}"
}

# =============================================================================
# Main Check
# =============================================================================

perform_health_check() {
    local all_healthy=true
    local results=()

    echo ""
    if [ "$JSON_OUTPUT" = false ]; then
        echo "============================================"
        echo "  Yeirin Backend Health Check"
        echo "  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "============================================"
        echo ""
    fi

    for service in "${!SERVICES[@]}"; do
        local url="${SERVICES[$service]}"
        local container_status=$(check_docker_container "$service")
        local docker_status=$(echo "$container_status" | cut -d: -f1)
        local docker_health=$(echo "$container_status" | cut -d: -f2)

        local http_result=$(check_http_endpoint "$url")
        local http_code=$(echo "$http_result" | cut -d: -f1)
        local response_time=$(echo "$http_result" | cut -d: -f2)

        local status="healthy"
        local status_icon="✅"

        if [ "$docker_status" != "running" ]; then
            status="down"
            status_icon="❌"
            all_healthy=false
        elif [ "$http_code" != "200" ] && [ "$http_code" != "204" ]; then
            status="unhealthy"
            status_icon="⚠️"
            all_healthy=false
        fi

        if [ "$JSON_OUTPUT" = true ]; then
            results+=("{\"service\":\"${service}\",\"status\":\"${status}\",\"docker\":\"${docker_status}\",\"http_code\":${http_code},\"response_time_ms\":${response_time}}")
        else
            printf "${status_icon} %-15s | Docker: %-10s | HTTP: %s | Response: %sms\n" \
                "${service}" "${docker_status}" "${http_code}" "${response_time}"

            if [ "$VERBOSE" = true ]; then
                echo "   └─ URL: ${url}"
                echo "   └─ Container Health: ${docker_health}"
                echo ""
            fi
        fi
    done

    # 추가 시스템 정보 (상세 모드)
    if [ "$VERBOSE" = true ] && [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "============================================"
        echo "  System Information"
        echo "============================================"
        echo ""

        # 디스크 사용량
        echo "📦 Disk Usage:"
        df -h / | tail -1 | awk '{print "   └─ " $5 " used (" $4 " available)"}'

        # 메모리 사용량
        echo ""
        echo "🧠 Memory Usage:"
        free -h | awk 'NR==2{print "   └─ " $3 "/" $2 " (" int($3/$2*100) "% used)"}'

        # Docker 리소스
        echo ""
        echo "🐳 Docker Resources:"
        echo "   └─ Images: $(docker images -q | wc -l)"
        echo "   └─ Containers: $(docker ps -q | wc -l) running / $(docker ps -aq | wc -l) total"
        echo "   └─ Volumes: $(docker volume ls -q | wc -l)"
    fi

    # JSON 출력
    if [ "$JSON_OUTPUT" = true ]; then
        local json_results=$(IFS=,; echo "${results[*]}")
        echo "{\"timestamp\":\"$(date -Iseconds)\",\"healthy\":${all_healthy},\"services\":[${json_results}]}"
    else
        echo ""
        echo "============================================"
        if [ "$all_healthy" = true ]; then
            echo -e "  Overall Status: ${GREEN}HEALTHY${NC}"
        else
            echo -e "  Overall Status: ${RED}UNHEALTHY${NC}"
        fi
        echo "============================================"
        echo ""
    fi

    # 종료 코드
    if [ "$all_healthy" = true ]; then
        exit 0
    else
        exit 1
    fi
}

# =============================================================================
# Run
# =============================================================================

perform_health_check
