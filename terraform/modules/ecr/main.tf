# =============================================================================
# ECR Module
# =============================================================================
#
# Yeirin MSA 서비스별 ECR 레포지토리:
# - yeirin/api-gateway (NestJS)
# - yeirin/yeirin-ai (FastAPI)
# - yeirin/soul-e (FastAPI)
#
# 비용 최적화:
# - Lifecycle Policy로 오래된 이미지 자동 삭제
# - Untagged 이미지 1일 후 삭제
# - 30일 이상 미사용 이미지 삭제 (최근 10개 보존)
# =============================================================================

# =============================================================================
# ECR Repositories
# =============================================================================

resource "aws_ecr_repository" "services" {
  for_each = toset(var.service_names)

  name                 = "${var.project_name}/${each.value}"
  image_tag_mutability = "MUTABLE" # latest 태그 덮어쓰기 허용

  # 이미지 스캔 설정 (보안 취약점 자동 검사)
  image_scanning_configuration {
    scan_on_push = var.enable_image_scanning
  }

  # 암호화 (기본 AES-256)
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.common_tags, {
    Name    = "${var.project_name}-${each.value}"
    Service = each.value
  })
}

# =============================================================================
# Lifecycle Policies (비용 최적화 핵심)
# =============================================================================

resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each = aws_ecr_repository.services

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        # Rule 1: Untagged 이미지 1일 후 삭제
        rulePriority = 1
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
      {
        # Rule 2: dev 태그 이미지는 최근 5개만 보존
        rulePriority = 2
        description  = "Keep only 5 dev images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["dev-"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      },
      {
        # Rule 3: prod 태그 이미지는 최근 10개만 보존
        rulePriority = 3
        description  = "Keep only 10 prod images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod-", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        # Rule 4: 30일 이상 된 모든 이미지 삭제 (위 규칙에 해당 안 되는 것)
        rulePriority = 10
        description  = "Delete images older than 30 days"
        selection = {
          tagStatus   = "any"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# =============================================================================
# Repository Policy (Optional - Cross-account access)
# =============================================================================

# CI/CD에서 이미지 푸시/풀 권한
resource "aws_ecr_repository_policy" "ci_access" {
  for_each = var.enable_ci_access ? aws_ecr_repository.services : {}

  repository = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPull"
        Effect = "Allow"
        Principal = {
          AWS = var.ci_role_arns
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}
