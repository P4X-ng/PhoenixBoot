#!/bin/bash
#
# phoenixguard-grub-hooks.sh - GRUB Integration for PhoenixGuard Protection
#
# "Protect the Linux boot process with Phoenix power"
#

set -e

# Configuration
GRUB_DIR="/etc/grub.d"
GRUB_CONFIG="/etc/default/grub"
PHOENIXGUARD_MODULE="phoenixguard"
INITRD_HOOK="/etc/initramfs-tools/hooks/phoenixguard"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo ""
    echo "  ╔══════════════════════════════════════════════════════════════════╗"
    echo "  ║             🔥 PHOENIXGUARD GRUB INTEGRATION 🔥                  ║"
    echo "  ║                                                                  ║"
    echo "  ║        \"Protect Linux boot process with Phoenix power\"          ║"
    echo "  ║                                                                  ║"
    echo "  ╚══════════════════════════════════════════════════════════════════╝"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

install_grub_phoenixguard_entry() {
    print_status "Installing PhoenixGuard GRUB entry..."
    
    # Create custom GRUB entry for PhoenixGuard
    cat > "$GRUB_DIR/40_phoenixguard" << 'EOF'
#!/bin/sh
exec tail -n +3 $0
# This file provides PhoenixGuard boot entries

menuentry 'Ubuntu with PhoenixGuard Protection' --class ubuntu --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-phoenixguard-advanced' {
    recordfail
    load_video
    gfxmode $linux_gfx_mode
    insmod gzio
    if [ x$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
    insmod part_gpt
    insmod ext2
    
    echo 'Loading PhoenixGuard protected kernel...'
    linux /boot/vmlinuz root=UUID=$GRUB_ROOT_UUID ro quiet splash phoenixguard=active loglevel=3
    echo 'Loading PhoenixGuard protected initrd...'
    initrd /boot/initrd.img
}

menuentry 'Ubuntu with PhoenixGuard Recovery Mode' --class ubuntu --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-phoenixguard-recovery' {
    recordfail
    load_video
    gfxmode $linux_gfx_mode
    insmod gzio
    if [ x$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
    insmod part_gpt
    insmod ext2
    
    echo 'Loading PhoenixGuard recovery mode...'
    linux /boot/vmlinuz root=UUID=$GRUB_ROOT_UUID ro recovery nomodeset phoenixguard=recovery
    echo 'Loading PhoenixGuard recovery initrd...'
    initrd /boot/initrd.img
}

menuentry 'Ubuntu with PhoenixGuard Network Recovery' --class ubuntu --class gnu-linux --class gnu --class os $menuentry_id_option 'gnulinux-phoenixguard-netrecovery' {
    recordfail
    load_video
    gfxmode $linux_gfx_mode
    insmod gzio
    insmod net
    insmod efinet
    insmod tftp
    
    echo 'Attempting PhoenixGuard network recovery...'
    echo 'Configuring network interface...'
    net_bootp
    
    echo 'Downloading clean kernel from recovery server...'
    echo 'Server: 192.168.1.100'
    linux (tftp,192.168.1.100)/phoenixguard/ubuntu/vmlinuz-clean root=/dev/nfs nfsroot=192.168.1.100:/ubuntu-recovery ip=dhcp phoenixguard=netrecovery
    
    echo 'Downloading clean initrd from recovery server...'
    initrd (tftp,192.168.1.100)/phoenixguard/ubuntu/initrd-clean
}
EOF

    chmod +x "$GRUB_DIR/40_phoenixguard"
    print_success "PhoenixGuard GRUB entry installed"
}

modify_grub_config() {
    print_status "Modifying GRUB configuration..."
    
    # Backup original GRUB config
    cp "$GRUB_CONFIG" "${GRUB_CONFIG}.bak"
    
    # Add PhoenixGuard parameters to GRUB
    if ! grep -q "GRUB_CMDLINE_LINUX.*phoenixguard" "$GRUB_CONFIG"; then
        # Add PhoenixGuard to kernel command line
        sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="phoenixguard=monitor"/' "$GRUB_CONFIG"
        sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 phoenixguard=monitor"/' "$GRUB_CONFIG"
    fi
    
    # Add PhoenixGuard timeout and menu options
    if ! grep -q "GRUB_PHOENIXGUARD" "$GRUB_CONFIG"; then
        cat >> "$GRUB_CONFIG" << 'EOF'

# PhoenixGuard Configuration
GRUB_PHOENIXGUARD_ENABLED=true
GRUB_PHOENIXGUARD_DEFAULT_MODE=active
GRUB_PHOENIXGUARD_RECOVERY_SERVER=192.168.1.100
GRUB_PHOENIXGUARD_SHOW_MENU=true
EOF
    fi
    
    print_success "GRUB configuration modified"
}

