# ============================================================
# kubernetes.tf — EKS 连接配置 + 共享 Namespace
# ============================================================


provider "kubernetes" {
  host                   = aws_eks_cluster.my_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.my_cluster.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.my_cluster.name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.my_cluster.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.my_cluster.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.my_cluster.name, "--region", var.aws_region]
    }
  }
}

resource "kubernetes_namespace_v1" "ns_ai_ops" {
  metadata {
    name = "ns-ai-ops"
    labels = {
      environment = "production"
      managed-by  = "terraform"
    }
  }
}

resource "kubernetes_namespace_v1" "ns_monitoring" {
  metadata {
    name = "ns-monitoring"
    labels = {
      environment = "production"
      managed-by  = "terraform"
    }
  }
}

resource "kubernetes_namespace_v1" "ns_devops" {
  metadata {
    name = "ns-devops"
    labels = {
      environment = "production"
      managed-by  = "terraform"
    }
  }
}
