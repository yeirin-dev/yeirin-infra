# Yeirin 인프라 아키텍처

## 전체 시스템 아키텍처

```mermaid
flowchart TB
    subgraph Internet
        USER[👤 사용자]
    end

    subgraph Vercel["☁️ Vercel"]
        FE[Next.js Frontend]
    end

    subgraph AWS["☁️ AWS Cloud"]
        subgraph VPC["VPC (10.0.0.0/16)"]
            subgraph PublicSubnet["Public Subnet"]
                subgraph EC2["EC2 Instance"]
                    subgraph Docker["Docker Compose"]
                        NGINX[🔀 Nginx<br/>SSL/CORS]
                        API[📡 Yeirin API<br/>NestJS :3000]
                        AI[🤖 Yeirin AI<br/>FastAPI :8001]
                        SOUL[💬 Soul-E<br/>FastAPI :8000]
                        PG[(PostgreSQL<br/>:5432)]
                        REDIS[(Redis<br/>:6379)]
                    end
                end
            end
            IGW[🌐 Internet Gateway]
        end
        ECR[📦 ECR Registry]
        S3[🗄️ S3 Bucket]
    end

    subgraph External["🌍 External APIs"]
        OPENAI[OpenAI API]
    end

    USER -->|HTTPS| FE
    FE -->|HTTPS| NGINX
    NGINX --> API
    NGINX --> AI
    NGINX --> SOUL
    API --> PG
    API --> REDIS
    API --> S3
    AI --> PG
    SOUL --> PG
    SOUL --> REDIS
    SOUL -->|GPT| OPENAI
    ECR -.->|Pull Images| EC2
    PublicSubnet --> IGW
```

## MSA 서비스 구성

```mermaid
flowchart LR
    subgraph Services["마이크로서비스"]
        subgraph API["Yeirin API Gateway"]
            API_DESC["NestJS :3000<br/>━━━━━━━━━━<br/>• 회원 관리<br/>• 바우처 기관 관리<br/>• 상담 요청 관리<br/>• 파일 업로드 (S3)<br/>• JWT 인증"]
        end

        subgraph AI["Yeirin AI Service"]
            AI_DESC["FastAPI :8001<br/>━━━━━━━━━━<br/>• 상담의뢰지 분석<br/>• 협업 필터링 추천<br/>• 상담기관 매칭"]
        end

        subgraph SOUL["Soul-E Service"]
            SOUL_DESC["FastAPI :8000<br/>━━━━━━━━━━<br/>• OpenAI GPT 대화<br/>• 심리 검사 (KPRC)<br/>• 상담의뢰지 생성<br/>• SSE 스트리밍"]
        end
    end
```

### 서비스별 상세

| 서비스 | 프레임워크 | 포트 | 역할 |
|--------|-----------|------|------|
| **Yeirin API** | NestJS | 3000 | 메인 백엔드 API, 인증/인가 |
| **Yeirin AI** | FastAPI | 8001 | AI 기반 상담기관 추천 |
| **Soul-E** | FastAPI | 8000 | LLM 심리상담 챗봇 |

## 네트워크 아키텍처

```mermaid
flowchart TB
    subgraph VPC["🔒 VPC (10.0.0.0/16)"]
        subgraph PublicSubnet["📍 Public Subnet (10.0.1.0/24)"]
            subgraph EC2["💻 EC2 Instance"]
                subgraph DockerNetwork["🐳 Docker Network (yeirin-network)"]
                    NGINX[Nginx<br/>80, 443]

                    subgraph Backend["Backend Services"]
                        API[api-gateway<br/>:3000]
                        AI[yeirin-ai<br/>:8001]
                        SOUL[soul-e<br/>:8000]
                    end

                    subgraph Data["Data Layer"]
                        PG[(PostgreSQL<br/>:5432)]
                        REDIS[(Redis<br/>:6379)]
                    end
                end

                SG_NGINX[/"🛡️ nginx-sg<br/>80, 443, 22"/]
                SG_BACKEND[/"🛡️ backend-sg<br/>3000, 8000, 8001"/]
            end
        end
        IGW[🌐 Internet Gateway]
    end

    Internet((🌍 Internet)) --> IGW
    IGW --> NGINX
    NGINX --> API
    NGINX --> AI
    NGINX --> SOUL
    API --> PG
    API --> REDIS
    AI --> PG
    SOUL --> PG
    SOUL --> REDIS
```

