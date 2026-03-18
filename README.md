# nixbuild.net AWS Deployment

This directory defines a simple Terraform deployment of nixbuild.net, that you
can use directly or as a base for a more refined deployment.


## Repository Overview

[variables.tf](./variables.tf) defines all available Terraform variables along
with the AMI lookup logic.

[main.tf](./main.tf) defines a VPC, a subnet, an EBS volume used for
nixbuild.net state and an EC2 instance for the `nxb-server`. It also defines all
necessary associations and the IAM policy needed for `nxb-server` to be able to
read secrets from SSM and create and destroy builder instances. The deployment
is intentionally simple, and you should likely adapt it to your own needs. For
example, the IAM policies can be locked down more.

[cloud-init.tf](./cloud-init.tf) contains the necessary directives to load
secrets from SSM.

[nixbuild-conf.tf](./nixbuild-conf.tf) contains the configuration for your
nixbuild.net deployment. This includes pre-defined accounts, build cluster
configuration etc.


## Prerequisites

The instructions below use `tofu` ([OpenTofu](https://opentofu.org/)), but
`terraform` should also work.

You can run `nix develop` in this directory to enter a shell where all the
tools used below are available.

The Terraform configuration in this directory depends on two secrets being
available as SSM parameters. To keep the secrets out of the local Terraform
state file, we manage these outside Terraform.

First, generate the secrets:

* Generate an SSH host key for the NixBuild SSH frontend. This is the host key
  that your Nix clients will see when they use your NixBuild deployment. The
  host key should be password-less and of type `Ed25519`. You can generate it
  like this:

  ```bash
  ssh-keygen -N "" -C dummy@dummy -t ed25519 -f ssh-host-key
  ```

  The `-C dummy@dummy` argument is there to work around a bug in the library
  that is used for reading SSH host keys, so make sure to use it.

* Generate a [Biscuit](https://www.biscuitsec.org/) key. This key will be used
  when NixBuild creates
  [auth tokens](https://docs.nixbuild.net/access-control/#using-auth-tokens).
  Use [biscuit-cli](https://github.com/biscuit-auth/biscuit-cli) to generate the
  key like this:

  ```bash
  biscuit keypair --only-private-key > biscuit-key
  ```

Now put the secrets into SSM:

```bash
aws ssm put-parameter \
  --region <YOUR REGION> \
  --type SecureString \
  --key-id alias/aws/ssm \
  --name "NIXBUILD_SSH_HOSTKEY" \
  --value "$(cat ./ssh-host-key)"

aws ssm put-parameter \
  --region <YOUR REGION> \
  --type SecureString \
  --key-id alias/aws/ssm \
  --name "NIXBUILD_BISCUIT_SECRETKEY" \
  --value "$(cat ./biscuit-key)"
```

It seems `aws ssm put-parameter` can ignore your default region, so to be sure
the secrets end up in the correct region, specify it explicitly with `--region`.

You can use other names for the SSM parameters if you like, but then you should
make sure to update the `ssm_param_biscuit_secretkey` and
`ssm_param_ssh_hostkey` Terraform variables in
[terraform.tfvars](./terraform.tfvars).


## Deployment

1. Configure the variables in [terraform.tfvars](./terraform.tfvars). At
   minimum, you need to set:

   * `region` — the AWS region to deploy in (e.g. `eu-north-1`).
   * `nxb_server_instance_type` — the EC2 instance type for the nxb-server
     (e.g. `c5a.4xlarge`).

   You can optionally set:

   * `nxb_version` — the nixbuild.net version to deploy. Defaults to the
     latest available version. See the
     [nixbuild.net AMI catalog](https://catalog.nixbuild.net/aws/amis.json) for
     available versions.
   * `nxb_server_ami` — which server AMI to use. Defaults to `server_x86_64`.
     Set to `server_aarch64` if you want an ARM-based server.

2. Edit the `nixbuild.conf` contents in [nixbuild-conf.tf](./nixbuild-conf.tf)
   to your liking. At minimum, you should add a nixbuild.net account with your
   SSH key. To do that, find the `predefined-accounts` setting and configure it
   like this:

   ```
   predefined-accounts = [
     {
       account-id = 1
       email = "dev@nixbuild.net"
       ssh-keys = [
         "ssh-ed25519 <pubkey> <comment>"
       ]
     }
   ]
   ```

   Each `account-id` must be unique across all predefined accounts.

   The public SSH key you use must be of the type `ed25519` due to a limitation
   in the SSH server in nixbuild.net.

3. Run `tofu init` if needed, then `tofu apply`.

   After a successful apply, the public IP address of the nxb-server will be
   shown as the `nxb_server_public_ip` output. You can use this IP to connect
   your Nix clients to your nixbuild.net deployment.
