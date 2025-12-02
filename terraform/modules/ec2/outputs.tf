# =============================================================================
# EC2 Module - Outputs
# =============================================================================

output "instance_id" {
  description = "EC2 인스턴스 ID"
  value       = aws_instance.backend.id
}

output "instance_arn" {
  description = "EC2 인스턴스 ARN"
  value       = aws_instance.backend.arn
}

output "private_ip" {
  description = "프라이빗 IP 주소"
  value       = aws_instance.backend.private_ip
}

output "public_ip" {
  description = "퍼블릭 IP 주소 (Elastic IP 사용 시 해당 IP)"
  value       = var.create_elastic_ip ? aws_eip.backend[0].public_ip : aws_instance.backend.public_ip
}

output "public_dns" {
  description = "퍼블릭 DNS 이름"
  value       = aws_instance.backend.public_dns
}

output "elastic_ip" {
  description = "Elastic IP 주소 (생성된 경우)"
  value       = var.create_elastic_ip ? aws_eip.backend[0].public_ip : null
}

output "iam_role_arn" {
  description = "EC2 IAM Role ARN"
  value       = aws_iam_role.ec2_role.arn
}

output "iam_instance_profile_name" {
  description = "IAM Instance Profile 이름"
  value       = aws_iam_instance_profile.ec2_profile.name
}

output "ssh_connection_string" {
  description = "SSH 접속 명령어"
  value       = "ssh -i <your-key.pem> ec2-user@${var.create_elastic_ip ? aws_eip.backend[0].public_ip : aws_instance.backend.public_ip}"
}
