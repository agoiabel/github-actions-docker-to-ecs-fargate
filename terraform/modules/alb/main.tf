# alb/main.tf
#
# Creates:
#   - Security group: allows HTTP/80 inbound from the internet, all outbound
#   - Application Load Balancer: internet-facing, spans public subnets
#   - Target group: IP-based (required for Fargate), with health check config
#   - HTTP listener: forwards all traffic to the target group
#
# The target group uses target_type = "ip" because Fargate tasks are
# registered by their private IP address, not by EC2 instance ID.

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Allow HTTP inbound from the internet to the ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound must be open so the ALB can reach ECS tasks on their container port
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = false          # internet-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # Protect against accidental deletion — remove this if you want
  # terraform destroy to succeed without manual intervention
  # enable_deletion_protection = true

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  name        = "${var.name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"   # Fargate requires ip target type
  
  health_check {
    path    = var.health_check_path
    protocol = "HTTP"
    matcher  = "200"

    # Poll every 30 seconds
    interval = 30

    # A single poll must respond within 5 seconds
    timeout = 5

    # Two consecutive 200 responses = healthy, task starts receiving traffic
    healthy_threshold = 2

    # Three consecutive failures = unhealthy, task stops receiving traffic
    unhealthy_threshold = 3
  }

  # How long the ALB waits for in-flight requests before removing an old task.
  # Comes from local.current.deregistration_delay in locals.tf.
  deregistration_delay = var.deregistration_delay

  tags = var.tags

  # Target groups cannot be updated in-place when certain attributes change.
  # Create the new one before destroying the old one to avoid downtime.
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}