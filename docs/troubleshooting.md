# Yeirin 인프라 문제 해결 가이드

> 자주 발생하는 문제와 해결 방법

## 목차
1. [배포 관련 문제](#배포-관련-문제)
2. [Docker 관련 문제](#docker-관련-문제)
3. [네트워크/CORS 문제](#네트워크cors-문제)
4. [SSL/인증서 문제](#ssl인증서-문제)
5. [데이터베이스 문제](#데이터베이스-문제)
6. [성능 문제](#성능-문제)
7. [디버깅 팁](#디버깅-팁)

---

## 배포 관련 문제

### ECR 로그인 실패

**증상:**
```
Error: Cannot perform an interactive login from a non TTY device
```

**해결:**
```bash
# AWS CLI v2 사용 확인
aws --version

# 올바른 로그인 명령어
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin \
  <ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com

# IAM 권한 확인
aws sts get-caller-identity
```

### 이미지 푸시 실패

**증상:**
```
denied: Your authorization token has expired. Reauthenticate and try again.
```

**해결:**
```bash
# ECR 재로그인 (토큰은 12시간 유효)
/opt/yeirin/scripts/ecr-login.sh

# 또는 직접 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin $ECR_REGISTRY
```

### GitHub Actions 배포 실패

**증상:**
```
Error: ssh: connect to host xxx port 22: Connection timed out
```

**해결:**
1. EC2 보안 그룹에서 GitHub Actions IP 허용
2. 또는 모든 IP에서 SSH 허용 (개발 환경만)

```bash
# GitHub Actions IP 범위 확인
curl -s https://api.github.com/meta | jq '.actions[]'
```

보안 그룹 수정:
```hcl
# terraform/environments/dev/main.tf
ssh_allowed_ips = ["0.0.0.0/0"]  # 개발용만
```

---

## Docker 관련 문제

### 컨테이너 시작 실패

**증상:**
```
ERROR: for api-gateway  Container exited with code 1
```

**디버깅:**
```bash
# 로그 확인
docker-compose logs api-gateway

# 상세 로그
docker logs yeirin-api-gateway --tail 100

# 컨테이너 내부 확인
docker-compose run --rm api-gateway sh
```

**일반적인 원인:**
1. 환경변수 누락 → `.env` 파일 확인
2. 포트 충돌 → `docker ps` 확인
3. 볼륨 권한 → `chmod` 확인

### 메모리 부족

**증상:**
```
Cannot allocate memory
```

**해결:**
```bash
# 스왑 확인
free -h

# 스왑 없으면 생성
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 영구 적용
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Docker 메모리 제한 조정
# docker-compose.prod.yml에서 mem_limit 조정
```

### 이미지 풀 실패

**증상:**
```
Error response from daemon: pull access denied
```

**해결:**
```bash
# ECR 로그인 확인
cat ~/.docker/config.json | jq '.auths'

# 이미지 존재 확인
aws ecr describe-images \
  --repository-name yeirin/api-gateway \
  --region ap-northeast-2

# 이미지 태그 확인
aws ecr list-images \
  --repository-name yeirin/api-gateway \
  --region ap-northeast-2
```

### 디스크 공간 부족

**증상:**
```
no space left on device
```

**해결:**
```bash
# 디스크 사용량 확인
df -h

# Docker 정리
docker system prune -af
docker volume prune -f

# 오래된 이미지 정리
docker images | grep "none" | awk '{print $3}' | xargs docker rmi

# 로그 정리
sudo truncate -s 0 /var/lib/docker/containers/*/*-json.log
```

---

## 네트워크/CORS 문제

### CORS 에러

**증상:**
```
Access to fetch at 'https://api.yeirin.com' from origin 'https://yeirin.vercel.app'
has been blocked by CORS policy
```

**해결:**

1. Nginx CORS 설정 확인:
```nginx
# docker/nginx/nginx.conf
location /api/ {
    # CORS 헤더
    add_header 'Access-Control-Allow-Origin' '$http_origin' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type, X-Requested-With' always;
    add_header 'Access-Control-Allow-Credentials' 'true' always;

    # Preflight 요청 처리
    if ($request_method = 'OPTIONS') {
        add_header 'Access-Control-Allow-Origin' '$http_origin';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type, X-Requested-With';
        add_header 'Access-Control-Allow-Credentials' 'true';
        add_header 'Content-Length' 0;
        add_header 'Content-Type' 'text/plain';
        return 204;
    }

    proxy_pass http://api-gateway:3000/;
}
```

2. 허용 도메인 추가:
```nginx
# map 블록에 도메인 추가
map $http_origin $cors_origin {
    default "";
    "~^https://yeirin\.vercel\.app$" $http_origin;
    "~^https://.*\.yeirin\.com$" $http_origin;
    "~^https://yeirin\.com$" $http_origin;
    "~^http://localhost:3001$" $http_origin;  # 개발용
}
```

3. Nginx 재시작:
```bash
docker-compose restart nginx
```

### 502 Bad Gateway

**증상:**
```
502 Bad Gateway - nginx
```

**디버깅:**
```bash
# 백엔드 서비스 상태 확인
docker-compose ps

# Nginx 에러 로그
docker-compose logs nginx --tail 100

# 내부 연결 테스트
docker-compose exec nginx curl -v http://api-gateway:3000/health
```

**일반적인 원인:**
1. 백엔드 서비스 다운 → `docker-compose up -d`
2. 잘못된 upstream 설정 → `nginx.conf` 확인
3. 네트워크 문제 → Docker 네트워크 재생성

```bash
# Docker 네트워크 재생성
docker-compose down
docker network rm yeirin-network
docker-compose up -d
```

### 연결 타임아웃

**증상:**
```
upstream timed out (110: Connection timed out)
```

**해결:**
```nginx
# nginx.conf - 타임아웃 증가
location /api/ {
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    # ...
}
```

---

## SSL/인증서 문제

### 인증서 발급 실패

**증상:**
```
Certbot failed to authenticate some domains
```

**해결:**
```bash
# DNS 확인
dig api.yeirin.com

# 80 포트 접근 확인
curl -v http://api.yeirin.com/.well-known/acme-challenge/test

# Nginx 설정 확인 (Let's Encrypt용 경로)
location /.well-known/acme-challenge/ {
    root /var/www/certbot;
}
```

### 인증서 만료

**증상:**
```
NET::ERR_CERT_DATE_INVALID
```

**해결:**
```bash
# 인증서 상태 확인
docker-compose exec nginx openssl x509 -in /etc/letsencrypt/live/api.yeirin.com/cert.pem -noout -dates

# 수동 갱신
docker-compose run --rm certbot renew

# Nginx 재시작
docker-compose restart nginx
```

### Mixed Content 에러

**증상:**
```
Mixed Content: The page was loaded over HTTPS, but requested an insecure resource
```

**해결:**
1. 프론트엔드에서 API URL이 HTTPS인지 확인:
```javascript
// .env.local
NEXT_PUBLIC_API_URL=https://api.yeirin.com  // http가 아닌 https
```

2. 백엔드 응답에서 HTTP URL 제거

---

## 데이터베이스 문제

### PostgreSQL 연결 실패

**증상:**
```
ECONNREFUSED 127.0.0.1:5432
```

**해결:**
```bash
# PostgreSQL 상태 확인
docker-compose ps postgres

# 로그 확인
docker-compose logs postgres

# 직접 연결 테스트
docker-compose exec postgres psql -U yeirin -d yeirin

# 환경변수 확인
docker-compose exec api-gateway env | grep DATABASE
```

### 데이터베이스 복구

```bash
# 백업
docker-compose exec postgres pg_dump -U yeirin yeirin > backup.sql

# 복원
cat backup.sql | docker-compose exec -T postgres psql -U yeirin yeirin
```

### Redis 연결 문제

**증상:**
```
Redis connection error: ECONNREFUSED
```

**해결:**
```bash
# Redis 상태 확인
docker-compose exec redis redis-cli ping

# 메모리 확인
docker-compose exec redis redis-cli info memory

# 연결 수 확인
docker-compose exec redis redis-cli client list
```

---

## 성능 문제

### 느린 응답 시간

**디버깅:**
```bash
# API 응답 시간 측정
curl -w "@curl-format.txt" -o /dev/null -s https://api.yeirin.com/health

# curl-format.txt 내용:
#     time_namelookup:  %{time_namelookup}\n
#        time_connect:  %{time_connect}\n
#     time_appconnect:  %{time_appconnect}\n
#    time_pretransfer:  %{time_pretransfer}\n
#       time_redirect:  %{time_redirect}\n
#  time_starttransfer:  %{time_starttransfer}\n
#                     ----------\n
#          time_total:  %{time_total}\n
```

**일반적인 원인:**
1. 데이터베이스 쿼리 최적화 필요
2. 메모리 부족 → 스왑 추가
3. CPU 부족 → 인스턴스 업그레이드

### 높은 CPU 사용량

```bash
# 프로세스별 CPU 확인
docker stats

# 상세 확인
htop

# 특정 컨테이너 리소스 제한
# docker-compose.prod.yml
services:
  api-gateway:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
```

---

## 디버깅 팁

### 로그 확인 명령어 모음

```bash
# 모든 서비스 로그
docker-compose logs -f

# 특정 서비스 로그
docker-compose logs -f api-gateway

# 최근 N줄
docker-compose logs --tail 100 api-gateway

# 타임스탬프 포함
docker-compose logs -f -t api-gateway

# 로그 파일로 저장
docker-compose logs > logs.txt 2>&1
```

### 컨테이너 내부 디버깅

```bash
# 실행 중인 컨테이너 진입
docker-compose exec api-gateway sh

# 새 컨테이너로 디버깅
docker-compose run --rm api-gateway sh

# 프로세스 확인
docker-compose exec api-gateway ps aux

# 네트워크 확인
docker-compose exec api-gateway netstat -tlnp
```

### 네트워크 디버깅

```bash
# 컨테이너 간 연결 테스트
docker-compose exec nginx curl -v http://api-gateway:3000/health
docker-compose exec api-gateway curl -v http://postgres:5432

# DNS 확인
docker-compose exec nginx nslookup api-gateway

# 포트 확인
docker-compose exec nginx netstat -tlnp
```

### 환경변수 확인

```bash
# 모든 환경변수 출력
docker-compose exec api-gateway env

# 특정 변수 확인
docker-compose exec api-gateway env | grep DATABASE
```

### 빠른 문제 진단 스크립트

```bash
#!/bin/bash
# diagnose.sh

echo "=== Docker 상태 ==="
docker-compose ps

echo -e "\n=== 디스크 사용량 ==="
df -h /

echo -e "\n=== 메모리 상태 ==="
free -h

echo -e "\n=== 최근 에러 로그 ==="
docker-compose logs --tail 20 2>&1 | grep -i error

echo -e "\n=== 헬스체크 ==="
for service in api-gateway yeirin-ai soul-e; do
  status=$(docker inspect --format='{{.State.Health.Status}}' yeirin-$service 2>/dev/null || echo "unknown")
  echo "$service: $status"
done
```

---

## 긴급 복구 절차

### 1. 전체 서비스 재시작

```bash
cd /opt/yeirin/docker
docker-compose down
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

### 2. 롤백

```bash
/opt/yeirin/scripts/rollback.sh prod
```

### 3. 데이터베이스 복구

```bash
# 최신 백업 확인
ls -la /opt/yeirin/backups/

# 복원
cat /opt/yeirin/backups/latest/database.sql | \
  docker-compose exec -T postgres psql -U yeirin yeirin
```

### 4. 완전 재설치

```bash
# 주의: 모든 데이터 삭제됨
docker-compose down -v
docker system prune -af
sudo bash /tmp/setup-ec2.sh
```

---

## 지원 요청 시 포함할 정보

문제 해결이 어려운 경우 다음 정보를 포함해 지원 요청:

```bash
# 시스템 정보 수집
echo "=== 시스템 정보 ===" > debug-info.txt
uname -a >> debug-info.txt
docker --version >> debug-info.txt
docker-compose --version >> debug-info.txt

echo -e "\n=== Docker 상태 ===" >> debug-info.txt
docker-compose ps >> debug-info.txt

echo -e "\n=== 로그 (최근 100줄) ===" >> debug-info.txt
docker-compose logs --tail 100 >> debug-info.txt 2>&1

echo -e "\n=== 리소스 사용량 ===" >> debug-info.txt
docker stats --no-stream >> debug-info.txt

# 결과 파일 공유
cat debug-info.txt
```
