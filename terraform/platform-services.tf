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

# 2. ALB Controller IAM 角色（通过 IRSA 绑定）
data "aws_iam_policy_document" "alb_controller_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
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

# 3. Helm 安装 ALB Controller
resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.my_cluster.name
  }
  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }

  depends_on = [aws_eks_cluster.my_cluster]
}

# 4. ExternalDNS IAM 角色
data "aws_iam_policy_document" "external_dns_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
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

# 5. Helm 安装 ExternalDNS
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"

  set {
    name  = "provider"
    value = "aws"
  }
  set {
    name  = "aws.zoneType"
    value = "private"
  }
  set {
    name  = "txtOwnerId"
    value = "aiops-local"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns.arn
  }

  depends_on = [aws_eks_cluster.my_cluster]
}
