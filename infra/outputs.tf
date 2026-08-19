output "alb_dns_name" {
  description = "Public address of the load balancer"
  value       = aws_lb.main.dns_name
}

output "target_group_arn" {
  description = "Target group ARN, used by the deploy pipeline"
  value       = aws_lb_target_group.app.arn
}

output "db_secret_name" {
  description = "Secrets Manager entry holding the database credentials"
  value       = aws_secretsmanager_secret.db.name
}

output "db_endpoint" {
  description = "RDS endpoint address"
  value       = aws_db_instance.main.address
}

output "instance_ids" {
  description = "App server instance IDs by deployment group"
  value = {
    for name, inst in aws_instance.app : name => inst.id
  }
}

output "artifact_bucket" {
  description = "S3 bucket holding build artifacts"
  value       = aws_s3_bucket.artifacts.id
}