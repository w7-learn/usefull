#!/bin/bash

# ================================================
# Teljes körű KVM virtualizációs platform telepítő
# Google Cloud VM-re optimalizálva (Rocky Linux 8.x)
# Funkciók: KVM + Cockpit WebUI + VM management tools
# Szerző: AI Assistant
# Verzió: 2.0
# ================================================

set -e  # Kilépés hiba esetén

# Színes kimenet
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Logolás függvények
log_header() { echo -e "${WHITE}${1}${NC}"; }
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Root jogok ellenőrzése
if [[ $EUID -ne 0 ]]; then
   log_error "Ez a script root jogokkal kell futtatni!"
   echo "Használat: sudo bash $0"
   exit 1
fi

# Banner
clear
log_header "================================================"
log_header "🚀 TELJES KÖRŰ KVM VIRTUALIZÁCIÓS PLATFORM"
log_header "================================================"
log_header "🎯 Optimalizálva Google Cloud nested virtualizációhoz"
log_header "📦 Tartalmazza: KVM + Cockpit WebUI + Management Tools"
log_header "================================================"
echo ""

# Rendszer információk
log_step "Rendszer információk összegyűjtése..."
HOSTNAME=$(hostname)
SERVER_IP=$(hostname -I | awk '{print $1}')
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
TOTAL_CPU=$(nproc)
OS_VERSION=$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)

echo ""
log_info "🖥️  Szerver: $HOSTNAME"
log_info "🌍 IP cím: $SERVER_IP"
log_info "💾 RAM: ${TOTAL_RAM}MB (~$((TOTAL_RAM/1024))GB)"
log_info "⚡ CPU magok: $TOTAL_CPU"
log_info "🐧 OS: $OS_VERSION"
echo ""

# Megerősítés
read -p "$(echo -e ${CYAN}"Folytatod a telepítést? (y/N): "${NC})" confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    log_warn "Telepítés megszakítva."
    exit 0
fi

# ================================================
# 1. RENDSZER FRISSÍTÉSE
# ================================================
log_header "📦 1. RENDSZER FRISSÍTÉSE"
log_step "DNF package manager frissítése..."
dnf update -y

log_step "EPEL repository hozzáadása..."
dnf install -y epel-release

# ================================================
# 2. CPU VIRTUALIZÁCIÓ ELLENŐRZÉSE
# ================================================
log_header "⚡ 2. CPU VIRTUALIZÁCIÓ ELLENŐRZÉSE"

log_step "CPU virtualization támogatás ellenőrzése..."
CPU_VIRT=$(egrep -c '(vmx|svm)' /proc/cpuinfo || true)
if [ "$CPU_VIRT" -eq 0 ]; then
    log_error "❌ CPU nem támogatja a virtualizációt!"
    log_error "Google Cloud VM-en engedélyezd a nested virtualizációt:"
    log_error "gcloud compute instances stop $HOSTNAME"
    log_error "gcloud compute instances update $HOSTNAME --enable-nested-virtualization"
    log_error "gcloud compute instances start $HOSTNAME"
    exit 1
else
    log_success "✅ CPU virtualization támogatott ($CPU_VIRT mag)"
fi

# CPU típus meghatározása
if grep -q "Intel" /proc/cpuinfo; then
    CPU_TYPE="intel"
    log_info "🔧 Intel CPU detected"
elif grep -q "AMD" /proc/cpuinfo; then
    CPU_TYPE="amd"
    log_info "🔧 AMD CPU detected"
else
    log_warn "⚠️  Ismeretlen CPU típus"
    CPU_TYPE="unknown"
fi

# ================================================
# 3. KVM ÉS VIRTUALIZÁCIÓS CSOMAGOK TELEPÍTÉSE
# ================================================
log_header "📦 3. KVM VIRTUALIZÁCIÓS PLATFORM TELEPÍTÉSE"

log_step "Virtualization Host csomagcsoport telepítése..."
dnf groupinstall -y "Virtualization Host"

