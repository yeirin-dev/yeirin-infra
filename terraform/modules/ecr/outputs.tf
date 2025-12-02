# =============================================================================
# ECR Module - Outputs
# =============================================================================

output "repository_urls" {
  description = "ECR 레포지토리 URL 맵"
  value = {
    for name, repo in aws_ecr_repository.services :
    name => repo.repository_url
  }
}

output "repository_arns" {
  description = "ECR 레포지토리 ARN 맵"
  value = {
    for name, repo in aws_ecr_repository.services :
    name => repo.arn
  }
}

output "registry_id" {
  description = "ECR 레지스트리 ID (AWS 계정 ID)"
  value       = values(aws_ecr_repository.services)[0].registry_id
}

output "repository_names" {
  description = "생성된 ECR 레포지토리 이름 목록"
  value       = [for repo in aws_ecr_repository.services : repo.name]
}
