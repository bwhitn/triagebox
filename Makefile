SHELL := /usr/bin/env bash

.PHONY: build build-resume build-fast build-kernel-fast preflight fetch-v86 build-v86-min use-v86-stock use-v86-min build-disk build-disk-resume build-kernel build-kernel-resume write-build-config disk-usage shrink-disk audit-runtime serve server docker-serve release-package show-version set-version clean

build: fetch-v86 build-disk

build-resume: fetch-v86 build-disk-resume

build-fast: preflight
	BUILDROOT_RESUME=1 BUILDROOT_TOPLEVEL_PARALLEL=1 PREFETCH_DOWNLOADS=0 AUTO_SHRINK=0 ./scripts/build-boot-assets-buildroot.sh
	./scripts/write-build-config.sh

build-kernel-fast: preflight
	BUILDROOT_RESUME=1 BUILDROOT_ONLY=kernel BUILDROOT_TOPLEVEL_PARALLEL=1 PREFETCH_DOWNLOADS=0 PREFETCH_REFINERY_WHEELS=0 REFINERY_REQUIRE_BUILDROOT_TARGET=0 ./scripts/build-boot-assets-buildroot.sh
	./scripts/write-build-config.sh

preflight:
	./scripts/check-build-deps.sh

fetch-v86: preflight
	./scripts/fetch-v86-assets.sh

build-v86-min:
	CHECK_V86_MIN=1 ./scripts/check-build-deps.sh
	./scripts/build-v86-min-assets.sh
	V86_ASSET_FLAVOR=v86-min ./scripts/write-build-config.sh

use-v86-stock:
	./scripts/write-build-config.sh

use-v86-min:
	V86_ASSET_FLAVOR=v86-min ./scripts/write-build-config.sh

build-disk: preflight
	./scripts/build-boot-assets-buildroot.sh
	./scripts/write-build-config.sh

build-disk-resume: preflight
	BUILDROOT_RESUME=1 ./scripts/build-boot-assets-buildroot.sh
	./scripts/write-build-config.sh

build-kernel: preflight
	BUILDROOT_ONLY=kernel PREFETCH_DOWNLOADS=0 PREFETCH_REFINERY_WHEELS=0 REFINERY_REQUIRE_BUILDROOT_TARGET=0 ./scripts/build-boot-assets-buildroot.sh
	./scripts/write-build-config.sh

build-kernel-resume: preflight
	BUILDROOT_RESUME=1 BUILDROOT_ONLY=kernel PREFETCH_DOWNLOADS=0 PREFETCH_REFINERY_WHEELS=0 REFINERY_REQUIRE_BUILDROOT_TARGET=0 ./scripts/build-boot-assets-buildroot.sh
	./scripts/write-build-config.sh

write-build-config:
	./scripts/write-build-config.sh

disk-usage:
	./scripts/disk-usage.sh

shrink-disk:
	./scripts/shrink-image.sh

audit-runtime:
	./scripts/audit-runtime-rootfs.sh

serve:
	./scripts/serve-local.sh

server: serve

docker-serve:
	./scripts/compose-up.sh

release-package:
	./scripts/package-release.sh

show-version:
	@cat VERSION

set-version:
	@test -n "$(VERSION)" || (echo "Usage: make set-version VERSION=v0.0.0" >&2; exit 1)
	./scripts/set-version.sh "$(VERSION)"

clean:
	rm -rf .work
	rm -f public/assets/buildroot-linux.img public/assets/default-extra.img public/assets/debian-trixie.img public/assets/vmlinuz public/assets/initrd.img public/assets/boot-image-info.txt public/assets/buildroot-legal-info.tar.gz public/assets/binary-refinery-missing-wheels.txt public/assets/binary-refinery-buildroot-provided.txt public/assets/binary-refinery-missing-buildroot-packages.txt
	rm -rf public/assets/v86 public/assets/v86-min public/assets/xterm
	mkdir -p public/assets
	touch public/assets/.gitkeep
