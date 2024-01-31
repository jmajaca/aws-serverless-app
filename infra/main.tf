resource "aws_kms_key" "default" {
  description         = "default-key"
  enable_key_rotation = true
}

resource "aws_ecs_cluster" "cluster" {
  name = "ecs-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

module "ecs-app" {
  source = "./modules/ecs-app"

  application_name              = "demo-api"
  application_version           = "latest"
  application_port              = 80
  application_health_check_path = "/health"

  min_replicas = 1
  max_replicas = 3

  ecs_cluster            = aws_ecs_cluster.cluster
  aws_kms_key_id         = aws_kms_key.default.key_id
  ecs_execution_role_arn = aws_iam_role.ecs_execution_role.arn

  vpc_id          = module.vpc.vpc_id
  public_subnets  = module.vpc.public_subnets
  private_subnets = module.vpc.private_subnets

  alarm_emails = ["foodie.casinos-0a@icloud.com"]
}