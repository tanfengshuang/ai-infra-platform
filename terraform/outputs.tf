# ========================================================
# outputs.tf — EKS 集群输出（供 terraform-agent 引用）
# ========================================================
output "vpc_id" {
  description = "EKS VPC ID"
  value       = aws_vpc.eks_vpc.id
}

output "private_subnet_ids" {
  description = "EKS 节点子网 ID 列表"
  value       = [aws_subnet.pub_sub_1.id, aws_subnet.pub_sub_2.id]
}

output "eks_cluster_name" {
  description = "EKS 集群名称"
  value       = aws_eks_cluster.my_cluster.name
}

output "eks_cluster_endpoint" {
  description = "EKS 集群 API 端点"
  value       = aws_eks_cluster.my_cluster.endpoint
}

output "eks_node_security_group_id" {
  description = "EKS 集群安全组 ID（用于 Redis 白名单）"
  value       = aws_eks_cluster.my_cluster.vpc_config[0].cluster_security_group_id
}

output "private_zone_id" {
  description = "Route 53 私有托管区 ID"
  value       = aws_route53_zone.private_zone.zone_id
}

output "private_zone_name" {
  description = "Route 53 私有托管区域名"
  value       = aws_route53_zone.private_zone.name
}
