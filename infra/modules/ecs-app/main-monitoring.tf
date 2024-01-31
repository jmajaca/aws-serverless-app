resource "aws_sns_topic" "app_alarms" {
  name              = "${var.application_name}-alarms"
  kms_master_key_id = var.aws_kms_key_id
}

resource "aws_sns_topic_subscription" "ecs_usage_target" {
  for_each  = toset(var.alarm_emails)
  topic_arn = aws_sns_topic.app_alarms.arn
  protocol  = "email"
  endpoint  = each.key
}

resource "aws_cloudwatch_metric_alarm" "resource_alarm" {
  for_each = toset(["CPU", "Memory"])

  alarm_name          = "${aws_ecs_service.service.name}-${each.value}"
  alarm_description   = "Watch for ${each.value} usage"
  alarm_actions       = [aws_sns_topic.app_alarms.arn]
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  period              = 180
  metric_name         = "${each.value}Utilization"
  namespace           = "AWS/ECS"
  statistic           = "Average"
  threshold           = 80
  dimensions = {
    "ClusterName" = var.ecs_cluster.name
    "ServiceName" = aws_ecs_service.service.name
  }
}

resource "aws_cloudwatch_metric_alarm" "status_alarm" {
  alarm_name          = "${var.application_name}-5xx"
  alarm_description   = "Watch for application 5xx errors"
  alarm_actions       = [aws_sns_topic.app_alarms.arn]
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  period              = 180
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Sum"
  threshold           = 10
  dimensions = {
    "TargetGroup"  = aws_alb_target_group.alb_target_group.arn_suffix
    "LoadBalancer" = aws_alb.alb.arn_suffix
  }
}