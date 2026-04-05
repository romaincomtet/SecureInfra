sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst cloud-image-utils

sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
newgrp libvirt
virsh list --all

# mount the shared folder
sudo mkdir -p /mnt/shared
sudo mount -t 9p -o trans=virtio share /mnt/shared
cd /mnt/shared


wget https://cloud-images.ubuntu.com/noble/current/jammy-server-cloudimg-arm64.img

qemu-img create -f qcow2 -F qcow2 -b jammy-server-cloudimg-arm64.img vm1.qcow2 40G
qemu-img create -f qcow2 -F qcow2 -b jammy-server-cloudimg-arm64.img vm2.qcow2 40G

cloud-localds seed-vm1.iso user-data meta-data
cloud-localds seed-vm2.iso user-data-vm2 meta-data-vm2

virt-install \
  --name vm1 \
  --noautoconsole \
  --import \
  --memory 2048 \
  --vcpus 2 \
  --osinfo generic \
  --arch aarch64 \
  --disk bus=virtio,path=$(pwd)/jammy-server-cloudimg-arm64.img \
  --network default \
  --cloud-init user-data=$(pwd)/user-data,meta-data=$(pwd)/meta-data