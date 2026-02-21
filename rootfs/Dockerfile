FROM --platform=linux/386 alpine:3.20

RUN set -eux; \
    apk add --no-cache \
      alpine-base \
      mkinitfs \
      util-linux \
      procps-ng; \
    if apk add --no-cache linux-lts; then \
      kernel_flavor="lts"; \
    else \
      apk add --no-cache linux-virt; \
      kernel_flavor="virt"; \
    fi; \
    kernel_release="$(ls /lib/modules | sort | tail -n 1)"; \
    mkinitfs -F "base ide scsi virtio ext4" -k "${kernel_release}" -o "/boot/initramfs-${kernel_flavor}"

COPY overlay/ /

RUN chmod 0755 /usr/local/sbin/v86-init
