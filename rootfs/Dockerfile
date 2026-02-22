FROM --platform=linux/386 alpine:3.20

RUN set -eux; \
    apk add --no-cache \
      alpine-base \
      mkinitfs \
      util-linux \
      procps-ng; \
    apk del --no-cache busybox-suid || true; \
    rm -f /bin/bbsuid; \
    if apk add --no-cache linux-virt; then \
      kernel_flavor="virt"; \
    else \
      apk add --no-cache linux-lts; \
      kernel_flavor="lts"; \
    fi; \
    kernel_release="$(ls /lib/modules | sort | tail -n 1)"; \
    mkinitfs -F "base ata scsi virtio ext4" -k "${kernel_release}" -o "/boot/initramfs-${kernel_flavor}"

COPY overlay/ /

RUN chmod 0755 /usr/local/sbin/v86-init
