resource "aws_kms_key" "default" {
  description         = "default-key"
  enable_key_rotation = true
}

#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "demo-api"
  retention_in_days = 1
}

resource "aws_ecr_repository" "ecr_repository" {
  name = "demo-api"

  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  #encryption_configuration {
  #  encryption_type = "KMS"
  #  kms_key = aws_kms_key.default.key_id
  #}
}

resource "aws_ecs_cluster" "cluster" {
  name = "ecs-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "task_definition" {
  family                   = "demo-api"
  network_mode             = "awsvpc" # Use awsvpc for Fargate launch type
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "demo-api"
      image = "${aws_ecr_repository.ecr_repository.repository_url}:latest"
      portMappings = [
        {
          containerPort = 80,
          hostPort      = 80,
        },
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group" : aws_cloudwatch_log_group.cloudwatch_log_group.name,
          "awslogs-region" : "eu-central-1", # TODO
          "awslogs-stream-prefix" : "ecs",
        }
      }
      healthCheck = {
        retries = 3
        # command = ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
        command     = ["CMD-SHELL", "echo health"]
        timeout     = 2
        interval    = 10
        startPeriod = 10
      }
    },
  ])
}

resource "aws_ecs_service" "service" {
  name                              = "demo-api"
  cluster                           = aws_ecs_cluster.cluster.id
  task_definition                   = aws_ecs_task_definition.task_definition.arn
  launch_type                       = "FARGATE" # Use FARGATE for serverless deployment
  health_check_grace_period_seconds = 10

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.service_sg.id]

    # this is tmp when using default subnets (which are public)
    # https://stackoverflow.com/a/77706446
    # assign_public_ip = true
  }

  load_balancer {
    container_name   = "demo-api"
    container_port   = 80
    target_group_arn = aws_alb_target_group.alb_target_group.arn
  }
  desired_count = 1

  lifecycle {
    ignore_changes = [desired_count]
  }
}

#tfsec:ignore:aws-elb-alb-not-public
resource "aws_alb" "alb" {
  name                       = "my-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = module.vpc.public_subnets
  drop_invalid_header_fields = true
}

resource "aws_alb_listener" "http_listener" {
  load_balancer_arn = aws_alb.alb.arn
  port              = 80
  protocol          = "HTTP" #tfsec:ignore:aws-elb-http-not-used

  # can't use HTTPS because of no cert
  # default_action {
  #   type = "redirect"
  #   redirect {
  #     port        = "443"
  #     protocol    = "HTTPS"
  #     status_code = "HTTP_301"
  #   }
  # }
  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.alb_target_group.arn
  }
}

resource "aws_alb_listener" "https_listener" {
  load_balancer_arn = aws_alb.alb.arn
  port              = 443
  # can't use HTTPS because of no cert
  protocol = "HTTP" #tfsec:ignore:aws-elb-http-not-used

  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.alb_target_group.arn
  }
}

resource "aws_alb_target_group" "alb_target_group" {
  name        = "demo-api"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 6
    port                = "traffic-port"
    protocol            = "HTTP"
    path                = "/health"
    matcher             = "200"
  }

  vpc_id = module.vpc.vpc_id
}

resource "aws_sns_topic" "ecs_usage" {
  name              = "ecs-usage"
  kms_master_key_id = aws_kms_key.default.key_id
}

resource "aws_sns_topic_subscription" "ecs_usage_target" {
  topic_arn = aws_sns_topic.ecs_usage.arn
  protocol  = "email"
  endpoint  = "foodie.casinos-0a@icloud.com"
}

resource "aws_cloudwatch_metric_alarm" "cloudwatch_metric_alarm" {
  for_each = toset(["CPU", "Memory"])

  alarm_name          = "${aws_ecs_service.service.name}-${each.value}"
  alarm_description   = "Watch for ${each.value} usage"
  alarm_actions       = [aws_sns_topic.ecs_usage.arn]
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  period              = 180
  metric_name         = "${each.value}Utilization"
  namespace           = "AWS/ECS"
  statistic           = "Average"
  threshold           = 80
  dimensions = {
    "ClusterName" = aws_ecs_cluster.cluster.name
    "ServiceName" = aws_ecs_service.service.name
  }
}

# TODO this has mock values for testing
resource "aws_cloudwatch_metric_alarm" "cloudwatch_metric_alarm_alb" {
  alarm_name          = "alb 5xx"
  alarm_description   = "5xx"
  alarm_actions       = [aws_sns_topic.ecs_usage.arn] # TODO
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  period              = 180
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  statistic           = "Sum"
  threshold           = 2
  dimensions = {
    "TargetGroup"  = aws_alb_target_group.alb_target_group.arn_suffix
    "LoadBalancer" = aws_alb.alb.arn_suffix
  }
}

resource "aws_appautoscaling_target" "autoscaling_target" {
  max_capacity       = 3
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "autoscaling_policy_cpu" {
  for_each = toset(["ECSServiceAverageCPUUtilization", "ECSServiceAverageMemoryUtilization"])

  name               = each.key
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.autoscaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.autoscaling_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.autoscaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 80
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
    predefined_metric_specification {
      predefined_metric_type = each.key
    }
  }
}

# TODO list
# - logs +
# - alarms +
# - private vpc +
# - autoscaling +
# - 5xx alarms +