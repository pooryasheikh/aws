terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

resource "aws_launch_template" "backend" {
  image_id        = "ami-088d8c40e0ec18c88"
  instance_type   = var.instance_type
  vpc_security_group_ids = [aws_security_group.instance.id]
  user_data       = "${base64encode(templatefile("${path.module}/user-data.sh", {}))}"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }
}

resource "aws_autoscaling_group" "backend_1" {
  vpc_zone_identifier  = data.aws_subnets.default.ids
  target_group_arns    = [aws_lb_target_group.backend_1.arn]
  health_check_type    = "ELB"

  min_size = var.min_size
  max_size = var.max_size

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "backend-1"
    propagate_at_launch = true
  }

  tag {
    key                 = "Backend"
    value               = "1"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = {
      for key, value in var.custom_tags:
      key => upper(value)
      if key != "Name"
    }

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_autoscaling_group" "backend_2" {
  vpc_zone_identifier  = data.aws_subnets.default.ids
  target_group_arns    = [aws_lb_target_group.backend_2.arn]
  health_check_type    = "ELB"

  min_size = var.min_size
  max_size = var.max_size

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "backend-2"
    propagate_at_launch = true
  }

  tag {
    key                 = "Backend"
    value               = "2"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = {
      for key, value in var.custom_tags:
      key => upper(value)
      if key != "Name"
    }

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}


resource "aws_autoscaling_schedule" "backend_1_scale_out_during_business_hours" {
  count = var.enable_autoscaling ? 1 : 0

  scheduled_action_name  = "backend-1-scale-out-during-business-hours"
  min_size               = 2
  max_size               = 10
  desired_capacity       = 10
  recurrence             = "0 9 * * *"
  autoscaling_group_name = aws_autoscaling_group.backend_1.name
}

resource "aws_autoscaling_schedule" "backend_1_scale_in_at_night" {
  count = var.enable_autoscaling ? 1 : 0

  scheduled_action_name  = "backend-1-scale-in-at-night"
  min_size               = 2
  max_size               = 10
  desired_capacity       = 2
  recurrence             = "0 17 * * *"
  autoscaling_group_name = aws_autoscaling_group.backend_1.name
}

resource "aws_autoscaling_schedule" "backend_2_scale_out_during_business_hours" {
  count = var.enable_autoscaling ? 1 : 0

  scheduled_action_name  = "backend-2-scale-out-during-business-hours"
  min_size               = 2
  max_size               = 10
  desired_capacity       = 10
  recurrence             = "0 9 * * *"
  autoscaling_group_name = aws_autoscaling_group.backend_1.name
}

resource "aws_autoscaling_schedule" "backend_2_scale_in_at_night" {
  count = var.enable_autoscaling ? 1 : 0

  scheduled_action_name  = "backend-2-scale-in-at-night"
  min_size               = 2
  max_size               = 10
  desired_capacity       = 2
  recurrence             = "0 17 * * *"
  autoscaling_group_name = aws_autoscaling_group.backend_1.name
}
resource "aws_security_group" "instance" {
  name = "${var.cluster_name}-instance"
}

resource "aws_security_group_rule" "allow_server_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.instance.id

  from_port   = var.server_port
  to_port     = var.server_port
  protocol    = local.tcp_protocol
  cidr_blocks = local.all_ips
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_lb" "alb" {
  name               = var.cluster_name
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default.ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.alb.arn
  port              = local.http_port
  protocol          = "HTTP"

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/html"
      message_body = templatefile("${path.module}/message-body.html", {})
      status_code  = 200
    }
  }
}

resource "aws_lb_target_group" "backend_1" {
  name     = "backend-1"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/page1.html"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "backend_2" {
  name     = "backend-2"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/page2.html"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "backend_1" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/page1.html"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_1.arn
  }
}

resource "aws_lb_listener_rule" "backend_2" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 99

  condition {
    path_pattern {
      values = ["/page2.html"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_2.arn
  }
}

resource "aws_security_group" "alb" {
  name = "${var.cluster_name}-alb"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.http_port
  to_port     = local.http_port
  protocol    = local.tcp_protocol
  cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id

  from_port   = local.any_port
  to_port     = local.any_port
  protocol    = local.any_protocol
  cidr_blocks = local.all_ips
}

locals {
  http_port    = 80
  any_port     = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips      = ["0.0.0.0/0"]
}
