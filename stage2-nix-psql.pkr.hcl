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

variable "git_sha" {
  type    = string
  default = env("GIT_SHA")
}

variable "postgres_major_version" {
  type    = string
  default = ""
}

variable "source_ami" {
  type    = string
  description = "Source AMI ID from stage 1"
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
  source_ami    = "${var.source_ami}"

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
    packerExecutionId = "${var.packer-execution-id}"
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

  provisioner "file" {
    source = "audit-specs"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "shell" {
    environment_vars = [
      "GIT_SHA=${var.git_sha}",
      "POSTGRES_MAJOR_VERSION=${var.postgres_major_version}"
    ]
     script = "scripts/nix-provision.sh"
  }

}