log_step "További KVM és management eszközök telepítése..."
dnf install -y \
    qemu-kvm \
    libvirt \
    libvirt-daemon-config-network \
    libvirt-daemon-kvm \
    virt-install \
    virt-top \
    virt-viewer \
    virt-manager \
    libguestfs-tools \
    bridge-utils \
    dnsmasq \
    ebtables

# ================================================
# 4. COCKPIT WEBUI TELEPÍTÉSE
# ================================================
log_header "🌐 4. COCKPIT WEB MANAGEMENT TELEPÍTÉSE"

log_step "Cockpit és modulok telepítése..."
dnf install -y \
    cockpit \
    cockpit-machines \
    cockpit-storaged \
    cockpit-networkmanager \
    cockpit-packagekit \
    cockpit-selinux \
    cockpit-sosreport

# ================================================
# 5. NESTED VIRTUALIZÁCIÓ OPTIMALIZÁCIÓ
# ================================================
log_header "🔧 5. NESTED VIRTUALIZÁCIÓ OPTIMALIZÁCIÓ"

log_step "GRUB kernel paraméterek optimalizálása..."
# Backup eredeti GRUB config
cp /etc/default/grub /etc/default/grub.backup

# GRUB paraméterek hozzáadása
if ! grep -q "intel_iommu=on" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="intel_iommu=on iommu=pt kvm.ignore_msrs=1 kvm.report_ignored_msrs=0 /' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    log_info "✅ GRUB kernel paraméterek frissítve"
fi

log_step "KVM modulok optimalizálása nested virtualizációhoz..."
# KVM modul konfiguráció
cat > /etc/modprobe.d/kvm-nested.conf << EOF
# KVM nested virtualization optimalizáció Google Cloud-hoz
options kvm ignore_msrs=1 report_ignored_msrs=0
EOF

if [ "$CPU_TYPE" = "intel" ]; then
    echo 'options kvm_intel nested=1 enable_shadow_vmcs=1 enable_apicv=1 ept=1' >> /etc/modprobe.d/kvm-nested.conf
elif [ "$CPU_TYPE" = "amd" ]; then
    echo 'options kvm_amd nested=1' >> /etc/modprobe.d/kvm-nested.conf
fi

# CPU governor beállítása teljesítményre
log_step "CPU governor beállítása performance módra..."
echo 'performance' | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null 2>&1 || true

# ================================================
# 6. HÁLÓZATI KONFIGURÁCIÓ
# ================================================
log_header "🌐 6. HÁLÓZATI KONFIGURÁCIÓ"

log_step "Default bridge hálózat konfigurálása..."
# Libvirt default network indítása
systemctl enable --now libvirtd
virsh net-autostart default
virsh net-start default 2>/dev/null || true

log_step "Bridge hálózat létrehozása VM-ekhez..."
# Custom bridge létrehozása (opcionális)
cat > /tmp/vm-bridge.xml << 'EOF'
<network>
  <name>vm-bridge</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='vm-br0' stp='on' delay='0'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.100' end='192.168.100.200'/>
    </dhcp>
  </ip>
</network>
EOF

virsh net-define /tmp/vm-bridge.xml
virsh net-autostart vm-bridge
virsh net-start vm-bridge 2>/dev/null || true

# ================================================
# 7. SZOLGÁLTATÁSOK KONFIGURÁLÁSA
# ================================================
log_header "🔧 7. SZOLGÁLTATÁSOK KONFIGURÁLÁSA"

log_step "Libvirt szolgáltatások indítása..."
systemctl enable --now libvirtd
systemctl enable --now virtlogd
systemctl enable --now virtlockd

log_step "Cockpit szolgáltatás indítása..."
systemctl enable --now cockpit.socket

# ================================================
# 8. FELHASZNÁLÓI JOGOK BEÁLLÍTÁSA
# ================================================
log_header "👤 8. FELHASZNÁLÓI JOGOK BEÁLLÍTÁSA"

# Aktuális nem-root felhasználó meghatározása
CURRENT_USER=$(logname 2>/dev/null || echo $SUDO_USER || echo "saborobag")

log_step "Felhasználó ($CURRENT_USER) hozzáadása virtualizációs csoportokhoz..."
usermod -aG libvirt $CURRENT_USER
usermod -aG kvm $CURRENT_USER
usermod -aG qemu $CURRENT_USER

