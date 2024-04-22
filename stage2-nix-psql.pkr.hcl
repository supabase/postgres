variable "ami_name" {
  type    = string
  default = "supabase-postgres"
}

variable "ami_regions" {
  type    = list(string)
  default = ["ap-southeast-2"]
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
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
  ami_name      = "${var.ami_name}-stage-2"
  instance_type = "c6g.4xlarge"
  region        = "${var.region}"
  source_ami_filter {
    filters = {
      name          = "supabase-postgres-15.1.1.41-stage-1"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["194568623217"]
  }
  ssh_username = "ubuntu"
  ena_support = true

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
    source = "ansible/tasks/stage2"
    destination = "/tmp/ansible-playbook"
  }

  provisioner "file" {
    source = "ansible/files"
    destination = "/tmp/ansible-playbook/files"
  }


 provisioner "shell" {
     script = "scripts/nix-provision.sh"
  }
}
