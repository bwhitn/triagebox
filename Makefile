SHELL := /usr/bin/env bash

.PHONY: build fetch-v86 build-disk serve docker-serve clean

build: fetch-v86 build-disk

fetch-v86:
	./scripts/fetch-v86-assets.sh

build-disk:
	./scripts/build-boot-assets.sh

serve:
	./scripts/serve-local.sh

docker-serve:
	./scripts/compose-up.sh

clean:
	rm -rf .work
	rm -f public/assets/alpine-linux.img public/assets/debian-trixie.img public/assets/vmlinuz public/assets/initrd.img public/assets/boot-image-info.txt
	rm -rf public/assets/v86
	mkdir -p public/assets
	touch public/assets/.gitkeep