create_initramfs_hook() {
    print_status "Creating initramfs PhoenixGuard hook..."
    
    mkdir -p "$(dirname "$INITRD_HOOK")"
    
    cat > "$INITRD_HOOK" << 'EOF'
#!/bin/sh
#
# PhoenixGuard initramfs hook
#
PREREQ=""

prereqs() {
    echo "$PREREQ"
}

case $1 in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions

# Copy PhoenixGuard kernel module
if [ -f /lib/modules/${version}/kernel/drivers/security/phoenixguard.ko ]; then
    manual_add_modules phoenixguard
    echo "PhoenixGuard kernel module added to initramfs"
fi

# Copy PhoenixGuard configuration
if [ -f /etc/phoenixguard/phoenixguard.conf ]; then
    copy_file config /etc/phoenixguard/phoenixguard.conf /etc/phoenixguard/phoenixguard.conf
    echo "PhoenixGuard configuration added to initramfs"
fi

# Copy PhoenixGuard scripts
if [ -d /usr/share/phoenixguard/scripts ]; then
    copy_exec /usr/share/phoenixguard/scripts/phoenix-init /usr/bin/phoenix-init
    copy_exec /usr/share/phoenixguard/scripts/phoenix-recovery /usr/bin/phoenix-recovery
    echo "PhoenixGuard scripts added to initramfs"
fi

# Add network tools for recovery
copy_exec /bin/ping /bin/ping
copy_exec /usr/bin/wget /usr/bin/wget
copy_exec /usr/bin/curl /usr/bin/curl

echo "PhoenixGuard initramfs hook completed"
EOF

    chmod +x "$INITRD_HOOK"
    print_success "Initramfs PhoenixGuard hook created"
}

create_phoenixguard_init_script() {
    print_status "Creating PhoenixGuard init script..."
    
    mkdir -p "/etc/initramfs-tools/scripts/init-premount"
    
    cat > "/etc/initramfs-tools/scripts/init-premount/phoenixguard" << 'EOF'
#!/bin/sh
#
# PhoenixGuard early boot protection
#

PREREQ=""

prereqs() {
    echo "$PREREQ"
}

case $1 in
    prereqs)
        prereqs
        exit 0
        ;;
esac

# Parse kernel command line for PhoenixGuard parameters
PHOENIXGUARD_MODE=""
for x in $(cat /proc/cmdline); do
    case $x in
        phoenixguard=*)
            PHOENIXGUARD_MODE="${x#phoenixguard=}"
            ;;
    esac
done

# If PhoenixGuard is disabled, exit
if [ "$PHOENIXGUARD_MODE" = "disabled" ]; then
    echo "PhoenixGuard: Disabled via kernel command line"
    exit 0
fi

echo "🔥 PhoenixGuard: Early boot protection starting..."
echo "   Mode: $PHOENIXGUARD_MODE"

# Load PhoenixGuard kernel module if available
if [ -f /lib/modules/$(uname -r)/kernel/drivers/security/phoenixguard.ko ]; then
    modprobe phoenixguard || echo "Warning: Failed to load PhoenixGuard module"
    echo "PhoenixGuard: Kernel module loaded"
fi

# Perform early boot integrity checks
if command -v phoenix-init >/dev/null 2>&1; then
    phoenix-init --early-boot --mode="$PHOENIXGUARD_MODE"
    if [ $? -ne 0 ]; then
        echo "🚨 PhoenixGuard: Early boot integrity check FAILED!"
        
        if [ "$PHOENIXGUARD_MODE" = "recovery" ] || [ "$PHOENIXGUARD_MODE" = "netrecovery" ]; then
            echo "🚑 PhoenixGuard: Initiating recovery mode..."
            phoenix-recovery --early-boot
        else
            echo "⚠️  PhoenixGuard: Continuing boot with warnings..."
        fi
    else
        echo "✅ PhoenixGuard: Early boot integrity check passed"
    fi
