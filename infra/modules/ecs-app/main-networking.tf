#tfsec:ignore:aws-elb-alb-not-public
resource "aws_alb" "alb" {
  name                       = var.application_name
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = var.public_subnets
  drop_invalid_header_fields = true
  # I planned on creating access logs s3 bucket but policy for it can't be dynamicly
  # created for all regions so I gave up on the idea
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
  name        = var.application_name
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
    path                = var.application_health_check_path
    matcher             = "200"
  }
  vpc_id = var.vpc_id
}

resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Security group for the ALB"
  vpc_id      = var.vpc_id
  dynamic "ingress" {
    for_each = [80, 443]
    content {
      description      = "Allow all incoming traffic to port ${ingress.value}"
      from_port        = ingress.value
      to_port          = ingress.value
      protocol         = "TCP"
      cidr_blocks      = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-ingress-sgr
      ipv6_cidr_blocks = []
    }
  }
  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-egress-sgr
    ipv6_cidr_blocks = []
  }
}

resource "aws_security_group" "service_sg" {
  name        = "service-sg"
  description = "Security group for the service"
  vpc_id      = var.vpc_id
  ingress {
    description      = "Allow incoming traffic only from the ALB"
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
    cidr_blocks      = []
    ipv6_cidr_blocks = []
    security_groups  = [aws_security_group.alb_sg.id]
  }
  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"] #tfsec:ignore:aws-ec2-no-public-egress-sgr
    ipv6_cidr_blocks = []
  }
}