#!/usr/bin/env bash
# install-addons.sh — 安装 EKS 核心插件（ALB Controller + ExternalDNS）
# 在网络受限环境下使用，先本地准备好 chart 文件
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CHARTS_DIR="${HELM_CHARTS_DIR:-/tmp/helm-charts}"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-core-platform-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
VPC_ID="${VPC_ID:-}"
ACCOUNT_ID="${AWS_ACCOUNT_ID:-879866609414}"

if [ -z "$VPC_ID" ]; then
  echo ">>> 自动获取 VPC ID..."
  VPC_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
    --query "cluster.resourcesVpcConfig.vpcId" --output text)
  echo "    VPC ID: $VPC_ID"
fi

echo ""
echo "============================================"
echo " 安装 ALB Load Balancer Controller"
echo "============================================"
helm upgrade --install aws-load-balancer-controller \
  "$CHARTS_DIR/aws-load-balancer-controller-1.7.2.tgz" \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set aws.vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::${ACCOUNT_ID}:role/eks-alb-controller

echo ""
echo "============================================"
echo " 安装 ExternalDNS"
echo "============================================"
# 注意：使用 registry.k8s.io 镜像避免 Docker Hub 限速
# automountServiceAccountToken: true 是必需的，否则 IRSA 无法注入凭证
helm upgrade --install external-dns \
  "$CHARTS_DIR/external-dns-9.0.3.tgz" \
  -n kube-system \
  --set provider=aws \
  --set aws.zoneType=private \
  --set txtOwnerId=aiops-local \
  --set image.repository=registry.k8s.io/external-dns/external-dns \
  --set image.tag=v0.14.0 \
  --set global.security.allowInsecureImages=true \
  --set policy=sync \
  --set registry=txt \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-dns \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::${ACCOUNT_ID}:role/eks-external-dns

# 修复：automountServiceAccountToken 必须为 true，否则 IRSA 不生效
kubectl patch serviceaccount external-dns -n kube-system -p '{"automountServiceAccountToken": true}' 2>/dev/null || true

echo ""
echo "============================================"
echo " 验证"
echo "============================================"
kubectl get pods -n kube-system | grep -E "alb|external-dns"
