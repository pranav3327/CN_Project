variable "region" {
  type    = string
  default = "us-east-1"
}

variable "team" {
  type    = string
  default = "team1"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "instance_state" {
  description = "running or stopped (make start / make stop)"
  type        = string
  default     = "running"
  validation {
    condition     = contains(["running", "stopped"], var.instance_state)
    error_message = "instance_state must be running or stopped."
  }
}

variable "key_name" {
  description = "Existing EC2 key pair (e.g. vockey). Empty = Terraform creates one."
  type        = string
  default     = ""
}

variable "key_path" {
  description = "Private key file for key_name (e.g. ~/.ssh/labsuser.pem)."
  type        = string
  default     = ""
}

variable "ssh_cidr" {
  description = "Who may SSH in. Empty = your current public IP (auto-detected)."
  type        = string
  default     = ""
}

# The private LAN. Fixed host numbers (.11-.14) so DNS records, docs and viva answers never change.
variable "vpc_mode" {
  description = "new = own VPC 10.0.0.0/16 with subnet 10.0.1.0/24; default = a subnet inside the account's default VPC (use when the VPC limit is reached)"
  type        = string
  default     = "new"
  validation {
    condition     = contains(["new", "default"], var.vpc_mode)
    error_message = "vpc_mode must be new or default."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Project subnet when vpc_mode = new"
  type        = string
  default     = "10.0.1.0/24"
}

variable "default_vpc_subnet_cidr" {
  description = "Project subnet when vpc_mode = default (must be inside 172.31.0.0/16 and unused)"
  type        = string
  default     = "172.31.250.0/24"
}

variable "nodes" {
  description = "The four machines of the brief (Mac 1..4); host = last number of the IP."
  type = map(object({
    host     = number
    role     = string
    packages = list(string)
  }))
  default = {
    "node-1" = { host = 11, role = "Mac 1: primary DNS + client", packages = ["dnsmasq"] }
    "node-2" = { host = 12, role = "Mac 2: edge (nginx, TLS, load balancer)", packages = ["nginx"] }
    "node-3" = { host = 13, role = "Mac 3: Backend A (+ backup DNS, standby edge)", packages = ["dnsmasq", "nginx"] }
    "node-4" = { host = 14, role = "Mac 4: Backend B + client", packages = [] }
  }
}
