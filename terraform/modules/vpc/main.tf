# =============================================================================
# VPC Module
# =============================================================================
#
# 비용 최적화 설계:
# - NAT Gateway 없이 퍼블릭 서브넷만 사용 (NAT Gateway: 월 $32+ 절감)
# - 단일 AZ로 시작 (필요시 Multi-AZ 확장 가능)
# - 인터넷 게이트웨이만 사용 (무료)
#
# 네트워크 구성:
# - VPC CIDR: 10.0.0.0/16 (65,536 IPs)
# - Public Subnet: 10.0.1.0/24 (256 IPs) - EC2, RDS 등
# - 추후 확장용 서브넷 대역 예약
# =============================================================================

# =============================================================================
# VPC
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpc"
  })
}

# =============================================================================
# Internet Gateway (무료)
# =============================================================================

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-igw"
  })
}

# =============================================================================
# Public Subnets
# =============================================================================
#
# 비용 절감: NAT Gateway 대신 퍼블릭 서브넷 사용
# 보안: Security Group으로 인바운드 트래픽 제어
# =============================================================================

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-${var.availability_zones[count.index]}"
    Type = "Public"
  })
}

# =============================================================================
# Route Tables
# =============================================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# VPC Endpoints (선택적 - 비용 절감)
# =============================================================================
#
# S3 Gateway Endpoint는 무료이며 S3 트래픽이 인터넷을 거치지 않음
# ECR 접근 시 S3에서 이미지 레이어를 다운로드하므로 유용
# =============================================================================

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-${var.environment}-s3-endpoint"
  })
}
