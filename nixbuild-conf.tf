# The nixbuild.net configuration, deployed as JSON to
# /etc/nixbuild.net/conf.d/nixbuild.conf (see cloud-init.tf)

locals {
  nixbuild_conf = jsonencode({
    slurmctld = {
      host = var.nxb_server_hostname
      ip   = local.nxb_server_ip
    }

    nard = {
      s3 = {
        allow-ambient-credentials = true
      }
      push = {
        s3 = {
          concurrency         = 6
          max-concurrent-nars = 6
        }
      }
    }

    nixbuild = {
      # These are put in place by our 'init.sh' script (see cloud-init.tf)
      biscuit-private-key-file = "/etc/nixbuild.net/biscuit-key"
      ssh-host-key-file        = "/etc/nixbuild.net/ssh-host-key"

      debug-logs           = true
      require-state-volume = true

      # Matches the EBS configured in main.tf
      state-volume-device  = "/dev/sdb"

      predefined-accounts = []
    }

    ec2 = {
      build-node-templates = [
        # 16 x86_64-linux builder instances
        {
          ami            = local.amis["builder_x86_64"].ami_id
          region         = var.region
          security-group = aws_security_group.private.id
          subnet         = aws_subnet.private.id
          public-ip      = false
          instance-type  = "c5a.4xlarge" # 16 vCPUs / 32 GiB
          count          = 16
          weight         = 0
        },
        # 16 aarch64-linux builder instances
        {
          ami            = local.amis["builder_aarch64"].ami_id
          region         = var.region
          security-group = aws_security_group.private.id
          subnet         = aws_subnet.private.id
          public-ip      = false
          instance-type  = "c6g.4xlarge" # 16 vCPUs / 32 GiB
          count          = 16
          weight         = 0
        },
      ]
    }
  })
}
