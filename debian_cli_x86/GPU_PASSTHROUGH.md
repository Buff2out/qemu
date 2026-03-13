# GPU Passthrough (RTX 3050 Mobile) to Debian VM

## Why the host loses GPU access

A GPU cannot be shared between two OS kernels simultaneously — it's a fundamental hardware limitation. The nvidia driver requires exclusive ownership of the hardware registers, memory controller, and command queues. VFIO passthrough works by taking that ownership away from the host entirely and handing the raw PCIe device to the VM. There is no "split memory" mode at the hardware level.

**Options that exist for sharing:**

- **SR-IOV** — some enterprise/datacenter GPUs (A-series) support hardware-level virtualization with virtual functions. Consumer GPUs (RTX 3050) don't support it.
- **NVIDIA vGPU** — NVIDIA's proprietary solution that allows sharing, but requires a licensed datacenter GPU (Quadro/Tesla/A-series) and a paid license. Not available on GeForce/RTX consumer cards.
- **Dynamic rebinding** — run nvidia on the host normally, then before launching the VM: unbind from nvidia → bind to vfio-pci, launch VM, reverse after shutdown. One GPU, used by one side at a time but switchable. The current setup uses static binding (always reserved for the VM at boot).

---

## Host NixOS Setup

### `hosts/modules/vfio.nix`

```nix
# IOMMU для GPU passthrough
boot.kernelParams = [ "intel_iommu=on" "iommu=pt" ];

# Загружаем vfio-pci до того, как nvidia успеет захватить GPU
boot.initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];

# Привязываем GPU (01:00.0) и его аудио (01:00.1) к vfio-pci по ID
boot.extraModprobeConfig = ''
  options vfio-pci ids=10de:25a2,10de:2291
'';

# Права доступа к /dev/vfio/* для группы kvm
services.udev.extraRules = ''
  SUBSYSTEM=="vfio", OWNER="root", GROUP="kvm", MODE="0660"
'';

# VFIO требует блокировки всей RAM виртуалки в памяти хоста
security.pam.loginLimits = [
  { domain = "@kvm"; item = "memlock"; type = "-"; value = "unlimited"; }
];
```

After `nixos-rebuild switch`, **log out and back in** for memlock limits to apply.

### Verify GPU is bound to vfio-pci

```sh
lspci -k -s 01:00.0
# "Kernel driver in use: vfio-pci"
```

### Notes

- The host loses access to the NVIDIA GPU permanently (it's bound to vfio-pci at boot).
- Host display runs on Intel integrated graphics (Mesa Intel ADL GT2) — works automatically.
- `nvidia-smi` on the host will always fail — expected.

---

## QEMU `justfile` — `base-gpu` recipe

Key differences from `base`:
- `-vga none -display none` — prevents QEMU from injecting a default VGA device (would shift PCI slots and break guest network interface naming)
- `-device vfio-pci,host=01:00.0,multifunction=on` — RTX 3050 Mobile
- `-device vfio-pci,host=01:00.1` — NVIDIA HDMI audio
- No `-audiodev`/`intel-hda` (audio goes through GPU HDMI)
- No `-cdrom` (not installing, just daily use on `base.qcow2`)

VM output goes to the **physical monitor connected to the RTX 3050**, not a QEMU window.
SSH is the primary way to interact with the VM.

---

## Debian Guest Setup

### 1. Enable non-free repos

```sh
sudo sed -i 's/main non-free-firmware/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
sudo apt update
```

### 2. Install nvidia driver

```sh
sudo apt install nvidia-driver firmware-misc-nonfree linux-headers-$(uname -r)
```

If prompted about nouveau conflict — hit OK, reboot after install.

### 3. Build DKMS module (if not built automatically)

```sh
sudo dkms status
# should show "nvidia-current/xxx: added" if not yet built

sudo dkms install nvidia-current/$(dkms status | grep nvidia | awk -F'[/:]' '{print $2}' | tr -d ' ') -k $(uname -r)
```

### 4. Load module and verify

```sh
sudo modprobe nvidia
nvidia-smi
```

### Notes

- Running `just base` (virtio GPU, no passthrough) still works after nvidia install — the nvidia module just fails to find hardware silently, and virtio-gpu handles the display.
- `just base-gpu` boots headless (no QEMU window) — use SSH to connect.