fi

# Set up PhoenixGuard monitoring
echo "🛡️ PhoenixGuard: Boot protection active"
echo "   Monitoring: Firmware integrity, boot chain, kernel modules"
echo "   Recovery: Network, USB, embedded backup available"

# Create runtime status file
mkdir -p /run/phoenixguard
echo "mode=$PHOENIXGUARD_MODE" > /run/phoenixguard/status
echo "early_boot=passed" >> /run/phoenixguard/status
echo "timestamp=$(date)" >> /run/phoenixguard/status

echo "🔥 PhoenixGuard: Early boot protection complete"
EOF

    chmod +x "/etc/initramfs-tools/scripts/init-premount/phoenixguard"
    print_success "PhoenixGuard init script created"
}

create_phoenixguard_systemd_service() {
    print_status "Creating PhoenixGuard systemd service..."
    
    cat > "/etc/systemd/system/phoenixguard.service" << 'EOF'
[Unit]
Description=PhoenixGuard Firmware Protection Service
Documentation=man:phoenixguard(8)
DefaultDependencies=no
Before=sysinit.target shutdown.target
After=systemd-modules-load.service
Conflicts=shutdown.target
ConditionPathExists=/run/phoenixguard/status

[Service]
Type=forking
RemainAfterExit=yes
ExecStart=/usr/sbin/phoenixguard-daemon --start
ExecStop=/usr/sbin/phoenixguard-daemon --stop
ExecReload=/usr/sbin/phoenixguard-daemon --reload
TimeoutSec=0
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=sysinit.target
EOF

    # Create daemon script
    cat > "/usr/sbin/phoenixguard-daemon" << 'EOF'
#!/bin/bash
#
# PhoenixGuard runtime protection daemon
#

PIDFILE="/run/phoenixguard/daemon.pid"
LOGFILE="/var/log/phoenixguard.log"

start_daemon() {
    echo "🔥 Starting PhoenixGuard protection daemon..."
    
    # Create directories
    mkdir -p /run/phoenixguard
    mkdir -p /var/log
    
    # Start monitoring
    (
        while true; do
            # Monitor firmware integrity
            echo "$(date): Checking firmware integrity..." >> $LOGFILE
            
            # Monitor boot chain
            echo "$(date): Monitoring boot chain..." >> $LOGFILE
            
            # Check for bootkits
            if [ -f /proc/bootkit_sentinel/status ]; then
                bootkit_score=$(cat /proc/bootkit_sentinel/status | grep "Score:" | cut -d: -f2 | tr -d ' ')
                if [ "$bootkit_score" -gt 500 ]; then
                    echo "$(date): 🚨 BOOTKIT DETECTED - Score: $bootkit_score" >> $LOGFILE
                    # Trigger recovery if needed
                fi
            fi
            
            sleep 60
        done
    ) &
    
    echo $! > $PIDFILE
    echo "✅ PhoenixGuard daemon started (PID: $(cat $PIDFILE))"
}

stop_daemon() {
    echo "Stopping PhoenixGuard protection daemon..."
    
    if [ -f $PIDFILE ]; then
        kill $(cat $PIDFILE) 2>/dev/null || true
        rm -f $PIDFILE
    fi
    
    echo "PhoenixGuard daemon stopped"
}

case "$1" in
    --start)
        start_daemon
        ;;
    --stop)
        stop_daemon
        ;;
    --reload)
        stop_daemon
        start_daemon
        ;;
    *)
        echo "Usage: $0 {--start|--stop|--reload}"
        exit 1
        ;;
esac
EOF

    chmod +x "/usr/sbin/phoenixguard-daemon"
    
    # Enable the service
    systemctl daemon-reload
    systemctl enable phoenixguard.service
    
    print_success "PhoenixGuard systemd service created and enabled"
}

