FROM --platform=linux/386 alpine:3.20

ARG MKINITFS_FEATURES="base ata scsi ext4"
ARG USER_APK_PACKAGES=""
ARG STRIP_TO_BUSYBOX="1"

COPY user-packages.txt /tmp/user-packages.txt

RUN set -eux; \
    user_pkgs="$(awk 'NF && $1 !~ /^#/ {printf "%s ", $1}' /tmp/user-packages.txt)"; \
    if [ -n "${user_pkgs}" ]; then \
      apk add --no-cache ${user_pkgs}; \
    fi; \
    if [ -n "${USER_APK_PACKAGES}" ]; then \
      apk add --no-cache ${USER_APK_PACKAGES}; \
    fi; \
    apk add --no-cache \
      mkinitfs; \
    apk del --no-cache busybox-suid || true; \
    rm -f /bin/bbsuid; \
    if apk add --no-cache linux-virt; then \
      kernel_flavor="virt"; \
    else \
      apk add --no-cache linux-lts; \
      kernel_flavor="lts"; \
    fi; \
    kernel_release="$(ls /lib/modules | sort | tail -n 1)"; \
    mkinitfs -F "${MKINITFS_FEATURES}" -k "${kernel_release}" -o "/boot/initramfs-${kernel_flavor}"; \
    if [ "${STRIP_TO_BUSYBOX}" = "1" ]; then \
      apk del --no-cache \
        mkinitfs \
        apk-tools \
        alpine-keys \
        ca-certificates-bundle \
        ssl_client \
        scanelf \
        lddtree || true; \
      rm -rf /etc/apk /lib/apk /var/lib/apk /usr/share/apk /etc/ssl /usr/share/ca-certificates; \
      rm -f /sbin/apk; \
    else \
      apk del --no-cache mkinitfs || true; \
    fi; \
    rm -rf /tmp/mkinitfs* /var/tmp/*; \
    rm -f /tmp/user-packages.txt

COPY overlay/ /

RUN chmod 0755 /usr/local/sbin/v86-init