# ================================================
# 9. FIREWALL KONFIGURÁCIÓ
# ================================================
log_header "🔥 9. FIREWALL KONFIGURÁCIÓ"

log_step "Firewall szabályok beállítása..."
# Cockpit web interface
firewall-cmd --permanent --add-service=cockpit
# Libvirt szolgáltatások
firewall-cmd --permanent --add-service=libvirt
# VNC portok VM-ekhez
firewall-cmd --permanent --add-port=5900-5950/tcp
# SSH (ha nincs engedélyezve)
firewall-cmd --permanent --add-service=ssh

# Custom portok specifikus VM-ekhez
firewall-cmd --permanent --add-port=8080-8090/tcp  # Web alkalmazások
firewall-cmd --permanent --add-port=3389/tcp       # RDP
firewall-cmd --permanent --add-port=22-2222/tcp    # SSH range

firewall-cmd --reload
log_success "✅ Firewall konfiguráció kész"

# ================================================
# 10. VM MANAGEMENT SCRIPTEK LÉTREHOZÁSA
# ================================================
log_header "📜 10. VM MANAGEMENT SCRIPTEK"

log_step "VM management scriptek létrehozása..."

# VM létrehozó script
cat > /usr/local/bin/create-vm << 'EOF'
#!/bin/bash
# VM létrehozó script
# Használat: create-vm <név> <ram_gb> <cpu> <disk_gb> <iso_path>

VM_NAME="${1:-test-vm}"
RAM_GB="${2:-4}"
CPU_COUNT="${3:-2}"
DISK_SIZE="${4:-20}"
ISO_PATH="${5}"

if [ -z "$ISO_PATH" ]; then
    echo "Használat: create-vm <név> <ram_gb> <cpu> <disk_gb> <iso_path>"
    echo "Példa: create-vm ubuntu-server 4 2 20 /tmp/ubuntu.iso"
    exit 1
fi

RAM_MB=$((RAM_GB * 1024))

echo "🚀 VM létrehozása:"
echo "  Név: $VM_NAME"
echo "  RAM: ${RAM_GB}GB"
echo "  CPU: $CPU_COUNT vCPU"
echo "  Disk: ${DISK_SIZE}GB"
echo "  ISO: $ISO_PATH"

virt-install \
    --name="$VM_NAME" \
    --memory="$RAM_MB" \
    --vcpus="$CPU_COUNT" \
    --cpu host-passthrough \
    --disk size="$DISK_SIZE",format=qcow2,cache=writeback \
    --cdrom="$ISO_PATH" \
    --network network=default,model=virtio \
    --graphics vnc,listen=0.0.0.0 \
    --console pty,target_type=serial \
    --boot cdrom,hd \
    --os-variant=detect \
    --noautoconsole

echo ""
echo "✅ VM létrehozva: $VM_NAME"
echo "🖥️  VNC kapcsolat: $(hostname -I | awk '{print $1}'):590X"
echo "🌐 Cockpit: https://$(hostname -I | awk '{print $1}'):9090"
EOF

chmod +x /usr/local/bin/create-vm

# VM listázó script
cat > /usr/local/bin/list-vms << 'EOF'
#!/bin/bash
# VM listázó és információs script

echo "================================================"
echo "🖥️  VIRTUÁLIS GÉPEK ÁTTEKINTÉSE"
echo "================================================"

echo ""
echo "📊 RENDSZER ERŐFORRÁSOK:"
echo "├── CPU magok: $(nproc)"
echo "├── Összes RAM: $(free -h | awk '/^Mem:/{print $2}')"
echo "├── Szabad RAM: $(free -h | awk '/^Mem:/{print $7}')"
echo "└── Disk szabad: $(df -h / | awk 'NR==2{print $4}')"

echo ""
echo "🖱️  FUTÓ VM-EK:"
VMS_RUNNING=$(virsh list --state-running --name | wc -l)
VMS_TOTAL=$(virsh list --all --name | grep -v "^$" | wc -l)
echo "├── Futó: $VMS_RUNNING"
echo "└── Összes: $VMS_TOTAL"

