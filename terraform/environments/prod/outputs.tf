output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster_name" {
  value = module.ecs_api.cluster_name
}

output "ecs_service_name" {
  value = module.ecs_api.service_name
}

output "api_url" {
  value = "https://${local.api_domain}/api/v1"
}

output "images_public_base_url" {
  value = module.s3_cdn.public_base_url
}

output "s3_bucket_name" {
  value = module.s3_cdn.bucket_name
}

output "alb_dns_name" {
  value = module.ecs_api.alb_dns_name
}

output "amplify_app_id" {
  value = try(module.amplify[0].app_id, null)
}

output "amplify_default_domain" {
  value = try(module.amplify[0].default_domain, null)
}

output "front_url" {
  value = "https://${var.domain_name}"
}

output "database_secret_arn" {
  value = aws_secretsmanager_secret.db_url.arn
}

output "github_actions_deploy_role_arn" {
  value = module.github_oidc_deploy.role_arn
}
