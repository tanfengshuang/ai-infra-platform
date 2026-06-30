# ============================================================
# iam-oidc.tf — GitHub Actions OIDC + IAM 角色 + ARN 自动注入
# ============================================================

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

# 1. 创建 AWS OIDC 身份提供商
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# 2. 创建 IAM 部署角色（白名单：只允许 log-analyze-agent 和 platform-shared-services）
resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-eks-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:tanfengshuang/log-analyze-agent:*",
              "repo:tanfengshuang/platform-shared-services:*",
            ]
          }
        }
      }
    ]
  })
}

# 3. 赋予角色完整 EKS/AWS 管控权限（生产环境建议缩小到最小权限）
resource "aws_iam_role_policy_attachment" "admin_attach" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ==========================================
# 4. 🌟 自动将 ARN 注入到各个业务仓库的 GitHub Variables
# ==========================================
resource "github_actions_variable" "aws_role_arn" {
  for_each = toset(var.target_repositories)

  repository    = each.key
  variable_name = "AWS_ROLE_ARN"
  value         = aws_iam_role.github_actions_role.arn
}
