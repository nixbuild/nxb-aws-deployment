locals {
  nxb_server_userdata = join("\n", ["#cloud-config", yamlencode({
    hostname = var.nxb_server_hostname

    write_files = concat(
      length(var.nxb_server_ssh_public_keys) > 0 ? [{
        path        = "/etc/ssh/authorized_keys.d/root"
        permissions = "0444"
        content     = join("\n", var.nxb_server_ssh_public_keys)
      }] : [],
      [

      ########
      # We load secrets from SSM, but these files can be deployed in any way
      # you like. Just keep in mind that the Biscuit key must be readable by
      # the 'nixbuild-secrets' group, and the SSH host key must readable by
      # the 'nixbuild-frontend' user.
      #
      # This script is executed using the 'runcmd' feature of cloud-init (see
      # below).
      {
        path        = "/etc/nixbuild.net/init.sh"
        permissions = "0755"
        content     = <<-EOT
          #!/bin/sh
          aws ssm get-parameter \
            --name "${var.ssm_param_biscuit_secretkey}" \
            --with-decryption \
            --query "Parameter.Value" \
            --output text \
            | install /dev/stdin /etc/nixbuild.net/biscuit-key \
                --mode 0440 \
                --group nixbuild-secrets

          aws ssm get-parameter \
            --name "${var.ssm_param_ssh_hostkey}" \
            --with-decryption \
            --query "Parameter.Value" \
            --output text \
            | install /dev/stdin /etc/nixbuild.net/ssh-host-key \
                --mode 0400 \
                --owner nixbuild-frontend
        EOT
      },

      ########
      # The nixbuild.net configuration (see nixbuild-conf.tf)
      {
        path        = "/etc/nixbuild.net/conf.d/nixbuild.conf"
        permissions = "0644"
        content     = local.nixbuild_conf
      },
    ])

    ########
    # Run the script that sets up secrets etc
    runcmd = ["/etc/nixbuild.net/init.sh"]
  })])
}
