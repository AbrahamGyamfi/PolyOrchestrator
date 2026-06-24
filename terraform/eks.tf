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
#  EKS Managed Node Group
# ════════════════════════════════════════════════════════════════════════════

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-ng-main"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id   # nodes in private subnets

  instance_types = [var.eks_node_instance_type]
  disk_size      = 30

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
  depends_on    = [aws_eks_node_group.main]
}
