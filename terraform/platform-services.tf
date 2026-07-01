# ============================================================
# platform-services.tf — Route 53 + ALB Controller + ExternalDNS
# ============================================================

# 1. Route 53 私有托管区
resource "aws_route53_zone" "private_zone" {
  name = "aiops.local"

  vpc {
    vpc_id = aws_vpc.eks_vpc.id
  }

  comment = "EKS 内部工具链及业务 API 统一私有托管区"
  tags = merge(var.tags, { Name = "aiops-private-zone" })
}

# 1.5 EKS OIDC 身份提供商（供 ALB Controller 和 ExternalDNS 的 IRSA 使用）
data "tls_certificate" "eks" {
  url = aws_eks_cluster.my_cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.my_cluster.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
}


# 2. ALB Controller IAM 角色（通过 IRSA 绑定）
data "aws_iam_policy_document" "alb_controller_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.amazonaws.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.amazonaws.com:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "eks-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSLoadBalancingPolicy"
}

resource "aws_iam_role_policy_attachment" "alb_controller_ec2" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# 3. ALB Controller 已改为手动 helm install（不再由 Terraform 管理）
# 因为国内网络环境下 helm_release 容易超时且 state 管理不幂等
# 手动安装命令（必须带上 aws.vpcId，否则 Pod 会 CrashLoopBackOff）：
#   helm upgrade --install aws-load-balancer-controller /tmp/helm-charts/aws-load-balancer-controller-1.7.2.tgz \
#     -n kube-system \
#     --set clusterName=core-platform-cluster \
#     --set aws.vpcId=vpc-xxxxxxxx \
#     --set serviceAccount.create=true \
#     --set serviceAccount.name=aws-load-balancer-controller \
#     --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::879866609414:role/eks-alb-controller
#
# 或者直接运行: bash ../scripts/install-addons.sh

# 4. ExternalDNS IAM 角色
data "aws_iam_policy_document" "external_dns_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.amazonaws.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "oidc.eks.amazonaws.com:sub"
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "eks-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "external_dns_policy" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
      "route53:ListHostedZones",
    ]
    effect    = "Allow"
    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  name   = "eks-external-dns-policy"
  policy = data.aws_iam_policy_document.external_dns_policy.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

# 5. ExternalDNS 已改为手动 helm install（不再由 Terraform 管理）
# 手动安装命令（使用 registry.k8s.io 镜像避免 Docker Hub 限速）：
#   helm upgrade --install external-dns /tmp/helm-charts/external-dns-9.0.3.tgz \
#     -n kube-system \
#     --set provider=aws \
#     --set aws.zoneType=private \
#     --set txtOwnerId=aiops-local \
#     --set image.repository=registry.k8s.io/external-dns/external-dns \
#     --set image.tag=v0.14.0 \
#     --set global.security.allowInsecureImages=true \
#     --set policy=sync \
#     --set registry=txt \
#     --set serviceAccount.create=true \
#     --set serviceAccount.name=external-dns \
#     --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::879866609414:role/eks-external-dns
#
# 安装完成后必须修复 automountServiceAccountToken：
#   kubectl patch serviceaccount external-dns -n kube-system -p '{"automountServiceAccountToken": true}'
# 否则 IRSA 无法注入 AWS 凭证，Pod 会 crash（context deadline exceeded）
