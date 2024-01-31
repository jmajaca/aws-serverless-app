#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "/ecs/${var.application_name}"
  retention_in_days = 1
}

resource "aws_ecr_repository" "ecr_repository" {
  name = var.application_name

  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # this is for easy destruction while testing

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.aws_kms_key_id
  }
}

resource "aws_ecs_task_definition" "task_definition" {
  family                   = var.application_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = var.ecs_execution_role_arn
  task_role_arn      = var.ecs_execution_role_arn

  container_definitions = jsonencode([
    {
      name  = var.application_name
      image = "${aws_ecr_repository.ecr_repository.repository_url}:${var.application_version}"
      portMappings = [
        {
          containerPort = var.application_port,
          hostPort      = 80,
        },
      ],
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group" : aws_cloudwatch_log_group.cloudwatch_log_group.name,
          "awslogs-region" : data.aws_region.current.name
          "awslogs-stream-prefix" : "ecs",
        }
      }
      healthCheck = {
        retries = 3
        # TODO
        # command = ["CMD-SHELL", "curl -f http://localhost:${var.application_port}/${var.application_health_check_path} || exit 1"]
        command     = ["CMD-SHELL", "echo health"]
        timeout     = 2
        interval    = 10
        startPeriod = 10
      }
    },
  ])
}

resource "aws_ecs_service" "service" {
  name                              = var.application_name
  cluster                           = var.ecs_cluster.id
  task_definition                   = aws_ecs_task_definition.task_definition.arn
  launch_type                       = "FARGATE" # Use FARGATE for serverless deployment
  health_check_grace_period_seconds = 10

  network_configuration {
    subnets         = var.private_subnets
    security_groups = [aws_security_group.service_sg.id]
  }

  load_balancer {
    container_name   = var.application_name
    container_port   = var.application_port
    target_group_arn = aws_alb_target_group.alb_target_group.arn
  }
  desired_count = 1

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_appautoscaling_target" "autoscaling_target" {
  max_capacity       = var.max_replicas
  min_capacity       = var.min_replicas
  resource_id        = "service/${var.ecs_cluster.name}/${aws_ecs_service.service.name}"
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