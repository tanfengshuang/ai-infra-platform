#!/usr/bin/env bash
# apply.sh — 一键部署基础设施
set -euo pipefail

DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
cd "$DIR"

echo "=========================================="
echo "  ai-infra-platform — 基础设施部署"
echo "=========================================="

# 检查 GitHub Token
if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "❌ 请设置 GITHUB_TOKEN 环境变量"
  echo "   export GITHUB_TOKEN=ghp_xxxx"
  exit 1
fi

terraform init -upgrade

echo ""
echo ">>> 执行 terraform apply..."
terraform apply -var="github_token=$GITHUB_TOKEN" -auto-approve

echo ""
echo ">>> 部署完成！关键输出："
terraform output