echo ""
virsh list --all

echo ""
echo "🌐 HÁLÓZATOK:"
virsh net-list --all

echo ""
echo "💾 STORAGE POOLOK:"
virsh pool-list --all

if [ $VMS_TOTAL -gt 0 ]; then
    echo ""
    echo "📋 VM RÉSZLETEK:"
    for vm in $(virsh list --all --name | grep -v "^$"); do
        if [ ! -z "$vm" ]; then
            state=$(virsh domstate "$vm" 2>/dev/null)
            ram=$(virsh dominfo "$vm" 2>/dev/null | grep "Max memory" | awk '{print $3}')
            cpu=$(virsh dominfo "$vm" 2>/dev/null | grep "CPU(s)" | awk '{print $2}')
            ram_gb=$((ram / 1024 / 1024))
            echo "├── $vm: ${cpu} vCPU, ${ram_gb}GB RAM [$state]"
        fi
    done
fi

echo ""
echo "🔗 HASZNOS PARANCSOK:"
echo "├── VM indítás: virsh start <vm-név>"
echo "├── VM leállítás: virsh shutdown <vm-név>"
echo "├── VM törlés: virsh destroy <vm-név> && virsh undefine <vm-név> --remove-all-storage"
echo "├── VNC port: virsh vncdisplay <vm-név>"
echo "└── Cockpit WebUI: https://$(hostname -I | awk '{print $1}'):9090"
EOF

chmod +x /usr/local/bin/list-vms

# ISO letöltő script
cat > /usr/local/bin/download-iso << 'EOF'
#!/bin/bash
# Népszerű ISO-k letöltő script

ISO_DIR="/var/lib/libvirt/images/iso"
mkdir -p "$ISO_DIR"

echo "📥 ISO LETÖLTŐ ESZKÖZ"
echo "====================="
echo ""
echo "Választható ISO-k:"
echo "1. Ubuntu Server 22.04 LTS"
echo "2. Ubuntu Desktop 22.04 LTS"  
echo "3. CentOS Stream 9"
echo "4. Rocky Linux 9"
echo "5. Debian 12"
echo "6. Alpine Linux"
echo "7. Egyedi URL"
echo ""

read -p "Válassz (1-7): " choice

case $choice in
    1)
        URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso"
        FILENAME="ubuntu-22.04-server.iso"
        ;;
    2)
        URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.3-desktop-amd64.iso"
        FILENAME="ubuntu-22.04-desktop.iso"
        ;;
    3)
        URL="https://mirror.stream.centos.org/9-stream/BaseOS/x86_64/iso/CentOS-Stream-9-latest-x86_64-dvd1.iso"
        FILENAME="centos-stream-9.iso"
        ;;
    4)
        URL="https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.3-x86_64-minimal.iso"
        FILENAME="rocky-linux-9.iso"
        ;;
    5)
        URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.2.0-amd64-netinst.iso"
        FILENAME="debian-12.iso"
        ;;
    6)
        URL="https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/x86_64/alpine-standard-3.18.4-x86_64.iso"
        FILENAME="alpine-linux.iso"
        ;;
    7)
        read -p "Add meg az ISO URL-t: " URL
        read -p "Add meg a fájlnevet: " FILENAME
        ;;
    *)
        echo "Érvénytelen választás!"
        exit 1
        ;;
esac

echo ""
echo "📥 Letöltés: $FILENAME"
echo "🌍 URL: $URL"
echo "📁 Cél: $ISO_DIR/$FILENAME"
echo ""

cd "$ISO_DIR"
wget -O "$FILENAME" "$URL"

if [ $? -eq 0 ]; then
    echo "✅ Letöltés kész: $ISO_DIR/$FILENAME"
    echo "🚀 VM létrehozás: create-vm myvm 4 2 20 $ISO_DIR/$FILENAME"
else
    echo "❌ Letöltés sikertelen!"
fi
EOF

chmod +x /usr/local/bin/download-iso

# ================================================
# 11. TELEPÍTÉS BEFEJEZÉSE ÉS INFORMÁCIÓK
# ================================================
log_header "🎉 11. TELEPÍTÉS BEFEJEZÉSE"

