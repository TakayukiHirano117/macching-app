data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs           = slice(data.aws_availability_zones.available.names, 0, 2)
  api_domain    = "${var.api_subdomain}.${var.domain_name}"
  images_domain = "${var.images_subdomain}.${var.domain_name}"
  front_origins = ["https://${var.domain_name}", "http://localhost:3001"]
  photos_bucket = "${var.name_prefix}-photos-${data.aws_caller_identity.current.account_id}"
  ecr_image     = var.container_image != "" ? var.container_image : "${module.ecr.repository_url}:latest"
}

resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

module "network" {
  source      = "../../modules/network"
  name_prefix = var.name_prefix
  azs         = local.azs
}

resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "Public ALB"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs" {
  name        = "${var.name_prefix}-ecs"
  description = "ECS Fargate tasks"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "ecr" {
  source = "../../modules/ecr"
  name   = "${var.name_prefix}-api"
}

module "rds" {
  source                = "../../modules/rds"
  name_prefix           = var.name_prefix
  vpc_id                = module.network.vpc_id
  private_subnet_ids    = module.network.private_subnet_ids
  ecs_security_group_id = aws_security_group.ecs.id
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = random_password.db.result
}

resource "aws_acm_certificate" "api" {
  domain_name       = local.api_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for record in aws_route53_record.api_cert_validation : record.fqdn]
}

resource "aws_acm_certificate" "images" {
  provider          = aws.us_east_1
  domain_name       = local.images_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "images_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.images.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "images" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.images.arn
  validation_record_fqdns = [for record in aws_route53_record.images_cert_validation : record.fqdn]
}

module "s3_cdn" {
  source              = "../../modules/s3_cdn"
  name_prefix         = var.name_prefix
  bucket_name         = local.photos_bucket
  images_domain       = local.images_domain
  front_origins       = local.front_origins
  acm_certificate_arn = aws_acm_certificate_validation.images.certificate_arn
}

module "ecs_api" {
  source                     = "../../modules/ecs_api"
  name_prefix                = var.name_prefix
  vpc_id                     = module.network.vpc_id
  public_subnet_ids          = module.network.public_subnet_ids
  private_subnet_ids         = module.network.private_subnet_ids
  alb_security_group_id      = aws_security_group.alb.id
  ecs_security_group_id      = aws_security_group.ecs.id
  container_image            = local.ecr_image
  database_url               = module.rds.database_url
  s3_bucket_name             = module.s3_cdn.bucket_name
  s3_bucket_arn              = module.s3_cdn.bucket_arn
  aws_region                 = var.aws_region
  cloudfront_public_base_url = module.s3_cdn.public_base_url
  acm_certificate_arn        = aws_acm_certificate_validation.api.certificate_arn
}

resource "aws_route53_record" "api" {
  zone_id = var.hosted_zone_id
  name    = local.api_domain
  type    = "A"

  alias {
    name                   = module.ecs_api.alb_dns_name
    zone_id                = module.ecs_api.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "images" {
  zone_id = var.hosted_zone_id
  name    = local.images_domain
  type    = "A"

  alias {
    name                   = module.s3_cdn.cloudfront_domain_name
    zone_id                = "Z2FDTNDATAQYW2" # CloudFront hosted zone ID (global)
    evaluate_target_health = false
  }
}

module "amplify" {
  count = var.enable_amplify && var.github_access_token != "" ? 1 : 0

  source       = "../../modules/amplify"
  name         = var.name_prefix
  repository   = var.front_repository
  access_token = var.github_access_token
  domain_name  = var.domain_name
  api_base_url = "https://${local.api_domain}/api/v1"
}

module "github_oidc_deploy" {
  source = "../../modules/github_oidc_deploy"

  name_prefix            = var.name_prefix
  github_repository      = var.github_deploy_repository
  ecr_repository_arn     = module.ecr.repository_arn
  ecs_cluster_name       = module.ecs_api.cluster_name
  ecs_service_name       = module.ecs_api.service_name
  ecs_execution_role_arn = module.ecs_api.execution_role_arn
  ecs_task_role_arn      = module.ecs_api.task_role_arn
}

resource "aws_secretsmanager_secret" "db_url" {
  name = "${var.name_prefix}/database-url"
}

resource "aws_secretsmanager_secret_version" "db_url" {
  secret_id     = aws_secretsmanager_secret.db_url.id
  secret_string = module.rds.database_url
}
