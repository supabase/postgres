variable "ami_name" {
  type    = string
  default = "supabase-postgres"
}

variable "ansible_arguments" {
  type    = string
  default = "--skip-tags install-postgrest,install-pgbouncer,install-supabase-internal"
}

variable "build-vol" {
  type    = string
  default = "xvdc"
}

variable "postgres_major_version" {
  type    = string
  default = env("POSTGRES_MAJOR_VERSION")
}

variable "postgres-version" {
  type    = string
  default = ""
}

variable "git-head-version" {
  type    = string
  default = "unknown"
}

variable "packer-execution-id" {
  type    = string
  default = "unknown"
}

variable "force-deregister" {
  type    = bool
  default = false
}

variable "input-hash" {
  type        = string
  default     = ""
  description = "Content hash of all input sources"
}

# These come from $arch.vars.pkr.hcl, don't need to pass in explicitly
variable "arch" {
  type        = string
  description = "Ubuntu image arch suffix (amd64|arm64), used to build the source AMI filter"
}

variable "instance_arch" {
  type        = string
  description = "AWS AMI architecture (x86_64|arm64)"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type used for the build instance"
}

# defined as variable because packer doesn't allow env() directly, not meant to be passed in
variable "region" {
  type    = string
  default = env("AWS_REGION")
}

locals {
  creator = "packer"
  ami     = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-${var.arch}-server-*"
}

packer {
  required_plugins {
    amazon = {
      source = "github.com/hashicorp/amazon"
      # don't use semver for the version since there's no lock files
      # can go back when we can have renovate watching this
      # see https://github.com/hashicorp/packer-plugin-amazon/issues/676
      version = "1.8.0"
    }
  }
}

# source block
source "amazon-ebssurrogate" "source" {
  ami_name                = "${var.ami_name}-${var.postgres-version}-${var.input-hash}-stage-1"
  ami_virtualization_type = "hvm"
  ami_architecture        = var.instance_arch
  instance_type           = var.instance_type
  region                  = var.region
  force_deregister        = var.force-deregister

  # Increase timeout for instance stop operations to handle large instances
  aws_polling {
    delay_seconds = 15
    max_attempts  = 120 # 120 * 15s = 30 minutes max wait
  }

  # Use latest official ubuntu noble ami owned by Canonical.
  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      name                = local.ami
      root-device-type    = "ebs"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  ena_support = true
  launch_block_device_mappings {
    device_name           = "/dev/xvdf"
    delete_on_termination = true
    volume_size           = 10
    volume_type           = "gp3"
    iops                  = 5000 # gp3 max at 10 GiB: 500 IOPS/GiB * 10
    throughput            = 1000 # bump to max once https://github.com/hashicorp/packer-plugin-amazon/pull/707 is merged (gp3 max at 0.25 MiB/s per IOPS * 5000 = 1250)
  }

  # NOTE: /dev/xvdh is mounted as /data (PostgreSQL data/WAL). The 1 GiB size
  # is a minimal default for this AMI; consumers should override this volume
  # size at launch.
  launch_block_device_mappings {
    device_name           = "/dev/xvdh"
    delete_on_termination = true
    volume_size           = 1
    volume_type           = "gp3"
  }

  launch_block_device_mappings {
    device_name           = "/dev/${var.build-vol}"
    delete_on_termination = true
    volume_size           = 16
    volume_type           = "gp3"
    iops                  = 8000 # gp3 max at 16 GiB: 500 IOPS/GiB * 16
    throughput            = 1000 # bump to max once https://github.com/hashicorp/packer-plugin-amazon/pull/707 is merged (gp3 max at 0.25 MiB/s per IOPS * 8000 = 2000)
    omit_from_artifact    = true
  }

  run_tags = {
    creator           = "packer"
    appType           = "postgres"
    packerExecutionId = var.packer-execution-id
    supaCreatedAt     = timestamp()
  }
  run_volume_tags = {
    creator           = "packer"
    appType           = "postgres"
    packerExecutionId = var.packer-execution-id
  }
  snapshot_tags = {
    creator           = "packer"
    appType           = "postgres"
    packerExecutionId = var.packer-execution-id
  }
  tags = {
    creator           = "packer"
    appType           = "postgres"
    postgresVersion   = "${var.postgres-version}-stage1"
    sourceSha         = var.git-head-version
    inputHash         = var.input-hash
    packerExecutionId = var.packer-execution-id
  }

  communicator = "ssh"
  ssh_pty      = true
  ssh_username = "ubuntu"
  ssh_timeout  = "5m"

  ami_root_device {
    source_device_name    = "/dev/xvdf"
    device_name           = "/dev/xvda"
    delete_on_termination = true
    volume_size           = 10
    volume_type           = "gp3"
    iops                  = 5000 # gp3 max at 10 GiB: 500 IOPS/GiB * 10
  }

  associate_public_ip_address = true
}

# a build block invokes sources and runs provisioning steps on them.
build {
  sources = ["source.amazon-ebssurrogate.source"]

  provisioner "file" {
    source      = "packer/files/ebsnvme-id"
    destination = "/tmp/ebsnvme-id"
  }

  provisioner "file" {
    source      = "packer/files/70-ec2-nvme-devices.rules"
    destination = "/tmp/70-ec2-nvme-devices.rules"
  }

  provisioner "file" {
    source      = "packer/scripts/chroot-bootstrap-nix.sh"
    destination = "/tmp/chroot-bootstrap-nix.sh"
  }

  provisioner "file" {
    source      = "packer/scripts/cleanup.sh"
    destination = "/tmp/cleanup.sh"
  }

  provisioner "file" {
    source      = "packer/files/cloud.cfg"
    destination = "/tmp/cloud.cfg"
  }

  provisioner "file" {
    source      = "packer/files/vector.timer"
    destination = "/tmp/vector.timer"
  }

  provisioner "file" {
    source      = "packer/files/apparmor_profiles"
    destination = "/tmp"
  }

  provisioner "file" {
    source      = "migrations"
    destination = "/tmp"
  }

  # Copy ansible playbook
  provisioner "shell" {
    inline = ["mkdir /tmp/ansible-playbook"]
  }

  provisioner "file" {
    source      = "ansible"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "shell" {
    environment_vars = [
      "ARGS=${var.ansible_arguments}",
      "POSTGRES_MAJOR_VERSION=${var.postgres_major_version}",
      "POSTGRES_SUPABASE_VERSION=${var.postgres-version}",
    ]
    use_env_var_file    = true
    script              = "packer/scripts/surrogate-bootstrap-nix.sh"
    execute_command     = "sudo -S sh -c '. {{.EnvVarFile}} && cd /tmp/ansible-playbook && {{.Path}}'"
    start_retry_timeout = "5m"
    skip_clean          = true
  }

  provisioner "file" {
    source      = "/tmp/ansible.log"
    destination = "/tmp/ansible.log"
    direction   = "download"
  }
}
