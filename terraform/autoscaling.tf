# ════════════════════════════════════════════════════════════════════════════
#  ECS Application Auto Scaling
# ════════════════════════════════════════════════════════════════════════════

locals {
  scalable_services = {
    auth_service     = aws_ecs_service.auth_service.name
    business_service = aws_ecs_service.business_service.name
    review_service   = aws_ecs_service.review_service.name
    inquiry_service  = aws_ecs_service.inquiry_service.name
    gateway          = aws_ecs_service.gateway.name
    frontend         = aws_ecs_service.frontend.name
  }
}

resource "aws_appautoscaling_target" "ecs_services" {
  for_each = local.scalable_services

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${each.value}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.ecs_min_capacity
  max_capacity       = var.ecs_max_capacity
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  for_each = local.scalable_services

  name               = "${var.project}-${each.key}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.ecs_cpu_target
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "ecs_memory" {
  for_each = local.scalable_services

  name               = "${var.project}-${each.key}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_services[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_services[each.key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_services[each.key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 80
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}
