#!/usr/bin/env bash
# install-addons.sh — 安装 EKS 核心插件（ALB Controller + ExternalDNS）
set -euo pipefail

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

echo ">>> 更新 kubeconfig..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
kubectl cluster-info | head -1

# === 前置校验：OIDC Provider 和 IAM Role 必须存在 ===
echo ">>> 验证 OIDC Provider..."
OIDC_ISSUER_ID=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query "cluster.identity.oidc.issuer" --output text | awk -F'/' '{print $NF}')
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/${OIDC_ISSUER_ID}"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" &>/dev/null; then
  echo "    ✅ OIDC Provider 存在"
else
  echo "    ❌ OIDC Provider 不存在！请先运行 terraform apply"
  exit 1
fi

echo ">>> 验证 IAM Role..."
for ROLE in eks-alb-controller eks-external-dns; do
  if aws iam get-role --role-name "$ROLE" &>/dev/null; then
    echo "    ✅ IAM Role $ROLE 存在"
  else
    echo "    ❌ IAM Role $ROLE 不存在！请先运行 terraform apply"
    exit 1
  fi
done

# === 安装 ALB Controller ===
echo ""
echo "============================================"
echo " 安装 ALB Load Balancer Controller"
echo "============================================"
# 先完全卸载（清理旧的 SA 和 token）
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
kubectl delete sa aws-load-balancer-controller -n kube-system 2>/dev/null || true

helm upgrade --install aws-load-balancer-controller \
  "$CHARTS_DIR/aws-load-balancer-controller-1.7.2.tgz" \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::${ACCOUNT_ID}:role/eks-alb-controller

echo ">>> 等待 ALB Controller Pod 就绪..."
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=aws-load-balancer-controller \
  --timeout=180s

echo "    ✅ ALB Controller 安装完成"

# === 安装 ExternalDNS ===
echo ""
echo "============================================"
echo " 安装 ExternalDNS"
echo "============================================"
# 先完全卸载
helm uninstall external-dns -n kube-system 2>/dev/null || true
kubectl delete sa external-dns -n kube-system 2>/dev/null || true

helm upgrade --install external-dns \
  "$CHARTS_DIR/external-dns-9.0.3.tgz" \
  -n kube-system \
  --set provider=aws \
  --set aws.zoneType=private \
  --set txtOwnerId=aiops-local \
  --set global.security.allowInsecureImages=true \
  --set policy=sync \
  --set registry=txt \
  --set serviceAccount.create=true \
  --set serviceAccount.name=external-dns \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::${ACCOUNT_ID}:role/eks-external-dns

# 修正镜像路径（避免 helm 自动加 docker.io/ 前缀）
kubectl patch deployment external-dns -n kube-system \
  -p '{"spec":{"template":{"spec":{"containers":[{"name":"external-dns","image":"registry.k8s.io/external-dns/external-dns:v0.14.0"}]}}}}' 2>/dev/null || true

# 修复 IRSA（automountServiceAccountToken）
kubectl patch serviceaccount external-dns -n kube-system \
  -p '{"automountServiceAccountToken": true}' 2>/dev/null || true

echo ">>> 等待 ExternalDNS Pod 就绪..."
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=external-dns \
  --timeout=180s 2>/dev/null || sleep 60

echo "    ✅ ExternalDNS 安装完成"

# === 最终验证 ===
echo ""
echo "============================================"
echo " 验证"
echo "============================================"
kubectl get pods -n kube-system | grep -E "alb|external-dns"
