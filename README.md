# ai-infra-platform — 公共基础设施底座

管理 AI Agent 平台的 AWS 底层基础设施 — EKS 集群、VPC、IAM OIDC、共享 Namespace。

## 目录结构

```
ai-infra-platform/
├── terraform/                  # 核心基础设施即代码
│   ├── main.tf                 # VPC + EKS 集群 + 节点组
│   ├── providers.tf            # AWS + GitHub Provider
│   ├── variables.tf            # 输入变量
│   ├── outputs.tf              # 输出供下游使用
│   ├── iam-oidc.tf             # GitHub Actions OIDC + 角色 + ARN 注入
│   ├── kubernetes.tf           # EKS 共享 Namespace
│   └── s3.tf                   # Terraform State bucket
├── scripts/
│   └── apply.sh                # 一键部署脚本
├── .github/workflows/
│   └── terraform-apply.yml     # CI/CD 自动部署
├── .gitignore
└── README.md
```

## 使用前提

- AWS CLI 已安装并配置
- Terraform >= 1.5
- 拥有 AWS AdministratorAccess 权限

## 快速部署

```bash
# 1. 自举 S3 bucket 存储 state
cd terraform
terraform init
terraform apply -auto-approve

# 2. 构建完整基础设施（需要 GitHub Token 注入 OIDC）
terraform apply \
  -var="github_token=ghp_your_github_pat" \
  -auto-approve
```

## 输出

部署成功后，通过 `terraform output` 可获取：
- `eks_cluster_name` — EKS 集群名
- `vpc_id` — VPC ID
- `eks_node_security_group_id` — 节点安全组 ID

两个业务仓库（`log-analyze-agent`、`platform-shared-services`）的 `AWS_ROLE_ARN` 变量会被自动注入。
