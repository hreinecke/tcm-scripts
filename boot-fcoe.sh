#!/bin/bash

MAC_0=0c:fd:37:04:1a:1e
MAC_1=0c:fd:37:04:1a:1f
WWN=0x50cfd376bf663032
IMG=/abuild/kvm/sles-fcoe-boot.img

qemu-system-x86_64 -m 2048 -enable-kvm -machine q35 -cpu SandyBridge \
  -drive file=/abuild/kvm/ovmf-fcoe.rom,if=pflash,format=raw \
  -netdev tap,id=net0,script=/abuild/kvm/qemu-ifup \
  -netdev tap,id=net1,script=/abuild/kvm/qemu-ifup \
  -drive file=${IMG},if=none,format=raw,cache=none,id=bootdisk \
  -device virtio-scsi-pci,id=virtio-1 \
  -device scsi-disk,bus=virtio-1.0,drive=bootdisk,serial=bootdisk,wwn=${WWN} \
  -device virtio-net-pci,mac=${MAC_0},netdev=net0 \
  -device virtio-net-pci,mac=${MAC_1},netdev=net1 \
$*
