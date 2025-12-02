# Yeirin 인프라 설정 가이드

> 개발 환경 설정부터 프로덕션 배포까지 단계별 가이드

## 목차
1. [사전 요구사항](#사전-요구사항)
2. [AWS 초기 설정](#aws-초기-설정)
3. [Terraform 설정](#terraform-설정)
4. [EC2 초기 설정](#ec2-초기-설정)
5. [Docker 환경 설정](#docker-환경-설정)
6. [GitHub Actions 설정](#github-actions-설정)
7. [SSL 인증서 설정](#ssl-인증서-설정)
8. [Vercel 연동](#vercel-연동)

---

## 사전 요구사항

### 로컬 개발 환경

#### 1. AWS CLI 설치

```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# 설치 확인
aws --version
```

#### 2. Terraform 설치

```bash
# macOS
brew install terraform

# Linux
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# 설치 확인
terraform --version
```

#### 3. Docker 및 Docker Compose 설치

```bash
# macOS
brew install docker docker-compose

# Linux (Docker)
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Linux (Docker Compose)
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# 설치 확인
docker --version
docker-compose --version
```

#### 4. 기타 도구

```bash
# jq (JSON 파싱)
brew install jq  # macOS
sudo apt install jq  # Linux

# GitHub CLI (선택사항)
brew install gh  # macOS
```

### AWS 계정 요구사항

- AWS 계정 및 IAM 사용자
- 프로그래밍 방식 액세스 (Access Key ID, Secret Access Key)
- 필요한 IAM 권한:
  - EC2 Full Access
  - VPC Full Access
  - ECR Full Access
  - S3 Full Access (Terraform 상태 저장용)
  - DynamoDB Full Access (Terraform 상태 잠금용)
  - CloudWatch Full Access
  - IAM Limited Access (역할 생성용)

---

## AWS 초기 설정

### 1. AWS CLI 설정

```bash
aws configure
# AWS Access Key ID: <YOUR_ACCESS_KEY>
# AWS Secret Access Key: <YOUR_SECRET_KEY>
# Default region name: ap-northeast-2
# Default output format: json

# 설정 확인
aws sts get-caller-identity
```

### 2. Terraform 상태 저장용 S3 버킷 생성

```bash
# S3 버킷 생성 (버킷 이름은 전역적으로 고유해야 함)
aws s3api create-bucket \
  --bucket yeirin-terraform-state \
  --region ap-northeast-2 \
  --create-bucket-configuration LocationConstraint=ap-northeast-2

# 버전 관리 활성화
aws s3api put-bucket-versioning \
  --bucket yeirin-terraform-state \
  --versioning-configuration Status=Enabled

# 암호화 활성화
aws s3api put-bucket-encryption \
  --bucket yeirin-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
```

### 3. DynamoDB 테이블 생성 (상태 잠금용)

```bash
aws dynamodb create-table \
  --table-name yeirin-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-northeast-2
```

### 4. SSH 키 생성 및 등록

```bash
# SSH 키 생성
ssh-keygen -t rsa -b 4096 -f ~/.ssh/yeirin-ec2 -C "yeirin-ec2"

# AWS에 키 등록
aws ec2 import-key-pair \
  --key-name yeirin-ec2 \
  --public-key-material fileb://~/.ssh/yeirin-ec2.pub \
  --region ap-northeast-2
```

---

## Terraform 설정

### 1. 환경별 설정 파일 생성

```bash
cd terraform/environments/dev

# 템플릿 복사
cp terraform.tfvars.example terraform.tfvars
```

### 2. terraform.tfvars 편집

```hcl
# terraform/environments/dev/terraform.tfvars

# 프로젝트 설정
project_name = "yeirin"
environment  = "dev"
aws_region   = "ap-northeast-2"

# 네트워크 설정
vpc_cidr = "10.0.0.0/16"

# EC2 설정
ec2_instance_type = "t3.small"
ec2_key_name      = "yeirin-ec2"
ec2_volume_size   = 30

# 접근 제어 (본인 IP로 변경)
ssh_allowed_ips = ["YOUR_IP/32"]

# ECR 설정
ecr_repositories = ["yeirin/api-gateway", "yeirin/yeirin-ai", "yeirin/soul-e"]

# 알림 (선택사항)
alert_email = "admin@yeirin.com"
```

### 3. Terraform 초기화 및 적용

```bash
# 초기화
terraform init

# 계획 확인
terraform plan -out=tfplan

# 적용
terraform apply tfplan

# 출력값 확인
terraform output
```

### 4. 주요 출력값 저장

```bash
# EC2 IP 저장
EC2_IP=$(terraform output -raw ec2_public_ip)
echo "EC2 IP: $EC2_IP"

# ECR 레지스트리 URL 저장
ECR_REGISTRY=$(terraform output -raw ecr_registry_url)
echo "ECR Registry: $ECR_REGISTRY"
```

---

## EC2 초기 설정

### 1. EC2 접속

```bash
ssh -i ~/.ssh/yeirin-ec2 ec2-user@$EC2_IP
```

### 2. 초기 설정 스크립트 실행

```bash
# 스크립트 복사 (로컬에서)
scp -i ~/.ssh/yeirin-ec2 scripts/setup-ec2.sh ec2-user@$EC2_IP:/tmp/

# EC2에서 실행
sudo bash /tmp/setup-ec2.sh
```

### 3. Docker 파일 복사

```bash
# 로컬에서 EC2로 복사
scp -i ~/.ssh/yeirin-ec2 -r docker/* ec2-user@$EC2_IP:/opt/yeirin/docker/
```

### 4. 환경변수 설정

```bash
# EC2에서 실행
cd /opt/yeirin/docker
cp .env.example .env
nano .env  # 또는 vim
```

필수 환경변수:
```bash
# AWS
ECR_REGISTRY=<AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com
IMAGE_TAG=latest

# 데이터베이스
DATABASE_NAME=yeirin
DATABASE_USER=yeirin
DATABASE_PASSWORD=<SECURE_PASSWORD>

# JWT
JWT_SECRET=<SECURE_32_CHAR_SECRET>
JWT_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# OpenAI (Soul-E)
OPENAI_API_KEY=<YOUR_OPENAI_KEY>

# 도메인 (SSL용)
BACKEND_DOMAIN=api.yeirin.com
LETSENCRYPT_EMAIL=admin@yeirin.com

# CORS
FRONTEND_URLS=https://yeirin.vercel.app
```

### 5. 서비스 시작

```bash
# ECR 로그인
/opt/yeirin/scripts/ecr-login.sh

# 서비스 시작 (개발)
cd /opt/yeirin/docker
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# 서비스 시작 (프로덕션)
docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d

# 상태 확인
docker-compose ps
```

---

## GitHub Actions 설정

### 1. Repository Secrets 설정

GitHub Repository → Settings → Secrets and variables → Actions

| Secret | 설명 | 예시 |
|--------|------|------|
| `AWS_ACCESS_KEY_ID` | AWS 액세스 키 | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | AWS 시크릿 키 | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_ACCOUNT_ID` | AWS 계정 ID | `123456789012` |
| `EC2_HOST_DEV` | 개발 EC2 IP | `3.35.xxx.xxx` |
| `EC2_HOST_PROD` | 프로덕션 EC2 IP | `52.79.xxx.xxx` |
| `EC2_SSH_KEY` | EC2 SSH 프라이빗 키 | `~/.ssh/yeirin-ec2` 내용 |
| `SLACK_WEBHOOK_URL` | Slack 알림 URL (선택) | `https://hooks.slack.com/...` |
| `BACKEND_DOMAIN` | 백엔드 도메인 | `api.yeirin.com` |

### 2. SSH 키 등록

```bash
# 프라이빗 키 내용 복사
cat ~/.ssh/yeirin-ec2 | pbcopy  # macOS
```

GitHub Secret `EC2_SSH_KEY`에 붙여넣기

### 3. Environment 설정 (선택사항)

프로덕션 배포 승인을 위해:

1. GitHub Repository → Settings → Environments
2. "production" 환경 생성
3. "Required reviewers" 활성화
4. 승인자 지정

---

## SSL 인증서 설정

### Let's Encrypt 자동 발급 (권장)

Docker Compose에 포함된 Certbot 설정:

```bash
# EC2에서 실행
cd /opt/yeirin/docker

# Certbot 컨테이너로 인증서 발급
docker-compose run --rm certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  -d api.yeirin.com \
  --email admin@yeirin.com \
  --agree-tos \
  --no-eff-email

# Nginx 재시작
docker-compose restart nginx
```

### 인증서 자동 갱신

Cron 작업 추가:
```bash
# crontab 편집
crontab -e

# 매월 1일 자동 갱신
0 0 1 * * cd /opt/yeirin/docker && docker-compose run --rm certbot renew && docker-compose restart nginx
```

---

## Vercel 연동

### 1. Vercel 프로젝트 설정

1. Vercel 대시보드 접속
2. "Import Project" → GitHub 연결
3. `yeirin-frontend` 리포지토리 선택

### 2. 환경변수 설정

Vercel Project → Settings → Environment Variables

| Variable | Value | Environment |
|----------|-------|-------------|
| `NEXT_PUBLIC_API_URL` | `https://api.yeirin.com` | Production |
| `NEXT_PUBLIC_API_URL` | `https://dev.api.yeirin.com` | Preview |
| `NEXT_PUBLIC_API_URL` | `http://localhost:3000` | Development |

### 3. 도메인 설정 (선택사항)

1. Vercel Project → Settings → Domains
2. 커스텀 도메인 추가 (예: `yeirin.com`)
3. DNS 레코드 설정

---

## 배포 테스트

### 1. 로컬에서 Docker 이미지 빌드 및 푸시

```bash
# ECR 로그인
aws ecr get-login-password --region ap-northeast-2 | \
  docker login --username AWS --password-stdin $ECR_REGISTRY

# 이미지 빌드 (예: api-gateway)
cd backend/yeirin
docker build -t $ECR_REGISTRY/yeirin/api-gateway:test .

# 푸시
docker push $ECR_REGISTRY/yeirin/api-gateway:test
```

### 2. EC2에서 배포

```bash
# EC2 접속
ssh -i ~/.ssh/yeirin-ec2 ec2-user@$EC2_IP

# 배포
cd /opt/yeirin
./scripts/deploy.sh dev api-gateway
```

### 3. 헬스체크

```bash
# 로컬에서
curl -f https://api.yeirin.com/health

# 또는 EC2에서
./scripts/health-check.sh
```

---

## 다음 단계

1. **도메인 설정**: Route 53 또는 외부 DNS에서 도메인 설정
2. **모니터링 설정**: CloudWatch 대시보드 및 알림 설정
3. **백업 설정**: PostgreSQL 데이터 백업 전략 수립
4. **보안 강화**: WAF, Shield 등 추가 보안 설정 검토

문제가 발생하면 [troubleshooting.md](./troubleshooting.md)를 참고하세요.
