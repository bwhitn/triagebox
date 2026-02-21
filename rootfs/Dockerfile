FROM --platform=linux/386 i386/debian:trixie-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash \
       initramfs-tools \
       linux-image-686 \
       procps \
       util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY overlay/ /

RUN chmod 0755 /usr/local/sbin/v86-init
