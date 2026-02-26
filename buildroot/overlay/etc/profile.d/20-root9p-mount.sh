#!/bin/sh

# Shell startup fallback: mount host 9p share at /root.
# This runs when /etc/profile is sourced.
if ! grep -qs ' /root 9p ' /proc/mounts; then
    mkdir -p /root 2>/dev/null || true

    if command -v modprobe >/dev/null 2>&1; then
        modprobe 9pnet_virtio 2>/dev/null || true
        modprobe 9pnet 2>/dev/null || true
        modprobe 9p 2>/dev/null || true
    elif /bin/busybox --list 2>/dev/null | grep -qx "modprobe"; then
        /bin/busybox modprobe 9pnet_virtio 2>/dev/null || true
        /bin/busybox modprobe 9pnet 2>/dev/null || true
        /bin/busybox modprobe 9p 2>/dev/null || true
    fi

    _root9p_tag=""
    for _root9p_path in /sys/bus/virtio/drivers/9pnet_virtio/virtio*/mount_tag /sys/bus/virtio/devices/virtio*/mount_tag; do
        [ -r "$_root9p_path" ] || continue
        _root9p_tag="$(tr -d '\r\n' < "$_root9p_path" 2>/dev/null || true)"
        [ -n "$_root9p_tag" ] && break
    done
    [ -n "$_root9p_tag" ] || _root9p_tag="host9p"

    _root9p_i=0
    while [ "$_root9p_i" -lt 8 ] && ! grep -qs ' /root 9p ' /proc/mounts; do
        mount -t 9p -o trans=virtio,version=9p2000.L,cache=loose,msize=262144 "$_root9p_tag" /root 2>/dev/null \
            || mount -t 9p -o trans=virtio,version=9p2000.L "$_root9p_tag" /root 2>/dev/null \
            || mount -t 9p "$_root9p_tag" /root 2>/dev/null \
            || {
                [ "$_root9p_tag" = "host9p" ] \
                    || mount -t 9p -o trans=virtio,version=9p2000.L host9p /root 2>/dev/null \
                    || mount -t 9p host9p /root 2>/dev/null
            }
        grep -qs ' /root 9p ' /proc/mounts && break
        _root9p_i=$((_root9p_i + 1))
        sleep 1
    done
fi
