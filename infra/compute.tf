data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  app_servers = {
    "web-01" = { group = "a", subnet = "a" }
    "web-02" = { group = "a", subnet = "a" }
    "web-03" = { group = "b", subnet = "b" }
    "web-04" = { group = "b", subnet = "b" }
  }
}

resource "aws_instance" "app" {
  for_each = local.app_servers

  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[each.value.subnet].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y java-17-amazon-corretto-headless jq
    useradd --system --no-create-home --shell /sbin/nologin appuser
    mkdir -p /opt/${var.project}
    chown appuser:appuser /opt/${var.project}
  EOF

  tags = {
    Name            = "${var.project}-${var.environment}-${each.key}"
    DeploymentGroup = each.value.group
    Environment     = var.environment
    Role            = "web"
  }
}