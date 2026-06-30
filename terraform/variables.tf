# ============================================================
# variables.tf — EKS 集群输入变量
# ============================================================
variable "aws_region" {
  description = "AWS 部署区域"
  type        = string
  default     = "us-east-1"
}

variable "github_token" {
  description = "GitHub Personal Access Token (classic)，用于自动注入 ARN 到仓库"
  type        = string
  sensitive   = true
}

variable "target_repositories" {
  description = "需要自动注入 AWS_ROLE_ARN 的业务仓库列表"
  type        = list(string)
  default     = ["log-analyze-agent", "platform-shared-services", "ai-infra-platform"]
}

variable "tags" {
  description = "通用资源标签"
  type        = map(string)
  default = {
    ManagedBy = "terraform"
    Project   = "ai-log-agent"
  }
}

variable "bucket_name" {
  description = "Terraform State 用的 S3 bucket 名称（全局唯一）"
  type        = string
  default     = "ai-log-agent-tfstate"
}
