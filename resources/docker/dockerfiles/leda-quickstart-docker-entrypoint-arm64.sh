#!/bin/bash
# /********************************************************************************
# * Copyright (c) 2022 Contributors to the Eclipse Foundation
# *
# * See the NOTICE file(s) distributed with this work for additional
# * information regarding copyright ownership.
# *
# * This program and the accompanying materials are made available under the
# * terms of the Apache License 2.0 which is available at
# * https://www.apache.org/licenses/LICENSE-2.0
# *
# * SPDX-License-Identifier: Apache-2.0
# ********************************************************************************/
#
# Run qemu with TAP network
#
# set -x 

USERID="-u $(id -u)"
GROUP="-g $(id -g)"
TUNCTL="sudo tunctl"
IFCONFIG="sudo ip"
IPTABLES="sudo iptables"
TAP=

function setupTap() {
    TAP=`$TUNCTL -b $GROUP 2>&1`
    n=$[ (`echo $TAP | sed 's/tap//'` * 2) + 1 ]
    $IFCONFIG addr add 192.168.7.$n/32 broadcast 192.168.7.255 dev $TAP
    $IFCONFIG link set dev $TAP up
    dest=$[ (`echo $TAP | sed 's/tap//'` * 2) + 2 ]
    $IFCONFIG route add to 192.168.7.$dest dev $TAP
    $IPTABLES -A POSTROUTING -t nat -j MASQUERADE -s 192.168.7.$n/32
    $IPTABLES -A POSTROUTING -t nat -j MASQUERADE -s 192.168.7.$dest/32
    sudo bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
    sudo bash -c "echo 1 > /proc/sys/net/ipv4/conf/$TAP/proxy_arp"
    $IPTABLES -P FORWARD ACCEPT
    echo "Set up TAP network interface: $TAP"
}

function teardownTap() {
    echo "Tearing down TAP network interface: $TAP"
    $TUNCTL -d $TAP
    $IFCONFIG link del $TAP
    n=$[ (`echo $TAP | sed 's/tap//'` * 2) + 1 ]
    dest=$[ (`echo $TAP | sed 's/tap//'` * 2) + 2 ]
    $IPTABLES -D POSTROUTING -t nat -j MASQUERADE -s 192.168.7.$n/32
    $IPTABLES -D POSTROUTING -t nat -j MASQUERADE -s 192.168.7.$dest/32
}

trap teardownTap EXIT

setupTap

# Forward network traffic for SSH to the QEMU Guest
iptables -t nat -A PREROUTING -p tcp --dport 22 -j DNAT --to-destination 192.168.7.$dest:22

# Forward network traffic for SSH to the QEMU Guest
iptables -t nat -A PREROUTING -p tcp --dport 31883 -j DNAT --to-destination 192.168.7.$dest:31883

# Forward Kubernetes Server API Port
iptables -t nat -A PREROUTING -p tcp --dport 6433 -j DNAT --to-destination 192.168.7.$dest:6443

# Masquerade the IP Address of the sender, so that the packet will go back to the gateway
iptables -t nat -A POSTROUTING -j MASQUERADE

qemu-system-aarch64 \
-device virtio-net-device,netdev=net0,mac=52:54:00:12:34:03 \
-netdev tap,id=net0,ifname=$TAP,script=no,downscript=no \
-object rng-random,filename=/dev/urandom,id=rng0 \
-device virtio-rng-pci,rng=rng0 \
-drive id=disk0,file=sdv-image-all-qemuarm64.wic.qcow2,if=none,format=qcow2 \
-device virtio-blk-device,drive=disk0 \
-device qemu-xhci \
-device usb-tablet \
-device usb-kbd \
-serial mon:stdio \
-serial null \
-nographic \
-object can-bus,id=canbus0 \
-device kvaser_pci,canbus=canbus0 \
-machine virt \
-cpu cortex-a57 \
-smp 4 \
-m 4096 \
-serial mon:vc \
-device virtio-gpu-pci \
-bios u-boot.bin
