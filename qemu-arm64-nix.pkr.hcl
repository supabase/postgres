variable "ansible_arguments" {
  type    = string
  default = "--skip-tags install-postgrest,install-pgbouncer,install-supabase-internal"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "git_sha" {
  type    = string
}

locals {
  creator = "packer"
}

variable "postgres-version" {
  type = string
  default = ""
}

variable "postgres-major-version" {
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

packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
    qemu = {
      version = "~> 1.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "null" "dependencies" {
  communicator = "none"
}

build {
  name    = "cloudimg.deps"
  sources = ["source.null.dependencies"]

  provisioner "shell-local" {
    inline = [
      "cp /usr/share/AAVMF/AAVMF_VARS.fd AAVMF_VARS.fd",
      "cloud-localds seeds-cloudimg.iso user-data-cloudimg meta-data"
    ]
    inline_shebang = "/bin/bash -e"
  }
}

source "qemu" "cloudimg" {
  boot_wait      = "2s"
  cpus           = 8
  disk_image     = true
  disk_size      = "15G"
  format         = "qcow2"
  headless       = true
  http_directory = "http"
  iso_checksum   = "file:https://cloud-images.ubuntu.com/focal/current/SHA256SUMS"
  iso_url        = "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-arm64.img"
  memory         = 40000
  qemu_binary    = "qemu-system-aarch64"
  qemuargs = [
    ["-machine", "virt,gic-version=3"],
    ["-cpu", "host"],
    ["-device", "virtio-gpu-pci"],
    ["-drive", "if=pflash,format=raw,id=ovmf_code,readonly=on,file=/usr/share/AAVMF/AAVMF_CODE.fd"],
    ["-drive", "if=pflash,format=raw,id=ovmf_vars,file=AAVMF_VARS.fd"],
    ["-drive", "file=output-cloudimg/packer-cloudimg,format=qcow2"],
    ["-drive", "file=seeds-cloudimg.iso,format=raw"],
    ["--enable-kvm"]
  ]
  shutdown_command       = "sudo -S shutdown -P now"
  ssh_handshake_attempts = 500
  ssh_password           = "ubuntu"
  ssh_timeout            = "1h"
  ssh_username           = "ubuntu"
  ssh_wait_timeout       = "1h"
  use_backing_file       = false
  accelerator            = "kvm"
}

build {
  name    = "cloudimg.image"
  sources = ["source.qemu.cloudimg"]

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
    source = "migrations"
    destination = "/tmp"
  }

  provisioner "shell" {
    environment_vars = [
      "POSTGRES_MAJOR_VERSION=${var.postgres-major-version}",
      "POSTGRES_SUPABASE_VERSION=${var.postgres-version}",
      "GIT_SHA=${var.git_sha}"
    ]
    use_env_var_file = true
    script = "ebssurrogate/scripts/qemu-bootstrap-nix.sh"
    execute_command = "sudo -S sh -c '. {{.EnvVarFile}} && cd /tmp/ansible-playbook && {{.Path}}'"
    start_retry_timeout = "5m"
    skip_clean = true
  }
}
