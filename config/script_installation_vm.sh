#!/usr/bin/env bash
#
# Fresh VM (e.g. GCP lab box) — run once from this directory so cloud-init files resolve:
#
#   sudo apt update && sudo apt install -y git
#   git clone https://github.com/romaincomtet/SecureInfra.git
#   cd SecureInfra/config
#   chmod +x script_installation_vm.sh
#   ./script_installation_vm.sh
#
# Disks and images are written under /var/lib/libvirt/images/secureinfra (not $PWD).
# After the first run, log out and back in (or reboot) so the libvirt/kvm groups apply everywhere.
#
# Console / Mac keyboard:
#   Default "virsh console" escape is Ctrl+] — hard on many Mac / AZERTY layouts.
#   Use:  chmod +x virsh-console.sh && ./virsh-console.sh vm1
#   Exit console: Ctrl+[  then  .  (period)
#   Or skip serial console:  sudo virsh domifaddr vm1  then  ssh ubuntu@<ip>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# qemu:///system runs as libvirt-qemu (group kvm); disks under $HOME are often not traversable.
VM_WORKDIR="/var/lib/libvirt/images/secureinfra"

sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst cloud-image-utils

sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm "$USER"
newgrp libvirt
virsh list --all

# Optional: check KVM is available
lsmod | grep kvm
test -e /dev/kvm && echo "/dev/kvm exists"

# If "default" exists but was never started, wake it (often redundant on Ubuntu).
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default 2>/dev/null || true

sudo mkdir -p "$VM_WORKDIR"
sudo chown "$(id -un):kvm" "$VM_WORKDIR"
sudo chmod 2775 "$VM_WORKDIR"
cd "$VM_WORKDIR"

# Download an x86_64 cloud image
if [ ! -f jammy-server-cloudimg-amd64.img ]; then
  wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
fi

# Create overlay disks
qemu-img create -f qcow2 -F qcow2 -b jammy-server-cloudimg-amd64.img vm1.qcow2 20G
qemu-img create -f qcow2 -F qcow2 -b jammy-server-cloudimg-amd64.img vm2.qcow2 20G

# Create cloud-init seed ISOs (inputs stay in repo; outputs in VM_WORKDIR)
cloud-localds seed-vm1.iso "$SCRIPT_DIR/user-data" "$SCRIPT_DIR/meta-data"
cloud-localds seed-vm2.iso "$SCRIPT_DIR/user-data-vm2" "$SCRIPT_DIR/meta-data-vm2"

# Ensure group read (belt and suspenders if setgid did not apply)
chmod g+r vm1.qcow2 vm2.qcow2 seed-vm1.iso seed-vm2.iso jammy-server-cloudimg-amd64.img 2>/dev/null || true

# Create VM1 (qemu:///system: session URI has no "default" network)
sudo virt-install \
  --connect qemu:///system \
  --name vm1 \
  --noautoconsole \
  --import \
  --memory 2048 \
  --vcpus 1 \
  --osinfo ubuntu22.04 \
  --arch x86_64 \
  --disk path="$VM_WORKDIR/vm1.qcow2",format=qcow2,bus=virtio \
  --disk path="$VM_WORKDIR/seed-vm1.iso",device=cdrom \
  --network network=default,model=virtio

# Create VM2
sudo virt-install \
  --connect qemu:///system \
  --name vm2 \
  --noautoconsole \
  --import \
  --memory 2048 \
  --vcpus 1 \
  --osinfo ubuntu22.04 \
  --arch x86_64 \
  --disk path="$VM_WORKDIR/vm2.qcow2",format=qcow2,bus=virtio \
  --disk path="$VM_WORKDIR/seed-vm2.iso",device=cdrom \
  --network network=default,model=virtio