## 보안 그룹 설정

```mermaid
flowchart LR
    subgraph nginx-sg["🛡️ nginx-sg"]
        direction TB
        IN1[/"Inbound"/]
        IN1_80["TCP 80<br/>0.0.0.0/0<br/>(Let's Encrypt)"]
        IN1_443["TCP 443<br/>0.0.0.0/0<br/>(HTTPS)"]
        IN1_22["TCP 22<br/>관리자 IP<br/>(SSH)"]
    end

    subgraph backend-sg["🛡️ backend-sg"]
        direction TB
        IN2[/"Inbound"/]
        IN2_3000["TCP 3000<br/>nginx-sg<br/>(API)"]
        IN2_8001["TCP 8001<br/>nginx-sg<br/>(AI)"]
        IN2_8000["TCP 8000<br/>nginx-sg<br/>(Soul-E)"]
        IN2_SELF["ALL<br/>self<br/>(내부 통신)"]
    end

    nginx-sg -->|"프록시"| backend-sg
```

### 보안 그룹 상세

#### Nginx Security Group (nginx-sg)
| 방향 | 프로토콜 | 포트 | 소스 | 설명 |
|------|---------|------|------|------|
| Inbound | TCP | 80 | 0.0.0.0/0 | HTTP (Let's Encrypt) |
| Inbound | TCP | 443 | 0.0.0.0/0 | HTTPS |
| Inbound | TCP | 22 | 관리자 IP | SSH |
| Outbound | ALL | ALL | 0.0.0.0/0 | 모든 아웃바운드 |

#### Backend Security Group (backend-sg)
| 방향 | 프로토콜 | 포트 | 소스 | 설명 |
|------|---------|------|------|------|
| Inbound | TCP | 3000 | nginx-sg | Yeirin API |
| Inbound | TCP | 8001 | nginx-sg | Yeirin AI |
| Inbound | TCP | 8000 | nginx-sg | Soul-E |
| Inbound | ALL | ALL | self | 내부 통신 |
| Outbound | ALL | ALL | 0.0.0.0/0 | 모든 아웃바운드 |

## 데이터 흐름

### 1. 사용자 인증 흐름

```mermaid
sequenceDiagram
    participant U as 👤 사용자
    participant V as Vercel (Frontend)
    participant N as Nginx
    participant A as Yeirin API
    participant DB as PostgreSQL

    U->>V: 로그인 요청
    V->>N: POST /api/auth/login
    N->>A: 프록시 전달
    A->>DB: 사용자 조회
    DB-->>A: 사용자 정보
    A-->>N: JWT 토큰 발급
    N-->>V: 응답
    V->>V: localStorage 저장
    V-->>U: 로그인 완료
```

### 2. 심리상담 (Soul-E) 흐름

```mermaid
sequenceDiagram
    participant U as 👤 사용자
    participant V as Vercel
    participant N as Nginx
    participant S as Soul-E
    participant O as OpenAI
    participant DB as PostgreSQL

    U->>V: 메시지 전송
    V->>N: POST /soul/chat
    N->>S: 프록시 전달
    S->>DB: 세션 조회/저장
    S->>O: GPT API 호출
    O-->>S: 스트리밍 응답
    S-->>N: SSE 스트리밍
    N-->>V: 실시간 전달
    V-->>U: 메시지 표시
```

### 3. AI 추천 흐름

```mermaid
sequenceDiagram
    participant U as 👤 사용자
    participant V as Vercel
    participant N as Nginx
    participant AI as Yeirin AI
    participant DB as PostgreSQL

    U->>V: 상담기관 추천 요청
    V->>N: POST /ai/recommend
    N->>AI: 프록시 전달
    AI->>DB: 상담의뢰지 조회
    AI->>AI: 협업 필터링 분석
    AI->>DB: 추천 결과 저장
    AI-->>N: 추천 기관 목록
    N-->>V: 응답
    V-->>U: 결과 표시
```

## 배포 아키텍처

```mermaid
flowchart TB
    subgraph GitHub["📂 GitHub Repository"]
        DEV[develop branch]
        MAIN[main branch]
    end

    subgraph Actions["⚙️ GitHub Actions"]
        GA_DEV[Deploy Dev<br/>Workflow]
        GA_PROD[Deploy Prod<br/>Workflow]
    end

    subgraph Build["🔨 Build Process"]
        BUILD_DEV[Docker Build<br/>dev-latest, :sha]
        BUILD_PROD[Docker Build<br/>latest, :sha]
    end

    subgraph ECR["📦 Amazon ECR"]
        ECR_DEV[yeirin/*:dev-latest]
        ECR_PROD[yeirin/*:latest]
    end

    subgraph Deploy["🚀 EC2 Deployment"]
        EC2_DEV[EC2 Dev<br/>t3.small]
        EC2_PROD[EC2 Prod<br/>t3.medium]
    end

    DEV -->|push| GA_DEV
    MAIN -->|push| GA_PROD
    GA_DEV --> BUILD_DEV
    GA_PROD -->|승인 필요| BUILD_PROD
    BUILD_DEV --> ECR_DEV
    BUILD_PROD --> ECR_PROD
    ECR_DEV -->|pull & deploy| EC2_DEV
    ECR_PROD -->|pull & deploy| EC2_PROD
```

### 배포 프로세스

```mermaid
flowchart LR
    subgraph CI["CI (Build)"]
        A[코드 변경 감지] --> B[Docker 이미지 빌드]
        B --> C[ECR 푸시]
    end

    subgraph CD["CD (Deploy)"]
        D[ECR 로그인] --> E[이미지 풀]
        E --> F[롤링 업데이트]
        F --> G{헬스체크}
        G -->|성공| H[완료]
        G -->|실패| I[자동 롤백]
    end

    CI --> CD
```

## 확장 전략

```mermaid
timeline
    title Yeirin 인프라 확장 로드맵

    section Phase 1 - MVP
        현재 : 단일 EC2 인스턴스
             : Docker Compose
             : 수동 스케일업
             : 예상 비용 $20-40/월

    section Phase 2 - 성장기
        사용자 증가 시 : 서비스별 EC2 분리
                      : RDS PostgreSQL
                      : ElastiCache Redis
                      : Application Load Balancer

    section Phase 3 - 스케일
        대규모 확장 시 : ECS/EKS 마이그레이션
                      : Auto Scaling
                      : Multi-AZ 구성
                      : CloudFront CDN
```

### Phase 상세

| Phase | 상태 | 주요 변경사항 | 예상 비용 |
|-------|------|--------------|----------|
| **Phase 1** | 현재 | 단일 EC2 + Docker Compose | $20-40/월 |
| **Phase 2** | 성장기 | 서비스 분리 + RDS + ALB | $100-200/월 |
| **Phase 3** | 스케일 | ECS/EKS + Auto Scaling | $300+/월 |

## 모니터링

```mermaid
flowchart TB
    subgraph Metrics["📊 CloudWatch 메트릭"]
        CPU[CPU 사용률]
        MEM[Memory 사용률]
        DISK[디스크 사용량]
        NET[네트워크 I/O]
    end

    subgraph Logs["📝 로그 관리"]
        APP_LOG[애플리케이션 로그]
        NGINX_LOG[Nginx 액세스/에러]
        DOCKER_LOG[Docker 컨테이너 로그]
    end

    subgraph Alerts["🚨 알림"]
        SLACK[Slack Webhook]
        EMAIL[Email 알림]
    end

    subgraph Triggers["⚡ 트리거 조건"]
        T1["CPU > 80%"]
        T2["헬스체크 실패"]
        T3["디스크 > 85%"]
    end

    Metrics --> Triggers
    Logs --> Triggers
    Triggers --> Alerts
```

### 모니터링 항목

| 카테고리 | 항목 | 임계치 | 알림 |
|---------|------|--------|------|
| CPU | 사용률 | > 80% | Slack |
| Memory | 사용률 | > 85% | Slack |
| Disk | 사용량 | > 85% | Slack + Email |
| Health | 헬스체크 | 실패 | Slack |
| Nginx | 5xx 에러 | > 10/min | Slack |
