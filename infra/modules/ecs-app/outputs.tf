output "alb_dns" {
  description = "DNS of the ALB"
  value       = aws_alb.alb.dns_name
}