FROM --platform=linux/386 alpine:3.20

ARG MKINITFS_FEATURES="base ata scsi ext4"
ARG USER_APK_PACKAGES=""
ARG PYTHON_PIP_PACKAGES="binary-refinery"
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
    if [ -n "${PYTHON_PIP_PACKAGES}" ]; then \
      apk add --no-cache --virtual .pip-build-deps \
        py3-pip \
        ca-certificates \
        build-base \
        python3-dev; \
      PIP_BREAK_SYSTEM_PACKAGES=1 PIP_NO_CACHE_DIR=1 python3 -m pip install --no-cache-dir ${PYTHON_PIP_PACKAGES}; \
      python3 -m pip cache purge >/dev/null 2>&1 || true; \
      apk del --no-cache .pip-build-deps || true; \
      rm -rf /root/.cache /tmp/pip-* /tmp/*.whl; \
      find /usr/lib/python3* -type d -name '__pycache__' -prune -exec rm -rf {} +; \
      find /usr/lib/python3* -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete; \
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
