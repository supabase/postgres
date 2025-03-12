UPSTREAM_NIX_GIT_SHA := $(shell git rev-parse HEAD)
GIT_SHA := $(shell git describe --tags --always --dirty)

init: qemu-arm64-nix.pkr.hcl
	packer init qemu-arm64-nix.pkr.hcl

output-cloudimg/packer-cloudimg: ansible qemu-arm64-nix.pkr.hcl
	packer build -var "git_sha=$(UPSTREAM_NIX_GIT_SHA)" qemu-arm64-nix.pkr.hcl

disk/focal-raw.img: output-cloudimg/packer-cloudimg
	mkdir -p disk
	sudo qemu-img convert -O raw output-cloudimg/packer-cloudimg disk/focal-raw.img

alpine-image: output-cloudimg/packer-cloudimg
	sudo nerdctl build . -t supabase-postgres-test:$(GIT_SHA) -f ./Dockerfile-kubernetes

clean:
	rm -rf output-cloudimg

.PHONY: alpine-image init clean
