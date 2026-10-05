# ─────────────────────────────────────────────────────────────────────
#  The "private LAN": one VPC, one subnet, four machines with fixed IPs.
#  Terraform builds the machines; `make converge` configures the services.
# ─────────────────────────────────────────────────────────────────────

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

data "http" "my_ip" {
  count = var.ssh_cidr == "" ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

data "aws_vpc" "default" {
  count   = var.vpc_mode == "default" ? 1 : 0
  default = true
}

locals {
  own_vpc      = var.vpc_mode == "new"
  vpc_id       = local.own_vpc ? aws_vpc.lan[0].id : data.aws_vpc.default[0].id
  subnet_cidr  = local.own_vpc ? var.subnet_cidr : var.default_vpc_subnet_cidr
  node_ip      = { for n, v in var.nodes : n => cidrhost(local.subnet_cidr, v.host) }
  ssh_cidr     = var.ssh_cidr != "" ? var.ssh_cidr : "${chomp(data.http.my_ip[0].response_body)}/32"
  generate_key = var.key_name == ""
  key_name     = local.generate_key ? aws_key_pair.cn[0].key_name : var.key_name
  key_file     = local.generate_key ? abspath("${path.module}/../.generated/cn-key.pem") : pathexpand(var.key_path)
  gen_dir      = abspath("${path.module}/../.generated")
}

# ---- network ------------------------------------------------------------

# vpc_mode = new: our own VPC + internet gateway + routes.
# vpc_mode = default: only a new subnet inside the default VPC (which already has them).
resource "aws_vpc" "lan" {
  count                = local.own_vpc ? 1 : 0
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # provides the VPC resolver 169.254.169.253
  enable_dns_hostnames = true
  tags                 = { Name = "cn-lan" }
}

resource "aws_internet_gateway" "igw" {
  count  = local.own_vpc ? 1 : 0
  vpc_id = aws_vpc.lan[0].id
  tags   = { Name = "cn-igw" }
}

resource "aws_subnet" "lan" {
  vpc_id                  = local.vpc_id
  cidr_block              = local.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "cn-lan-subnet" }
}

resource "aws_route_table" "lan" {
  count  = local.own_vpc ? 1 : 0
  vpc_id = aws_vpc.lan[0].id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }
  tags = { Name = "cn-lan-routes" }
}

resource "aws_route_table_association" "lan" {
  count          = local.own_vpc ? 1 : 0
  subnet_id      = aws_subnet.lan.id
  route_table_id = aws_route_table.lan[0].id
}

# Security group = the Wi-Fi: members talk freely to each other; only SSH from you.
resource "aws_security_group" "lan" {
  name        = "cn-lan"
  description = "CN project private LAN"
  vpc_id      = local.vpc_id
  tags        = { Name = "cn-lan" }
}

resource "aws_vpc_security_group_ingress_rule" "lan_internal" {
  security_group_id            = aws_security_group.lan.id
  referenced_security_group_id = aws_security_group.lan.id
  ip_protocol                  = "-1"
  description                  = "all traffic between the four machines"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.lan.id
  cidr_ipv4         = local.ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "SSH from the operator"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.lan.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---- SSH key (generated unless an existing key such as vockey is given) --

resource "tls_private_key" "cn" {
  count     = local.generate_key ? 1 : 0
  algorithm = "ED25519"
}

resource "aws_key_pair" "cn" {
  count      = local.generate_key ? 1 : 0
  key_name   = "cn-${var.team}-key"
  public_key = tls_private_key.cn[0].public_key_openssh
}

resource "local_sensitive_file" "key" {
  count           = local.generate_key ? 1 : 0
  content         = tls_private_key.cn[0].private_key_openssh
  filename        = local.key_file
  file_permission = "0600"
}

# ---- the four machines ----------------------------------------------------

resource "aws_instance" "node" {
  for_each = var.nodes

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.lan.id
  private_ip             = local.node_ip[each.key]
  vpc_security_group_ids = [aws_security_group.lan.id]
  key_name               = local.key_name

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname = each.key
    role     = each.value.role
    ip       = local.node_ip[each.key]
    packages = each.value.packages
  })

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = { Name = each.key, Role = each.value.role }

  # Never replace a machine just because Ubuntu published a newer AMI or the
  # boot script was edited – services are managed by `make converge`.
  lifecycle {
    ignore_changes = [ami, user_data]
  }

  depends_on = [aws_route_table_association.lan]
}

# `make stop` / `make start` (and restarting after an AWS Academy session ends)
resource "aws_ec2_instance_state" "node" {
  for_each    = aws_instance.node
  instance_id = each.value.id
  state       = var.instance_state
}

# Read the instances again AFTER the state change so public IPs are current
data "aws_instance" "node" {
  for_each    = aws_instance.node
  instance_id = each.value.id
  depends_on  = [aws_ec2_instance_state.node]
}

# ---- files used by the Makefile scripts ----------------------------------

resource "local_file" "cluster_env" {
  filename        = "${local.gen_dir}/cluster.env"
  file_permission = "0644"
  content = join("\n", concat(
    ["# Generated by Terraform – do not edit"],
    ["SUBNET_CIDR=${local.subnet_cidr}"],
    [for n, ip in local.node_ip : "${upper(replace(n, "-", ""))}_IP=${ip}"],
    [for n, d in data.aws_instance.node : "${upper(replace(n, "-", ""))}_PUB=${d.public_ip}"],
    ["SSH_KEY_FILE=\"${local.key_file}\"", ""]
  ))
}

resource "local_file" "ssh_config" {
  filename        = "${local.gen_dir}/ssh_config"
  file_permission = "0644"
  content = join("\n", [for n, d in data.aws_instance.node : <<-EOT
    Host ${n}
      HostName ${d.public_ip}
      User ubuntu
      IdentityFile "${local.key_file}"
      IdentitiesOnly yes
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      LogLevel ERROR
      ServerAliveInterval 20
      ConnectTimeout 8
      ControlMaster auto
      ControlPath /tmp/cn-ssh-%C
      ControlPersist 15m
    EOT
  ])
}
