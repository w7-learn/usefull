#!/bin/bash

# Proxmox ISO feltöltő és telepítő script
# Használat: bash proxmox-iso-install.sh

echo "================================================"
echo "Proxmox ISO feltöltő és telepítő"
echo "================================================"

# Színes kimenet
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 1. ISO feltöltési lehetőségek
echo ""
echo "ISO feltöltési módok:"
echo "1. SCP-vel (ajánlott)"
echo "2. Wget-tel letöltés"
echo "3. Már van ISO a rendszeren"
echo ""
read -p "Válassz (1-3): " choice

case $choice in
    1)
        echo ""
        log_info "SCP feltöltés útmutatója:"
        echo "Local gépeden futtasd:"
        echo "scp proxmox-ve_9.0-1.iso $(whoami)@$(hostname -I | awk '{print $1}'):/tmp/"
        echo ""
        read -p "Nyomj ENTER-t a feltöltés után..."
        ISO_PATH="/tmp/proxmox-ve_9.0-1.iso"
        ;;
    2)
        log_info "Proxmox ISO letöltése..."
        cd /tmp
        wget -O proxmox-ve_9.0-1.iso "https://www.proxmox.com/en/downloads/item/proxmox-ve-9-0-iso-installer"
        ISO_PATH="/tmp/proxmox-ve_9.0-1.iso"
        ;;
    3)
        read -p "Add meg az ISO teljes elérési útját: " ISO_PATH
        ;;
    *)
        log_error "Érvénytelen választás!"
        exit 1
        ;;
esac

# ISO ellenőrzése
if [ ! -f "$ISO_PATH" ]; then
    log_error "ISO fájl nem található: $ISO_PATH"
    exit 1
fi

log_info "ISO megtalálva: $ISO_PATH"
ISO_SIZE=$(du -h "$ISO_PATH" | cut -f1)
log_info "ISO méret: $ISO_SIZE"

# 2. VM paraméterek bekérése
echo ""
log_info "VM konfiguráció:"
read -p "VM név [proxmox-ve]: " VM_NAME
VM_NAME=${VM_NAME:-proxmox-ve}

read -p "Memória MB-ban [8192]: " MEMORY
MEMORY=${MEMORY:-8192}

read -p "CPU magok száma [4]: " VCPUS
VCPUS=${VCPUS:-4}

read -p "Disk méret GB-ban [100]: " DISK_SIZE
DISK_SIZE=${DISK_SIZE:-100}

echo ""
log_info "VM konfiguráció:"
echo "  Név: $VM_NAME"
echo "  Memória: $MEMORY MB"
echo "  CPU: $VCPUS mag"
echo "  Disk: $DISK_SIZE GB"
echo "  ISO: $ISO_PATH"

read -p "Folytatás? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Telepítés megszakítva."
    exit 0
fi

# 3. VM létrehozása
log_info "VM létrehozása..."

# Ellenőrizzük, hogy létezik-e már a VM
if virsh list --all | grep -q "$VM_NAME"; then
    log_warn "A VM már létezik: $VM_NAME"
    read -p "Töröljük és újra létrehozzuk? (y/N): " recreate
    if [[ $recreate =~ ^[Yy]$ ]]; then
        virsh destroy "$VM_NAME" 2>/dev/null || true
        virsh undefine "$VM_NAME" --remove-all-storage 2>/dev/null || true
        log_info "Régi VM törölve."
    else
        log_error "Telepítés megszakítva."
        exit 1
    fi
fi

# VM létrehozása
log_info "Proxmox VM indítása ISO-ból..."
virt-install \
    --name="$VM_NAME" \
    --memory="$MEMORY" \
    --vcpus="$VCPUS" \
    --disk size="$DISK_SIZE",format=qcow2 \
    --cdrom="$ISO_PATH" \
    --network bridge=virbr0,model=virtio \
    --graphics vnc,listen=0.0.0.0,port=5900 \
    --console pty,target_type=serial \
    --boot cdrom,hd \
    --os-variant=linux2022 \
    --noautoconsole

if [ $? -eq 0 ]; then
    log_info "VM sikeresen létrehozva és elindítva!"
    
    # VNC információk
    echo ""
    echo "================================================"
    echo "TELEPÍTÉSI INFORMÁCIÓK"
    echo "================================================"
    
    SERVER_IP=$(hostname -I | awk '{print $1}')
    VNC_PORT=$(virsh vncdisplay "$VM_NAME" 2>/dev/null | cut -d: -f2)
    VNC_FULL_PORT=$((5900 + VNC_PORT))
    
    echo ""
    log_info "VNC kapcsolat:"
    echo "  Cím: $SERVER_IP:$VNC_FULL_PORT"
    echo "  Vagy: $SERVER_IP:590$VNC_PORT"
    echo ""
    
    log_info "SSH tunnel (biztonságosabb):"
    echo "  ssh -L 5900:localhost:$VNC_FULL_PORT $(whoami)@$SERVER_IP"
    echo "  Majd VNC-vel: localhost:5900"
    echo ""
    
    log_info "VM kezelő parancsok:"
    echo "  Lista: virsh list --all"
    echo "  Indítás: virsh start $VM_NAME"
    echo "  Leállítás: virsh shutdown $VM_NAME"
    echo "  Törlés: virsh destroy $VM_NAME && virsh undefine $VM_NAME --remove-all-storage"
    echo "  Konzol: virsh console $VM_NAME"
    echo ""
    
    log_info "Proxmox telepítési lépések:"
    echo "1. Kapcsolódj VNC-vel a fenti címre"
    echo "2. Kövesd a Proxmox telepítő lépéseit"
    echo "3. Telepítés után: reboot"
    echo "4. Web interface: https://[proxmox-ip]:8006"
    echo ""
    
    log_warn "FIGYELEM: A VM most fut és várakozik a telepítésre!"
    
    # VM állapot ellenőrzése
    echo ""
    log_info "VM állapot:"
    virsh list | grep "$VM_NAME" || log_error "VM nem fut!"
    
else
    log_error "VM létrehozása sikertelen!"
    exit 1
fi