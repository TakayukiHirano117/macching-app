variable "aws_region" {
  type        = string
  description = "State bucket を置くリージョン"
  default     = "ap-northeast-1"
}

variable "state_bucket_name" {
  type        = string
  description = "Terraform remote state 用 S3 bucket 名（グローバル一意）"
  default     = "macching-app-tfstate-615299732848"
}