log_step "Nested virtualizáció ellenőrzése..."
# KVM modulok újratöltése
if [ "$CPU_TYPE" = "intel" ]; then
    modprobe -r kvm_intel 2>/dev/null || true
    modprobe kvm_intel
elif [ "$CPU_TYPE" = "amd" ]; then
    modprobe -r kvm_amd 2>/dev/null || true
    modprobe kvm_amd
fi
modprobe kvm

# Nested support ellenőrzése
if [ -f /sys/module/kvm_intel/parameters/nested ]; then
    NESTED_STATUS=$(cat /sys/module/kvm_intel/parameters/nested)
    log_info "🔧 Intel KVM nested: $NESTED_STATUS"
elif [ -f /sys/module/kvm_amd/parameters/nested ]; then
    NESTED_STATUS=$(cat /sys/module/kvm_amd/parameters/nested)
    log_info "🔧 AMD KVM nested: $NESTED_STATUS"
fi

# Path frissítése
export PATH="/usr/local/bin:$PATH"
echo 'export PATH="/usr/local/bin:$PATH"' >> /home/$CURRENT_USER/.bashrc

log_success "✅ KVM virtualizációs platform sikeresen telepítve!"

# ================================================
# ÖSSZEFOGLALÓ ÉS ÚTMUTATÓK
# ================================================
clear
log_header "================================================"
log_header "🎉 KVM VIRTUALIZÁCIÓS PLATFORM TELEPÍTVE!"
log_header "================================================"
echo ""

log_header "📊 RENDSZER ÖSSZEFOGLALÓ:"
echo "🖥️  Szerver: $HOSTNAME ($SERVER_IP)"
echo "💾 Elérhető RAM VM-ekhez: ~$((TOTAL_RAM - 2048))MB"
echo "⚡ CPU magok VM-ekhez: $((TOTAL_CPU - 1))"
echo "🔧 Nested virtualizáció: Engedélyezve"
echo ""

log_header "🌐 WEBES FELÜLETEK:"
echo "🎛️  Cockpit Management: https://$SERVER_IP:9090"
echo "   └── Felhasználó: $CURRENT_USER"
echo "   └── Jelszó: (rendszer jelszó)"
echo ""

log_header "🔧 PARANCSSOR ESZKÖZÖK:"
echo "🚀 VM létrehozás: create-vm <név> <ram_gb> <cpu> <disk_gb> <iso_path>"
echo "📋 VM-ek listája: list-vms"
echo "📥 ISO letöltés: download-iso"
echo "🖱️  VM kezelés: virsh list --all"
echo ""

log_header "📥 PÉLDA VM LÉTREHOZÁS:"
echo "1️⃣  ISO letöltése:"
echo "   download-iso"
echo ""
echo "2️⃣  VM létrehozása:"
echo "   create-vm ubuntu-server 4 2 20 /var/lib/libvirt/images/iso/ubuntu-22.04-server.iso"
echo ""
echo "3️⃣  VNC kapcsolat:"
echo "   SSH tunnel: ssh -L 5900:localhost:5900 $CURRENT_USER@$SERVER_IP"
echo "   VNC cím: localhost:5900"
echo ""

log_header "🔄 ÚJRAINDÍTÁS SZÜKSÉGES:"
log_warn "⚠️  A kernel paraméterek aktiválásához újraindítás javasolt!"
echo ""
read -p "$(echo -e ${CYAN}"Újraindítod most a rendszert? (y/N): "${NC})" reboot_now

if [[ $reboot_now =~ ^[Yy]$ ]]; then
    log_info "🔄 Rendszer újraindítása 10 másodperc múlva..."
    log_info "📱 Kapcsolódj újra SSH-val a restart után!"
    sleep 10
    reboot
else
    log_warn "⚠️  Ne felejts el újraindítani később: sudo reboot"
fi

log_header "================================================"
log_success "🎉 TELEPÍTÉS BEFEJEZVE! SZUPER VIRTUALIZÁLÁS! 🚀"
log_header "================================================"