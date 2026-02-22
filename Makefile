SHELL := /usr/bin/env bash

.PHONY: build preflight fetch-v86 build-disk write-build-config disk-usage shrink-disk serve docker-serve clean

build: fetch-v86 build-disk

preflight:
	./scripts/check-build-deps.sh

fetch-v86: preflight
	./scripts/fetch-v86-assets.sh

build-disk: preflight
	./scripts/build-boot-assets-buildroot.sh
	./scripts/write-build-config.sh

write-build-config:
	./scripts/write-build-config.sh

disk-usage:
	./scripts/disk-usage.sh

shrink-disk:
	./scripts/shrink-image.sh

serve:
	./scripts/serve-local.sh

docker-serve:
	./scripts/compose-up.sh

clean:
	rm -rf .work
	rm -f public/assets/buildroot-linux.img public/assets/debian-trixie.img public/assets/vmlinuz public/assets/initrd.img public/assets/boot-image-info.txt public/assets/buildroot-legal-info.tar.gz public/assets/binary-refinery-missing-wheels.txt public/assets/binary-refinery-buildroot-provided.txt
	rm -rf public/assets/v86 public/assets/xterm
	mkdir -p public/assets
	touch public/assets/.gitkeep
