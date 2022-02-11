## Ext4 amd64 AMI creation

`packer build -var "aws_access_key=$AWS_ACCESS_KEY_ID" -var "aws_secret_key=$AWS_SECRET_ACCESS_KEY" -var "region=$AWS_REGION" \
-var "docker_passwd=$DOCKER_PASSWD" -var "docker_user=$DOCKER_USER" -var "docker_image=$DOCKER_IMAGE" -var "docker_image_tag=$DOCKER_IMAGE_TAG" \
amazon-amd64.pkr.hcl`

## Ext4 arm64 AMI creation

`packer build -var "aws_access_key=$AWS_ACCESS_KEY_ID" -var "aws_secret_key=$AWS_SECRET_ACCESS_KEY" -var "region=$AWS_REGION" \
-var "docker_passwd=$DOCKER_PASSWD" -var "docker_user=$DOCKER_USER" -var "docker_image=$DOCKER_IMAGE" -var "docker_image_tag=$DOCKER_IMAGE_TAG" \
amazon-arm64.pkr.hcl`

## Docker Image

	DOCKER_IMAGE is used to store ccache data during build process. This can be any image, you can create your image using:

	```
	docker pull ubuntu
	docker tag ubuntu <username>/ccache
	docker push <username>/ccache
	```

	For ARM64 builds

	```	
	docker pull arm64v8/ubuntu
	docker tag arm64v8/ubuntu:latest <username>/ccache-arm64v8
	docker push <username>/ccache-arm64v8
	```
	
	Now set DOCKER_IMAGE="<username>/ccache" or DOCKER_IMAGE="<username>/ccache-arm64v8" based on your AMI architecture.
	
	
## EBS-Surrogate File layout

```
$ tree ebssurrogate/
ebssurrogate/
├── files
│   ├── 70-ec2-nvme-devices.rules
│   ├── cloud.cfg		# cloud.cfg for cloud-init
│   ├── ebsnvme-id
│   ├── sources-arm64.cfg       # apt/sources.list for arm64
│   ├── sources.cfg		# apt/sources.list for amd64
│   ├── vector.timer            # systemd-timer to delay vectore execution
│   └── zfs-growpart-root.cfg
└── scripts
    ├── chroot-bootstrap.sh    # Installs grub and other required packages for build. Configures target AMI  settings
    └── surrogate-bootstrap.sh # Formats disk and setups chroot environment. Runs Ansible tasks within chrooted environment.
```
