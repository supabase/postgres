UPSTREAM_NIX_GIT_SHA := $(shell git rev-parse HEAD)
GIT_SHA := $(shell git describe --tags --always --dirty)

init: qemu-arm64-nix.pkr.hcl
	packer init qemu-arm64-nix.pkr.hcl

output-cloudimg/packer-cloudimg: ansible qemu-arm64-nix.pkr.hcl
	packer build -var "git_sha=$(UPSTREAM_NIX_GIT_SHA)" qemu-arm64-nix.pkr.hcl

alpine-image: output-cloudimg/packer-cloudimg
	sudo nerdctl build . -t supabase-postgres-test:$(GIT_SHA) -f ./Dockerfile-kubernetes

# Build minimal Alpine-based image
minimal-image:
	docker build -f Dockerfile-alpine-minimal -t supabase/postgres:minimal .

clean:
	rm -rf output-cloudimg

.PHONY: alpine-image init clean minimal-image
