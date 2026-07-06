output "ecs_execution_role_arn" {
  value = aws_iam_role.ecs_execution.arn
}

output "ecs_execution_role_name" {
  value = aws_iam_role.ecs_execution.name
}

output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task.arn
}

output "eks_cluster_role_arn" {
  # The eks module depends on this ARN; because Terraform tracks it through
  # the policy attachment, the cluster role won't be passed until all
  # attachments in this module complete.
  value      = aws_iam_role.eks_cluster.arn
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

output "eks_nodes_role_arn" {
  value = aws_iam_role.eks_nodes.arn
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr_readonly,
    aws_iam_role_policy_attachment.eks_ebs_csi,
  ]
}

output "eks_nodes_role_name" {
  value = aws_iam_role.eks_nodes.name
}
