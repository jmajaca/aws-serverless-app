provider "aws" {
  region = "eu-central-1"
  profile = "personal"
}
/*
terraform {
  backend "s3" {
    bucket         = "jmajaca-tf"
    dynamodb_table = "jmajaca-tf"
    encrypt        = true
    key            = "demo-api"
    region         = "eu-central-1"
  }
}*/

resource "aws_cloudwatch_log_group" "cloudwatch_log_group" {
  name              = "demo-api"
  retention_in_days = 1
}

resource "aws_ecr_repository" "ecr_repository" {
  name = "demo-api"
}

resource "aws_ecs_cluster" "cluster" {
  name = "ecs-cluster"
}

resource "aws_ecs_task_definition" "task_definition" {
  family                   = "demo-api"
  network_mode             = "awsvpc"  # Use awsvpc for Fargate launch type
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" 
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_execution_role.arn
  task_role_arn = aws_iam_role.ecs_execution_role.arn

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
            command = ["CMD-SHELL", "echo health"]
            timeout     = 2
            interval    = 10
            startPeriod = 10
        }
    },
  ])
}

resource "aws_ecs_service" "service" {
  name            = "demo-api"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.task_definition.arn
  launch_type     = "FARGATE"  # Use FARGATE for serverless deployment

  network_configuration {
    subnets = data.aws_subnets.default.ids
    security_groups = [data.aws_security_group.default.id]

    # this is tmp when using default subnets (which are public)
    # https://stackoverflow.com/a/77706446
    assign_public_ip = true
  }

  load_balancer {
    container_name = "demo-api"
    container_port = 80
    target_group_arn = aws_alb_target_group.alb_target_group.arn
  }
  desired_count = 1

  lifecycle {
    ignore_changes = [ desired_count ]
  }
}

resource "aws_security_group" "allow_all_traffic_sg" {
    # name = "allow-all-traffic-sg"
  description = "Security group for the ALB"

  ingress {
    description      = "Allow all traffic"
    from_port        = 0
    to_port          = 443
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }

  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_alb" "alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [data.aws_security_group.default.id, aws_security_group.allow_all_traffic_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_alb_listener" "alb_listener" {
  load_balancer_arn = aws_alb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      status_code  = "200"
      message_body = "{ \"status\": \"OK\" }"
      content_type = "application/json"
    }
  }
}

resource "aws_alb_listener_rule" "alb_listener_rule" {
  listener_arn = aws_alb_listener.alb_listener.arn
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  action {
    type = "forward"
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
    matcher = "200"
  }

  vpc_id = data.aws_vpc.default.id
}

resource "aws_sns_topic" "ecs_usage" {
  name = "ecs-usage"
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

resource "aws_appautoscaling_target" "autoscaling_target" {
  max_capacity = 3
  min_capacity = 1
  resource_id = "service/${aws_ecs_cluster.cluster.name}/${aws_ecs_service.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace = "ecs"
}

resource "aws_appautoscaling_policy" "autoscaling_policy_cpu" {
  for_each = toset(["ECSServiceAverageCPUUtilization", "ECSServiceAverageMemoryUtilization"])

  name = each.key
  policy_type = "TargetTrackingScaling"
  resource_id = aws_appautoscaling_target.autoscaling_target.resource_id
  scalable_dimension = aws_appautoscaling_target.autoscaling_target.scalable_dimension
  service_namespace = aws_appautoscaling_target.autoscaling_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 80
    scale_in_cooldown = 300
    scale_out_cooldown = 300
    predefined_metric_specification {
      predefined_metric_type = each.key
    }
  }
}

# TODO list
# - logs +
# - alarms +
# - private vpc
# - autoscaling +
