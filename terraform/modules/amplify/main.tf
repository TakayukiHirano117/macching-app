variable "name" {
  type = string
}

variable "repository" {
  type = string
}

variable "access_token" {
  type      = string
  sensitive = true
}

variable "branch_name" {
  type    = string
  default = "main"
}

variable "domain_name" {
  type = string
}

variable "api_base_url" {
  type = string
}

resource "aws_amplify_app" "this" {
  name         = var.name
  repository   = var.repository
  access_token = var.access_token
  platform     = "WEB_COMPUTE"

  # Amplify Hosting compute image does not include bun by default.
  # Install bun in preBuild, then build Next.js SSR artifacts.
  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        preBuild:
          commands:
            - curl -fsSL https://bun.sh/install | bash
            - export BUN_INSTALL="$HOME/.bun"
            - export PATH="$BUN_INSTALL/bin:$PATH"
            - bun --version
            - bun install --frozen-lockfile
        build:
          commands:
            - export BUN_INSTALL="$HOME/.bun"
            - export PATH="$BUN_INSTALL/bin:$PATH"
            - bun run build
      artifacts:
        baseDirectory: .next
        files:
          - '**/*'
      cache:
        paths:
          - node_modules/**/*
          - .next/cache/**/*
          - .bun/install/cache/**/*
  EOT

  environment_variables = {
    API_BASE_URL = var.api_base_url
    NODE_OPTIONS = "--max-old-space-size=4096"
  }
}

resource "aws_amplify_branch" "main" {
  app_id            = aws_amplify_app.this.id
  branch_name       = var.branch_name
  framework         = "Next.js - SSR"
  stage             = "PRODUCTION"
  enable_auto_build = true
}

resource "aws_amplify_domain_association" "this" {
  app_id      = aws_amplify_app.this.id
  domain_name = var.domain_name

  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = ""
  }

  wait_for_verification = false
}

output "app_id" {
  value = aws_amplify_app.this.id
}

output "default_domain" {
  value = aws_amplify_app.this.default_domain
}

output "branch_name" {
  value = aws_amplify_branch.main.branch_name
}
