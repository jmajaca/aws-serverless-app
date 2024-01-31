output "application_hostname" {
  description = "Application hostname"
  value       = module.ecs-app.alb_dns
}