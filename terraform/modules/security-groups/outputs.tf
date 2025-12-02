# =============================================================================
# Security Groups Module - Outputs
# =============================================================================

output "nginx_security_group_id" {
  description = "Nginx 보안 그룹 ID"
  value       = aws_security_group.nginx.id
}

output "backend_security_group_id" {
  description = "백엔드 서비스 보안 그룹 ID"
  value       = aws_security_group.backend.id
}

output "database_security_group_id" {
  description = "데이터베이스 보안 그룹 ID (RDS 활성화 시)"
  value       = var.enable_rds ? aws_security_group.database[0].id : null
}

output "all_security_group_ids" {
  description = "모든 보안 그룹 ID 맵"
  value = {
    nginx    = aws_security_group.nginx.id
    backend  = aws_security_group.backend.id
    database = var.enable_rds ? aws_security_group.database[0].id : null
  }
}
