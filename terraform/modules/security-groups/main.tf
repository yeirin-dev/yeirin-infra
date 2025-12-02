# =============================================================================
# Security Groups Module
# =============================================================================
#
# Yeirin MSA 아키텍처용 보안 그룹:
# 1. ALB/Nginx Security Group - HTTPS 인바운드
# 2. Backend Services Security Group - 내부 서비스 통신
# 3. Database Security Group - RDS 접근 (옵션)
#
# 서비스 포트:
# - yeirin (NestJS API Gateway): 3000
# - yeirin-ai (FastAPI AI Service): 8001
# - soul-e (FastAPI LLM Chatbot): 8000
# =============================================================================

# =============================================================================
# Reverse Proxy Security Group (Nginx)
# =============================================================================
#
# 외부에서 접근 가능한 유일한 진입점
# Vercel 프론트엔드에서의 API 요청 허용
# =============================================================================

resource "aws_security_group" "nginx" {
  name        = "${var.project_name}-${var.environment}-nginx-sg"
  description = "Security group for Nginx reverse proxy"
  vpc_id      = var.vpc_id

  # HTTP (Let's Encrypt 인증서 발급용)
  ingress {
    description = "HTTP for Let's Encrypt"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS (메인 트래픽)
  ingress {
    description = "HTTPS from anywhere (Vercel frontend)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH (관리용 - 특정 IP만)
  dynamic "ingress" {
    for_each = var.allowed_ssh_cidrs
    content {
      description = "SSH from allowed IPs"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # 모든 아웃바운드 허용
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-nginx-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Backend Services Security Group
# =============================================================================
#
# 내부 서비스 간 통신용
# Nginx에서만 접근 가능
# =============================================================================

resource "aws_security_group" "backend" {
  name        = "${var.project_name}-${var.environment}-backend-sg"
  description = "Security group for backend microservices"
  vpc_id      = var.vpc_id

  # Yeirin API Gateway (NestJS) - Nginx에서 접근
  ingress {
    description     = "Yeirin API from Nginx"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  # Yeirin AI Service (FastAPI) - Nginx에서 접근
  ingress {
    description     = "Yeirin AI from Nginx"
    from_port       = 8001
    to_port         = 8001
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  # Soul-E LLM Service (FastAPI) - Nginx에서 접근
  ingress {
    description     = "Soul-E from Nginx"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  # 내부 서비스 간 통신 (같은 SG 내)
  ingress {
    description = "Internal service communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  # SSH (관리용 - Nginx SG에서만)
  ingress {
    description     = "SSH from Nginx/Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.nginx.id]
  }

  # 모든 아웃바운드 허용 (ECR, 외부 API 등)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-backend-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Database Security Group (Optional)
# =============================================================================
#
# RDS 사용 시 활성화
# 현재는 EC2 내부 Docker로 PostgreSQL 실행 가정
# =============================================================================

resource "aws_security_group" "database" {
  count = var.enable_rds ? 1 : 0

  name        = "${var.project_name}-${var.environment}-db-sg"
  description = "Security group for RDS database"
  vpc_id      = var.vpc_id

  # PostgreSQL - 백엔드 서비스에서만 접근
  ingress {
    description     = "PostgreSQL from backend services"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  # 아웃바운드 불필요 (RDS는 아웃바운드 안 함)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-db-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}
