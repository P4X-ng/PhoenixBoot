# VMKit PCI Passthrough Guide

VMKit now supports **GPU and NVMe passthrough** for high-performance VMs! This enables gaming VMs, AI/ML workloads, and development environments with direct hardware access.

## 🚀 Features

- **GPU Passthrough** - Direct graphics card access for gaming, AI/ML, rendering
- **NVMe Passthrough** - High-speed storage for fast I/O, databases, compilation
- **Auto-detection** - Automatically find and configure devices
- **IOMMU Validation** - Check system compatibility and configuration
- **Secure Boot Compatible** - Passthrough works with UEFI Secure Boot
- **Multi-device Support** - Pass through multiple devices to single VM
- **Easy CLI** - Simple command-line interface for common scenarios

## 📋 System Requirements

### BIOS/UEFI Settings
- **Intel**: VT-d enabled
- **AMD**: IOMMU enabled
- **Secure Boot**: Can remain enabled

### Kernel Parameters
Add to `/etc/default/grub` GRUB_CMDLINE_LINUX:

**Intel systems:**
```bash
intel_iommu=on iommu=pt
```

**AMD systems:**
```bash
amd_iommu=on iommu=pt
```

After editing, run:
```bash
sudo update-grub
sudo reboot
```

### VFIO Modules
```bash
sudo modprobe vfio-pci
```

## 🎮 Quick Examples

### Gaming VM with GPU + NVMe
```bash
# Auto-detect devices
sudo vmkit create gaming-vm ubuntu-22.04.img \
  --memory 16G --cpus 8 \
  --gpu auto --nvme auto \
  --graphics none --start

# Specific devices
sudo vmkit create gaming-vm ubuntu-22.04.img \
  --memory 16G --cpus 8 \
  --gpu 0000:01:00.0 --nvme 0000:02:00.0 \
  --graphics none --start
```

### Development VM with NVMe
```bash
sudo vmkit create dev-vm ubuntu-22.04.img \
  --memory 8G --cpus 6 \
  --nvme auto --start
```

### Multi-GPU Setup
```bash
# Gaming VM with first GPU
sudo vmkit create gaming ubuntu-22.04.img \
  --gpu 0000:01:00.0 --memory 16G --graphics none

# AI/ML VM with second GPU  
sudo vmkit create ai-vm ubuntu-22.04.img \
  --gpu 0000:03:00.0 --memory 32G --graphics none
```

## 🐍 Python API

### Basic Usage
```python
from vmkit import SecureVM, CloudImage, find_gpu, find_nvme, ssh_only_config

# Find devices
gpu = find_gpu("nvidia")  # Auto-detect NVIDIA GPU
nvme = find_nvme()        # Auto-detect any NVMe

# Create passthrough VM
vm = SecureVM(
    name="gaming-vm",
    memory="16G",
    cpus=8,
    image=CloudImage("ubuntu-22.04.img", 
                     cloud_init_config=ssh_only_config("gaming-vm")),
    secure_boot=True,
    graphics="none",
    passthrough_devices=[gpu, nvme]
)

# Validate and create
ready, issues = vm.validate_passthrough()
if ready:
    vm.create().start()
else:
    print("Issues:", issues)
```

### Manual Device Selection
```python
from vmkit import PassthroughManager

# Scan system
manager = PassthroughManager()
manager.print_device_summary()

# Get specific devices
gpus = manager.get_gpus()
nvmes = manager.get_nvme_devices()
device = manager.get_device_by_id("0000:01:00.0")

# Create VM with selected devices
vm = SecureVM("custom-vm", passthrough_devices=[device])
```

## 🔧 CLI Commands

### List Available Devices
```bash
sudo vmkit devices
```

### VM Management with Passthrough
```bash
# Create VM
sudo vmkit create <name> <image> [passthrough options]

# Standard VM commands work the same
sudo vmkit start <name>
sudo vmkit stop <name>
sudo vmkit console <name>
sudo vmkit destroy <name>
```

### Passthrough Options
- `--gpu <pci_id|auto>` - GPU passthrough
- `--nvme <pci_id|auto>` - NVMe passthrough  
- `--passthrough <pci_id>` - Generic PCI device (can use multiple times)

## 🛠️ Troubleshooting

### Check System Status
```bash
sudo vmkit devices
```

### Common Issues

**"No IOMMU groups found"**
- Enable VT-d/IOMMU in BIOS
- Add kernel parameters and reboot
- Check: `dmesg | grep -i iommu`

**"VFIO modules not loaded"**
```bash
sudo modprobe vfio-pci
# Make persistent:
echo 'vfio-pci' | sudo tee -a /etc/modules
```

**"Device not bound to vfio-pci"**
```bash
# Find device vendor:device ID
lspci -nn | grep -i nvidia

# Bind to vfio-pci (example for NVIDIA RTX 3080)
echo '10de 2204' | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id
```

**GPU driver conflicts**
```bash
# Blacklist host GPU driver (NVIDIA example)
echo 'blacklist nouveau' | sudo tee -a /etc/modprobe.d/blacklist.conf
sudo update-initramfs -u
sudo reboot
```

### Verification Commands
```bash
# Check IOMMU enabled
dmesg | grep -i iommu

# Check VFIO modules
lsmod | grep vfio

# Check device drivers
lspci -k | grep -A3 -i nvidia

# Check IOMMU groups
find /sys/kernel/iommu_groups/ -type l
```

## 🎯 Use Cases

### Gaming
- **GPU**: Direct graphics performance, no virtualization overhead
- **NVMe**: Fast game loading, reduce stuttering
- **RAM**: 16GB+ recommended for modern games
- **CPU**: 8+ cores for streaming/background tasks

### AI/ML Development
- **GPU**: CUDA/OpenCL acceleration for training
- **NVMe**: Fast dataset loading, model checkpoints
- **RAM**: 32GB+ for large models
- **CPU**: Many cores for data preprocessing

### High-Performance Development  
- **NVMe**: Fast compilation, container builds
- **GPU**: Optional for OpenGL/compute development
- **RAM**: 8GB+ for IDEs, containers
- **CPU**: 6+ cores for parallel builds

### Content Creation
- **GPU**: Video encoding, 3D rendering
- **NVMe**: Fast media file access, cache
- **RAM**: 32GB+ for video editing
- **CPU**: Many cores for encoding

## ⚡ Performance Tips

1. **CPU Pinning**: Pin VM cores to specific physical cores
2. **Hugepages**: Use hugepages for better memory performance  
3. **NUMA**: Align devices and memory to same NUMA node
4. **I/O Threading**: Use multiple virtio queues
5. **MSI-X**: Enable MSI-X interrupts for devices

## 🔒 Security Considerations

- **IOMMU Isolation**: Devices are isolated from host kernel
- **Secure Boot**: VMKit maintains UEFI Secure Boot compatibility
- **Driver Security**: Guest drivers can't directly affect host
- **Memory Protection**: IOMMU provides memory access control
- **Device Reset**: Devices are reset between VM sessions

## 📚 Advanced Examples

See `examples/passthrough_examples.py` for detailed examples including:
- Gaming VM configuration
- Development environment setup
- Multi-GPU configurations
- Troubleshooting workflows

## 🤝 Contributing

Found issues or want to improve passthrough support? 
- Test on different hardware configurations
- Report compatibility issues  
- Submit improvements for device detection
- Add support for new device types

---

**VMKit Passthrough: Because VMs shouldn't be slow!** 🚀
