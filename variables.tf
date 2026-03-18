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

variable "nxb_server_ami" {
  description = "The AMI to use for the nxb-server instance"
  type        = string
  default     = "server_x86_64"
}

data "http" "amis" {
  url = "https://catalog.nixbuild.net/aws/amis.json"
}

locals {
  all_amis = jsondecode(data.http.amis.response_body)

  ami_queries = {
    server_x86_64    = { product = "nxb-server-ec2", system = "x86_64-linux" }
    server_aarch64   = { product = "nxb-server-ec2", system = "aarch64-linux" }
    builder_x86_64   = { product = "nxb-builder-ec2", system = "x86_64-linux" }
    builder_aarch64  = { product = "nxb-builder-ec2", system = "aarch64-linux" }
  }

  ami_candidates = {
    for name, query in local.ami_queries : name => [
      for ami in local.all_amis : ami if
        ami.region == var.region &&
        ami.image_info.product == query.product &&
        ami.image_info.version == var.nxb_version &&
        ami.image_info.system == query.system
    ]
  }

  amis = {
    for name, candidates in local.ami_candidates : name =>
      length(candidates) == 0 ? null : one([
        for ami in candidates : ami if
          ami.registration_time == reverse(sort(candidates[*].registration_time))[0]
      ])
  }
}
