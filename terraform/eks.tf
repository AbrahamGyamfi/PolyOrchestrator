# ════════════════════════════════════════════════════════════════════════════
#  EKS Cluster
# ════════════════════════════════════════════════════════════════════════════

resource "aws_eks_cluster" "main" {
  name     = "${var.project}-eks"
  version  = var.eks_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    security_group_ids      = [aws_security_group.eks_nodes.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Enable EKS control-plane logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]

  tags = { Name = "${var.project}-eks" }
}

# ════════════════════════════════════════════════════════════════════════════
#  EKS Node Launch Template (hop limit = 2 so pods can reach IMDS)
# ════════════════════════════════════════════════════════════════════════════

resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.project}-eks-node-"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project}-eks-node"
    }
  }
}

# ════════════════════════════════════════════════════════════════════════════
#  EKS Managed Node Group
# ════════════════════════════════════════════════════════════════════════════

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-ng-main"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.public[*].id   # public subnets — no NAT Gateway in this setup

  instance_types = [var.eks_node_instance_type]

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  scaling_config {
    min_size     = var.eks_node_min
    max_size     = var.eks_node_max
    desired_size = var.eks_node_desired
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
  ]

  tags = { Name = "${var.project}-node-group" }
}

# ════════════════════════════════════════════════════════════════════════════
#  EKS Addons
# ════════════════════════════════════════════════════════════════════════════

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "vpc-cni"
  depends_on    = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "coredns"
  depends_on    = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "kube-proxy"
  depends_on    = [aws_eks_node_group.main]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "aws-ebs-csi-driver"
  depends_on    = [aws_eks_node_group.main, aws_iam_role_policy_attachment.eks_ebs_csi]
}

# ════════════════════════════════════════════════════════════════════════════
#  EKS Outputs (live here so they toggle with this file)
# ════════════════════════════════════════════════════════════════════════════

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca" {
  value     = aws_eks_cluster.main.certificate_authority[0].data
  sensitive = true
}

output "eks_kubeconfig_command" {
  description = "Run this command to configure kubectl for the EKS cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}
