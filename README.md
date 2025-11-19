# nixbuild.net AWS Deployment

This directory defines a simple Terraform deployment of nixbuild.net, that you
can use directly or as a base for a more refined deployment.

## Repository Overview

[amis.json](./amis.json) declares all available AMIs. The Terraform
configuration will automatically look up AMI ids from this file, based on what
you set the `nxb_version` variable to. This file is updated by the nixbuild.net
team when new releases of nixbuild.net are published.

[variables.tf](./variables.tf) defines all available Terraform variables along
with the AMI lookup logic.

[main.tf](./main.tf) defines a VPC, a subnet, an EBS volume used for
nixbuild.net state and an EC2 instance for the `nxb-server`. It also defines all
necessary associations and the IAM policy needed for `nxb-server` to be able to
read secrets from SSM and create and destroy builder instances. The deployment
is intentionally simple, and you should likely adapt it to your own needs. For
example, it is possible to use different subnets for the builders and the
server, and to disable public IPs for builders. The IAM policies can also be
locked down more.

[cloud-init.yaml](./cloud-init.yaml) contains the necessary directives to load
secrets from SSM, as well as the NixBuild configuration.

TODO: Put the NixBuild configuration in a separate file for clarity.
Unfortunately not possible at the moment due to various limitations/bugs in the
`cloud-init` implementation that is used in NixBuild AMIs.

## Prerequisites

The Terraform configuration in this directory depends on two secrets being
available as SSM parameters. You configure the names of the SSM parameters in
[terraform.tfvars](./terraform.tfvars). See [variables.tf](./variables.tf) for
variable descriptions.

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

  `biscuit-cli` is available in nixpkgs, so if you don't have it installed
  locally you can just start a Nix shell with `nix shell nixpkgs#biscuit-cli` to
  make the above command work.

  **Note**, lately `biscuit-cli` has started printing a prefix like
  `ed25519-private/` before the key material. nixbuild.net doesn't yet handle
  parsing keys with such a prefix, so remove the prefix before storing the key
  to SSM.

Then, come up with SSM parameter names for the secrets. If you are paranoid, you
can use something completely random. Add the names to `terraform.tfvars`:

```
ssm_param_biscuit_secretkey = "NIXBUILD_BISCUIT_SECRETKEY"
ssm_param_ssh_hostkey       = "NIXBUILD_SSH_HOSTKEY"
```

Now put the parameters into SSM:

```
aws ssm put-parameter \
  --type SecureString \
  --key-id alias/aws/ssm \
  --name "NIXBUILD_SSH_HOSTKEY" \
  --value "$(cat ./ssh-host-key)"

aws ssm put-parameter \
  --type SecureString \
  --key-id alias/aws/ssm \
  --name "NIXBUILD_BISCUIT_SECRETKEY" \
  --value "$(cat ./biscuit-key)"
```

## Deployment

1. Configure the variables in [terraform.tfvars](./terraform.tfvars).

2. Edit the `nixbuild.conf` contents in [cloud-init.yaml](./cloud-init.yaml) to
   your liking. At minimum, you should add a nixbuild.net account with your SSH
   key. To do that, find the `predefined-accounts` setting and configure it
   like this:

   ```
   predefined-accounts = [
     {
       account-id = 1
       email = "dev@nixbuild.net"
       ssh-keys = [
         "ssh-ed25519 <pubkey> <comment>
       ]
     }
   ]
   ```

3. Run `terraform init` if needed, then `terraform apply`.
