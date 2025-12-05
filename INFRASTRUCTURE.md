# Yeirin MSA Infrastructure

## 개요

3개의 독립적인 EC2 인스턴스 + RDS PostgreSQL 기반의 MSA 아키텍처

- **배포 방식**: Git Pull 기반 GitHub Actions CI/CD
- **리전**: ap-northeast-2 (서울)
- **VPC**: vpc-0c5049a097d2099d5 (172.31.0.0/16)

---

## EC2 인스턴스 정보

### 1. Yeirin Backend (NestJS)

| 항목 | 값 |
|------|-----|
| Instance ID | `i-09b64f750cd1cba2d` |
| Instance Type | t3.small (2 vCPU, 2GB RAM) |
| Public IP | `3.38.162.252` |
| Private IP | `172.31.8.69` |
| Port | 3000 |
| OS | Amazon Linux 2023 |
| Runtime | Node.js 20 + Yarn |

**SSH 접속:**
```bash
ssh -i ~/.ssh/yeirin-dev-key.pem ec2-user@3.38.162.252
```

**서비스 관리:**
```bash
sudo systemctl status yeirin
sudo systemctl restart yeirin
sudo journalctl -u yeirin -f
```

---

### 2. Soul-E Backend (FastAPI)

| 항목 | 값 |
|------|-----|
| Instance ID | `i-00ba02ecce347ef12` |
| Instance Type | t3.small (2 vCPU, 2GB RAM) |
| Public IP | `43.202.32.196` |
| Private IP | `172.31.0.25` |
| Port | 8000 |
| OS | Amazon Linux 2023 |
| Runtime | Python 3.12 + uv |

**SSH 접속:**
```bash
ssh -i ~/.ssh/yeirin-dev-key.pem ec2-user@43.202.32.196
```

**서비스 관리:**
```bash
sudo systemctl status soul-e
sudo systemctl restart soul-e
sudo journalctl -u soul-e -f
```

---

### 3. Yeirin-AI Backend (FastAPI + Playwright)

| 항목 | 값 |
|------|-----|
| Instance ID | `i-0193d7862f897c95f` |
| Instance Type | t3.medium (2 vCPU, 4GB RAM) |
| Public IP | `43.203.210.136` |
| Private IP | `172.31.9.114` |
| Port | 8001 |
| OS | Amazon Linux 2023 |
| Runtime | Python 3.11 + uv + Playwright |

**SSH 접속:**
```bash
ssh -i ~/.ssh/yeirin-dev-key.pem ec2-user@43.203.210.136
```

**서비스 관리:**
```bash
sudo systemctl status yeirin-ai
sudo systemctl restart yeirin-ai
sudo journalctl -u yeirin-ai -f
```

---

## RDS PostgreSQL

| 항목 | 값 |
|------|-----|
| DB Instance ID | `yeirin-db` |
| Engine | PostgreSQL 15 |
| Instance Class | db.t3.micro |
| Endpoint | `yeirin-db.cr6i26cya9vi.ap-northeast-2.rds.amazonaws.com` |
| Port | 5432 |
| Database | `yeirin_dev` |
| Username | `yeirin` |
| Password | `yeirin123` |

**psql 접속:**
```bash
PGPASSWORD=yeirin123 psql -h <RDS_ENDPOINT> -U yeirin -d yeirin_dev
```

---

## Security Groups

### 1. yeirin-rds-sg (sg-022cde49c48e466c6)
- PostgreSQL 5432 from yeirin-backend-sg

### 2. yeirin-backend-sg (sg-088adb0d19802642b)
- SSH (22) from anywhere
- Yeirin (3000) from anywhere
- Soul-E (8000) from anywhere
- Yeirin-AI (8001) from anywhere

---

## IAM

### EC2 Instance Profile
- **Profile Name**: `yeirin-ec2-profile`
- **Role Name**: `yeirin-ec2-role`
- **Policies**:
  - `AmazonSSMReadOnlyAccess` (Parameter Store 읽기)
  - `AmazonS3FullAccess` (S3 파일 업로드)

---

## AWS Parameter Store

환경변수는 AWS SSM Parameter Store에서 관리:

```
/yeirin/dev/common/        # 공통 설정 (JWT, OpenAI API Key 등)
/yeirin/dev/yeirin/        # Yeirin 백엔드 설정
/yeirin/dev/soul-e/        # Soul-E 설정
/yeirin/dev/yeirin-ai/     # Yeirin-AI 설정
```

**Parameter 조회:**
```bash
aws ssm get-parameters-by-path --path "/yeirin/dev" --recursive --with-decryption
```

---

## 서비스 URL

| 서비스 | URL |
|--------|-----|
| Yeirin Backend | http://3.38.162.252:3000 |
| Soul-E Backend | http://43.202.32.196:8000 |
| Yeirin-AI Backend | http://43.203.210.136:8001 |

### Health Check Endpoints
- Yeirin: http://3.38.162.252:3000/health
- Soul-E: http://43.202.32.196:8000/health
- Yeirin-AI: http://43.203.210.136:8001/health

---

## 배포 가이드

### 수동 배포

각 서버에 SSH 접속 후:

```bash
cd ~/app/<service-name>
git pull origin deploy/dev
# Yeirin
yarn install && yarn build && sudo systemctl restart yeirin

# Soul-E / Yeirin-AI
uv sync && sudo systemctl restart <service-name>
```

### GitHub Actions CI/CD

`deploy/dev` 브랜치에 push 시 자동 배포:
- `.github/workflows/deploy-yeirin.yml`
- `.github/workflows/deploy-soul-e.yml`
- `.github/workflows/deploy-yeirin-ai.yml`

---

## 비용 예상 (월간)

| 리소스 | 스펙 | 예상 비용 (USD) |
|--------|------|----------------|
| EC2 yeirin-backend | t3.small | ~$15 |
| EC2 soul-e-backend | t3.small | ~$15 |
| EC2 yeirin-ai-backend | t3.medium | ~$30 |
| RDS yeirin-db | db.t3.micro | ~$12 |
| **Total** | | **~$72/월** |

---

## 문서 업데이트 이력

| 날짜 | 변경 내용 |
|------|-----------|
| 2025-12-05 | 초기 인프라 구성 |
