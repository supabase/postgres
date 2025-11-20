variable "profile" {
  type    = string
  default = "${env("AWS_PROFILE")}"
}

variable "ami_regions" {
  type    = list(string)
  default = ["ap-southeast-1"]
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
}

variable "ami_name" {
  type    = string
  default = "supabase-postgres"
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
variable "git_sha" {
  type    = string
  default = env("GIT_SHA")
}

variable "postgres_major_version" {
  type    = string
  default = ""
}

packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "${var.ami_name}-${var.postgres-version}"
  instance_type = "c6g.4xlarge"
  region        = "${var.region}"
  source_ami_filter {
    filters = {
      name   = "${var.ami_name}-${var.postgres-version}-stage-1"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon", "self"]
  }

  communicator = "ssh"
  ssh_pty = true
  ssh_username = "ubuntu"
  ssh_timeout = "5m"

  associate_public_ip_address = true

  # Increase timeout for instance stop operations to handle large instances
  aws_polling {
    delay_seconds = 15
    max_attempts  = 120  # 120 * 15s = 30 minutes max wait
  }
  
  launch_block_device_mappings {
    device_name           = "/dev/xvdc"
    delete_on_termination = true
    volume_size           = 40
    volume_type           = "gp2"
    omit_from_artifact    = true
  }

  ena_support = true

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
    postgresVersion = "${var.postgres-version}"
    sourceSha = "${var.git-head-version}"
  }
}

build {
  name = "nix-packer-ubuntu"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  # Copy ansible playbook
  provisioner "shell" {
    inline = ["mkdir /tmp/ansible-playbook"]
  }

  provisioner "file" {
    source = "ansible"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source = "migrations"
    destination = "/tmp"
  }

  provisioner "file" {
    source = "scripts"
    destination = "/tmp/ansible-playbook"
  }

  # Mount temporary build volume before nix operations
  provisioner "shell" {
    script = "scripts/mount-build-volume.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "GIT_SHA=${var.git_sha}",
      "POSTGRES_MAJOR_VERSION=${var.postgres_major_version}"
    ]
     script = "scripts/nix-provision.sh"
  }

  # Copy nix store from temp volume to root filesystem after all operations complete
  provisioner "shell" {
    script = "scripts/copy-nix-store.sh"
  }

}
