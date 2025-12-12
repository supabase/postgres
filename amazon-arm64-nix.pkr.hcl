variable "ami" {
  type    = string
  default = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"
}

variable "profile" {
  type    = string
  default = "${env("AWS_PROFILE")}"
}

variable "ami_name" {
  type    = string
  default = "supabase-postgres"
}

variable "ami_regions" {
  type    = list(string)
  default = ["ap-southeast-1"]
}

variable "ansible_arguments" {
  type    = string
  default = "--skip-tags install-postgrest,install-pgbouncer,install-supabase-internal"
}

variable "region" {
  type    = string
}

variable "build-vol" {
  type    = string
  default = "xvdc"
}

# ccache docker image details
variable "docker_user" {
  type    = string
  default = ""
}

variable "docker_passwd" {
  type    = string
  default = ""
}

variable "docker_image" {
  type    = string
  default = ""
}

variable "docker_image_tag" {
  type    = string
  default = "latest"
}

locals {
  creator = "packer"
}

variable "postgres-version" {
  type = string
  default = ""
}

variable "git-head-version" {
  type = string
  default = "unknown"
}

variable "packer-execution-id" {
  type = string
  default = "unknown"
}

variable "force-deregister" {
  type    = bool
  default = false
}

variable "input-hash" {
  type    = string
  default = ""
  description = "Content hash of all input sources"
}

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

# source block
source "amazon-ebssurrogate" "source" {
  profile = "${var.profile}"
  ami_name = "${var.ami_name}-${var.postgres-version}-${var.input-hash}-stage-1"
  ami_virtualization_type = "hvm"
  ami_architecture = "arm64"
  ami_regions   = "${var.ami_regions}"
  instance_type = "c6g.4xlarge"
  region       = "${var.region}"
  force_deregister = var.force-deregister

  # Increase timeout for instance stop operations to handle large instances
  aws_polling {
    delay_seconds = 15
    max_attempts  = 120  # 120 * 15s = 30 minutes max wait
  }

  # Use latest official ubuntu noble ami owned by Canonical.
  source_ami_filter {
    filters = {
      virtualization-type = "hvm"
      name = "${var.ami}"
      root-device-type = "ebs"
    }
    owners = [ "099720109477" ]
    most_recent = true
  }

  ena_support = true
  launch_block_device_mappings {
    device_name = "/dev/xvdf"
    delete_on_termination = true
    volume_size = 10
    volume_type = "gp3"
   }

  launch_block_device_mappings {
    device_name = "/dev/xvdh"
    delete_on_termination = true
    volume_size = 8
    volume_type = "gp3"
   }

  launch_block_device_mappings {
    device_name           = "/dev/${var.build-vol}"
    delete_on_termination = true
    volume_size           = 16
    volume_type           = "gp2"
    omit_from_artifact    = true
  }

  run_tags = {
    creator           = "packer"
    appType           = "postgres"
    packerExecutionId = "${var.packer-execution-id}"
  }
  run_volume_tags = {
    creator = "packer"
    appType = "postgres"
  }
  snapshot_tags = {
    creator = "packer"
    appType = "postgres"
  }
  tags = {
    creator = "packer"
    appType = "postgres"
    postgresVersion = "${var.postgres-version}-stage1"
    sourceSha = "${var.git-head-version}"
    inputHash = "${var.input-hash}"
  }

  communicator = "ssh"
  ssh_pty = true
  ssh_username = "ubuntu"
  ssh_timeout = "5m"

  ami_root_device {
    source_device_name = "/dev/xvdf"
    device_name = "/dev/xvda"
    delete_on_termination = true
    volume_size = 10
    volume_type = "gp2"
  }

  associate_public_ip_address = true
}

# a build block invokes sources and runs provisioning steps on them.
build {
  sources = ["source.amazon-ebssurrogate.source"]

  provisioner "file" {
    source = "ebssurrogate/files/sources-arm64.cfg"
    destination = "/tmp/sources.list"
  }

  provisioner "file" {
    source = "ebssurrogate/files/ebsnvme-id"
    destination = "/tmp/ebsnvme-id"
  }

  provisioner "file" {
    source = "ebssurrogate/files/70-ec2-nvme-devices.rules"
    destination = "/tmp/70-ec2-nvme-devices.rules"
  }

  provisioner "file" {
    source = "ebssurrogate/scripts/chroot-bootstrap-nix.sh"
    destination = "/tmp/chroot-bootstrap-nix.sh"
  }

  provisioner "file" {
    source = "ebssurrogate/files/cloud.cfg"
    destination = "/tmp/cloud.cfg"
  }

  provisioner "file" {
    source = "ebssurrogate/files/vector.timer"
    destination = "/tmp/vector.timer"
  }

  provisioner "file" {
    source = "ebssurrogate/files/apparmor_profiles"
    destination = "/tmp"
  }

  provisioner "file" {
    source = "migrations"
    destination = "/tmp"
  }

  # Copy ansible playbook
  provisioner "shell" {
    inline = ["mkdir /tmp/ansible-playbook"]
  }

  provisioner "file" {
    source = "ansible"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source = "scripts"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source = "ansible/vars.yml"
    destination = "/tmp/ansible-playbook/vars.yml"
  }

  provisioner "shell" {
    environment_vars = [
      "ARGS=${var.ansible_arguments}",
      "DOCKER_USER=${var.docker_user}",
      "DOCKER_PASSWD=${var.docker_passwd}",
      "DOCKER_IMAGE=${var.docker_image}",
      "DOCKER_IMAGE_TAG=${var.docker_image_tag}",
      "POSTGRES_SUPABASE_VERSION=${var.postgres-version}"
    ]
    use_env_var_file = true
    script = "ebssurrogate/scripts/surrogate-bootstrap-nix.sh"
    execute_command = "sudo -S sh -c '. {{.EnvVarFile}} && cd /tmp/ansible-playbook && {{.Path}}'"
    start_retry_timeout = "5m"
    skip_clean = true
  }

  provisioner "file" {
    source = "/tmp/ansible.log"
    destination = "/tmp/ansible.log"
    direction = "download"
  }
}
