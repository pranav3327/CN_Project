output "nodes" {
  value = {
    for n, d in data.aws_instance.node : n => {
      private_ip = d.private_ip
      public_ip  = d.public_ip
      state      = d.instance_state
    }
  }
}

output "ssh_allowed_from" {
  value = local.ssh_cidr
}
