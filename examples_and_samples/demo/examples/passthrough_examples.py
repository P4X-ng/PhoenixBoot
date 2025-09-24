#!/usr/bin/env python3
"""
VMKit Passthrough Examples

Demonstrates GPU and NVMe passthrough configurations for different use cases.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from vmkit import SecureVM, CloudImage, PassthroughManager, find_gpu, find_nvme, ssh_only_config


def gaming_vm_example():
    """
    Gaming VM with GPU + NVMe passthrough
    
    Perfect for gaming VMs that need high performance graphics and storage.
    """
    print("🎮 Gaming VM Example")
    print("=" * 50)
    
    # Find devices
    manager = PassthroughManager()
    gpu = find_gpu("nvidia")  # Find NVIDIA GPU
    nvme = find_nvme()        # Find any NVMe device
    
    if not gpu:
        print("❌ No NVIDIA GPU found for passthrough")
        return
    
    if not nvme:
        print("❌ No NVMe device found for passthrough")
        return
    
    print(f"🎯 Selected GPU: {gpu.device_name} ({gpu.pci_id})")
    print(f"🎯 Selected NVMe: {nvme.device_name} ({nvme.pci_id})")
    
    # Create gaming VM
    image = CloudImage("ubuntu-22.04-server-cloudimg-amd64.img",
                       cloud_init_config=ssh_only_config("gaming-vm"))
    
    vm = SecureVM(
        name="gaming-vm",
        memory="16G",           # Gaming needs lots of RAM
        cpus=8,                # Multiple cores for performance
        image=image,
        secure_boot=True,      # Keep security enabled
        graphics="none",       # Headless - GPU passed through
        passthrough_devices=[gpu, nvme]
    )
    
    # Validate configuration
    ready, issues = vm.validate_passthrough()
    if not ready:
        print("⚠️ Passthrough validation issues:")
        for issue in issues:
            print(f"  - {issue}")
        return
    
    print("✅ Passthrough configuration validated")
    print("\n📝 To create and start this VM:")
    print(f"vm.create().start()")
    print("\n🎮 Gaming VM Features:")
    print("  - Direct GPU access for maximum performance")
    print("  - NVMe passthrough for fast game loading")
    print("  - 16GB RAM for modern games")
    print("  - 8 CPU cores for streaming/multitasking")
    print("  - Secure Boot enabled for security")


def development_vm_example():
    """
    Development VM with NVMe passthrough
    
    Great for developers who need fast I/O but don't need GPU passthrough.
    """
    print("\n💻 Development VM Example")
    print("=" * 50)
    
    # Find NVMe device
    nvme = find_nvme()
    
    if not nvme:
        print("❌ No NVMe device found for passthrough")
        return
    
    print(f"🎯 Selected NVMe: {nvme.device_name} ({nvme.pci_id})")
    
    # Create development VM
    image = CloudImage("ubuntu-22.04-server-cloudimg-amd64.img",
                       cloud_init_config=ssh_only_config("dev-vm"))
    
    vm = SecureVM(
        name="dev-vm",
        memory="8G",            # Good for development
        cpus=6,                # Multiple cores for compilation
        image=image,
        secure_boot=True,
        graphics="spice",       # Keep graphics for GUI development
        passthrough_devices=[nvme]
    )
    
    print("✅ Development VM configured")
    print("\n💻 Development VM Features:")
    print("  - NVMe passthrough for fast compilation/builds")
    print("  - 8GB RAM for IDEs and containers")
    print("  - 6 CPU cores for parallel compilation")
    print("  - Graphics enabled for GUI development")
    print("  - Perfect for Docker, Kubernetes, etc.")


def multi_gpu_example():
    """
    Multi-GPU setup example
    
    Shows how to pass through multiple GPUs to different VMs.
    """
    print("\n🔥 Multi-GPU Setup Example")
    print("=" * 50)
    
    manager = PassthroughManager()
    gpus = manager.get_gpus()
    
    if len(gpus) < 2:
        print("❌ Need at least 2 GPUs for multi-GPU setup")
        print(f"Found {len(gpus)} GPU(s)")
        for i, gpu in enumerate(gpus):
            print(f"  GPU {i}: {gpu.device_name} ({gpu.pci_id})")
        return
    
    print(f"🎯 Found {len(gpus)} GPUs:")
    for i, gpu in enumerate(gpus):
        print(f"  GPU {i}: {gpu.device_name} ({gpu.pci_id})")
    
    # VM 1: Gaming VM with first GPU
    gaming_vm = SecureVM(
        name="gaming-vm",
        memory="16G",
        cpus=8,
        graphics="none",
        passthrough_devices=[gpus[0]]
    )
    
    # VM 2: AI/ML VM with second GPU  
    ai_vm = SecureVM(
        name="ai-vm", 
        memory="32G",           # AI needs lots of RAM
        cpus=12,               # More cores for AI workloads
        graphics="none",
        passthrough_devices=[gpus[1]]
    )
    
    print("✅ Multi-GPU configuration:")
    print(f"  🎮 Gaming VM: {gpus[0].device_name}")
    print(f"  🤖 AI/ML VM: {gpus[1].device_name}")
    print("\n🔥 Multi-GPU Benefits:")
    print("  - Dedicated GPU per VM")
    print("  - No GPU sharing conflicts")
    print("  - Maximum performance per VM")
    print("  - Run gaming + AI workloads simultaneously")


def cli_examples():
    """Show CLI command examples"""
    print("\n🖥️ CLI Examples")
    print("=" * 50)
    
    print("List available devices:")
    print("  sudo vmkit devices")
    print()
    
    print("Gaming VM with auto-detected GPU and NVMe:")
    print("  sudo vmkit create gaming-vm ubuntu-22.04.img \\")
    print("    --memory 16G --cpus 8 --gpu auto --nvme auto --graphics none")
    print()
    
    print("Development VM with specific NVMe:")
    print("  sudo vmkit create dev-vm ubuntu-22.04.img \\")
    print("    --memory 8G --cpus 6 --nvme 0000:01:00.0")
    print()
    
    print("Custom VM with multiple passthrough devices:")
    print("  sudo vmkit create custom-vm ubuntu-22.04.img \\")
    print("    --gpu 0000:01:00.0 --passthrough 0000:02:00.0 --passthrough 0000:03:00.0")


def troubleshooting_guide():
    """Show troubleshooting information"""
    print("\n🔧 Troubleshooting Guide")
    print("=" * 50)
    
    manager = PassthroughManager()
    ready, issues = manager.validate_passthrough_readiness()
    
    print("System Status:")
    if ready:
        print("  ✅ System ready for PCI passthrough")
    else:
        print("  ❌ Issues found:")
        for issue in issues:
            print(f"    - {issue}")
    
    print("\nCommon Solutions:")
    print("1. Enable IOMMU in BIOS/UEFI:")
    print("   - Intel: VT-d enabled")
    print("   - AMD: IOMMU enabled")
    
    print("\n2. Add kernel parameters:")
    print("   - Intel: intel_iommu=on iommu=pt")
    print("   - AMD: amd_iommu=on iommu=pt")
    
    print("\n3. Load VFIO modules:")
    print("   sudo modprobe vfio-pci")
    
    print("\n4. Bind devices to VFIO:")
    print("   # Find device IDs")
    print("   lspci -nn | grep -i nvidia")
    print("   # Bind to vfio-pci")
    print("   echo '10de 1b81' | sudo tee /sys/bus/pci/drivers/vfio-pci/new_id")
    
    print("\n5. Blacklist host drivers:")
    print("   # For NVIDIA GPU passthrough")
    print("   echo 'blacklist nouveau' | sudo tee -a /etc/modprobe.d/blacklist.conf")


def main():
    """Run all examples"""
    print("VMKit PCI Passthrough Examples")
    print("=" * 60)
    
    try:
        # Show system status first
        manager = PassthroughManager()
        manager.print_device_summary()
        
        # Run examples
        gaming_vm_example()
        development_vm_example() 
        multi_gpu_example()
        cli_examples()
        troubleshooting_guide()
        
    except Exception as e:
        print(f"Error running examples: {e}")
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())
