packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.2"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "nix-packer-ubuntu"
  instance_type = "t4g.xlarge"
  region        = "us-east-1"
  source_ami_filter {
    filters = {
      image-id          = "ami-0f96dd7e4b73241d8"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["194568623217"]
  }
  ssh_username = "ubuntu"
  ena_support = true
  launch_block_device_mappings {
    device_name = "/dev/sda1"
    volume_size = 40
    volume_type = "gp3"
    delete_on_termination = true
  }
  launch_block_device_mappings {
    device_name = "/dev/xvdf"
    delete_on_termination = true
    volume_size = 30
    volume_type = "gp3"
   }

  launch_block_device_mappings {
    device_name = "/dev/xvdh"
    delete_on_termination = true
    volume_size = 30
    volume_type = "gp3"
   }
  
  launch_block_device_mappings {
    device_name = "/dev/xvda"
    delete_on_termination = true
    volume_size = 30
    volume_type = "gp3"
   }
 

}

build {
  name = "nix-packer-ubuntu"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]
 provisioner "shell" {
     script = "scripts/nix-provision.sh"
  }
}
