variable "region" {
  description = "AWS Region"
  type        = string
}

variable "nxb_version" {
  description = "nixbuild.net Version"
  type        = string
}

variable "ssm_param_biscuit_secretkey" {
  description = "The name of the SSM parameter you've stored the NixBuild Biscuit secret key in"
  type        = string
}

variable "ssm_param_ssh_hostkey" {
  description = "The name of the SSM parameter you've stored the NixBuild SSH host key in"
  type        = string
}

variable "nxb_server_instance_type" {
  description = "The EC2 instance type to use for the nxb-server instance"
  type        = string
}

variable "nxb_server_hostname" {
  description = "The hostname to use for the nxb-server instance"
  type        = string
  default     = "nxb-server"
}

locals {
  amis = jsondecode(file("${path.module}/amis.json"))

  server_amis = [
    for ami in local.amis : ami if
      ami.image_info.product == "nxb-server-ec2" &&
      ami.image_info.version == var.nxb_version
  ]
  server_ami = length(local.server_amis) == 0 ? null : one([
    for ami in local.server_amis : ami if
      ami.registration_time == reverse(sort(local.server_amis[*].registration_time))[0]
  ])

  builder_x86_64_amis = [
    for ami in local.amis : ami if
      ami.image_info.product == "nxb-builder-ec2" &&
      ami.image_info.version == var.nxb_version &&
      ami.image_info.system == "x86_64-linux"
  ]
  builder_x86_64_ami = length(local.builder_x86_64_amis) == 0 ? null : one([
    for ami in local.builder_x86_64_amis : ami if
      ami.registration_time == reverse(sort(local.builder_x86_64_amis[*].registration_time))[0]
  ])

  builder_aarch64_amis = [
    for ami in local.amis : ami if
      ami.image_info.product == "nxb-builder-ec2" &&
      ami.image_info.version == var.nxb_version &&
      ami.image_info.system == "aarch64-linux"
  ]
  builder_aarch64_ami = length(local.builder_aarch64_amis) == 0 ? null : one([
    for ami in local.builder_aarch64_amis : ami if
      ami.registration_time == reverse(sort(local.builder_aarch64_amis[*].registration_time))[0]
  ])
}
