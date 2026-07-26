variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "name_prefix" {
  type    = string
  default = "macching-prod"
}

variable "domain_name" {
  type    = string
  default = "hirano-ta.com"
}

variable "api_subdomain" {
  type    = string
  default = "api"
}

variable "images_subdomain" {
  type    = string
  default = "images"
}

variable "hosted_zone_id" {
  type        = string
  description = "既存 Route 53 hosted zone ID"
  default     = "Z05943451NKGYPEMM1T37"
}

variable "front_repository" {
  type        = string
  description = "Amplify に接続する Next.js リポジトリ"
  default     = "https://github.com/TakayukiHirano117/next-front"
}

variable "github_access_token" {
  type        = string
  description = "Amplify 用 GitHub personal access token。空なら Amplify は作成しない"
  sensitive   = true
  default     = ""
}

variable "enable_amplify" {
  type        = bool
  description = "Amplify Hosting を作成するか"
  default     = false
}

variable "db_name" {
  type    = string
  default = "macching"
}

variable "db_username" {
  type    = string
  default = "macching"
}

variable "container_image" {
  type        = string
  description = "初回は ECR URI:tag。未pushなら public bun イメージで作成後に差し替える"
  default     = ""
}
