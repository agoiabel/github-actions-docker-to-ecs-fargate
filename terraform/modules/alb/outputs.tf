output "alb_dns_name" {
  description = "Public DNS name of the ALB — use this to test the application"
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "ARN of the target group — passed to the ECS service load_balancer block"
  value       = aws_lb_target_group.this.arn
}

output "security_group_id" {
  description = "ID of the ALB security group — ECS task security group allows inbound from this"
  value       = aws_security_group.alb.id
}