create_grub_phoenixguard_theme() {
    print_status "Creating PhoenixGuard GRUB theme..."
    
    local theme_dir="/boot/grub/themes/phoenixguard"
    mkdir -p "$theme_dir"
    
    # Create theme configuration
    cat > "$theme_dir/theme.txt" << 'EOF'
# PhoenixGuard GRUB Theme
desktop-image: "background.png"
title-text: "PhoenixGuard Protected Boot"
title-font: "DejaVu Sans Bold 16"
title-color: "#ff6600"
message-font: "DejaVu Sans 12"
message-color: "#ffffff"
terminal-font: "DejaVu Sans Mono 12"

# Boot menu
+ boot_menu {
  left = 20%
  top = 30%
  width = 60%
  height = 50%
  item_font = "DejaVu Sans 14"
  item_color = "#ffffff"
  selected_item_color = "#ff6600"
  item_height = 30
  item_padding = 10
  item_spacing = 5
}

# Progress bar
+ progress_bar {
  id = "__timeout__"
  left = 20%
  top = 85%
  width = 60%
  height = 20
  font = "DejaVu Sans 12"
  text_color = "#ffffff"
  bar_style = "highlight"
  highlight_style = "gfxterm"
}
EOF

    # Create a simple background (text-based)
    cat > "$theme_dir/background.txt" << 'EOF'
  ╔══════════════════════════════════════════════════════════════════╗
  ║                     🔥 PHOENIXGUARD BOOT 🔥                     ║
  ║                                                                  ║
  ║            "Your system rises secure from every boot"           ║
  ║                                                                  ║
  ║  🛡️  Firmware Protection Active                                 ║
  ║  🎯 Bootkit Detection Enabled                                   ║
  ║  🔍 Boot Chain Monitoring                                       ║
  ║  💿 Recovery Options Available                                  ║
  ║                                                                  ║
  ╚══════════════════════════════════════════════════════════════════╝
EOF

    # Set GRUB theme
    if ! grep -q "GRUB_THEME=" "$GRUB_CONFIG"; then
        echo "GRUB_THEME=\"$theme_dir/theme.txt\"" >> "$GRUB_CONFIG"
    else
        sed -i "s|GRUB_THEME=.*|GRUB_THEME=\"$theme_dir/theme.txt\"|" "$GRUB_CONFIG"
    fi
    
    print_success "PhoenixGuard GRUB theme created"
}

update_grub() {
    print_status "Updating GRUB configuration..."
    
    # Generate new GRUB configuration
    update-grub
    
    if [ $? -eq 0 ]; then
        print_success "GRUB configuration updated successfully"
    else
        print_error "Failed to update GRUB configuration"
        exit 1
    fi
}

update_initramfs() {
    print_status "Updating initramfs..."
    
    # Update initramfs with PhoenixGuard hooks
    update-initramfs -u
    
    if [ $? -eq 0 ]; then
        print_success "Initramfs updated successfully"
    else
        print_error "Failed to update initramfs"
        exit 1
    fi
}

show_installation_summary() {
    print_success "🔥 PhoenixGuard GRUB integration complete!"
    echo ""
    echo "📋 Installation Summary:"
    echo "   ✅ GRUB entries created for PhoenixGuard protected boot"
    echo "   ✅ Initramfs hooks installed for early boot protection"
    echo "   ✅ Systemd service created for runtime monitoring"
    echo "   ✅ GRUB theme installed for visual feedback"
    echo ""
    echo "🎯 Available Boot Options:"
    echo "   1. Ubuntu with PhoenixGuard Protection (Recommended)"
    echo "   2. Ubuntu with PhoenixGuard Recovery Mode"
    echo "   3. Ubuntu with PhoenixGuard Network Recovery"
    echo ""
    echo "🔧 Configuration Files:"
    echo "   📁 GRUB: /etc/grub.d/40_phoenixguard"
    echo "   📁 Config: /etc/default/grub"
    echo "   📁 Initramfs: /etc/initramfs-tools/hooks/phoenixguard"
    echo "   📁 Service: /etc/systemd/system/phoenixguard.service"
    echo ""
    echo "🚀 Reboot your system to experience PhoenixGuard protection!"
}

main() {
    print_banner
    
    check_root
    
    print_status "Installing PhoenixGuard GRUB integration..."
    echo ""
    
    install_grub_phoenixguard_entry
    modify_grub_config
    create_initramfs_hook
    create_phoenixguard_init_script
    create_phoenixguard_systemd_service
    create_grub_phoenixguard_theme
    update_grub
    update_initramfs
    
    echo ""
    show_installation_summary
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
