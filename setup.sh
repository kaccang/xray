#!/bin/bash
# ==========================================
# XRAY Auto Installer - Optimized for High Traffic + BBR + S3 Backup + Auto Renew
# Core Version: v26.2.6
# ==========================================

clear
echo -e "\u001B[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u001B[0m"
echo -e "\u001B[1;32m      XRAY SERVER AUTO INSTALLER          \u001B[0m"
echo -e "\u001B[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u001B[0m"

# Nonaktifkan IPv6 SEMENTARA (hindari error SSL github)
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6


# 1. Input Domain di awal biar bisa ditinggal tidur
read -rp "Masukkan Domain VPS Anda (contoh: sg1.domain.com): " domain
echo "$domain" > /root/domain
mkdir -p /etc/xray
echo "$domain" > /etc/xray/domain

echo -e "
\u001B[1;32m[1/7] Mengupdate OS & Install Dependencies...\u001B[0m"

apt-get update -y
apt-get -y upgrade
apt-get -y install nginx zip curl wget unzip jq vnstat lsof net-tools iptables socat cron rclone snap snapd

snap install speedtest

systemctl enable vnstat
systemctl start vnstat

# Setup Info Server & Timezone
timedatectl set-timezone Asia/Jakarta
curl -s ipinfo.io/org | cut -d ' ' -f 2- > /etc/xray/isp
curl -s ipinfo.io/city > /etc/xray/city

echo -e "\u001B[1;32m[2/7] Setup BBR & Tuning TCP Kernel...\u001B[0m"
# Menggunakan sysctl.d agar lebih rapi dan aman
cat > /etc/sysctl.d/99-xray-bbr.conf << 'EOF'
# =============================================
# TCP BBR (WAJIB)
# =============================================
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# =============================================
# TCP Connection Optimization
# =============================================
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_syncookies = 1

# Naikkan dari 6000 ke 32000 (biar 400 user gak trigger kernel drop)
net.ipv4.tcp_max_tw_buckets = 32000
net.ipv4.tcp_max_syn_backlog = 65535

# =============================================
# TCP Buffer — KRITIS untuk RAM 4GB!
# =============================================
net.ipv4.tcp_rmem = 4096 87380 2097152
net.ipv4.tcp_wmem = 4096 65536 2097152
net.core.rmem_max = 2097152
net.core.wmem_max = 2097152

# =============================================
# Keepalive — Bunuh Zombie Connection
# =============================================
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# =============================================
# TCP Fast Open — Manfaatkan CPU EPYC
# =============================================
net.ipv4.tcp_fastopen = 3

# =============================================
# File Descriptor — WAJIB untuk proxy server
# =============================================
fs.file-max = 1000000

# =============================================
# Memory — Cegah OOM Kill
# =============================================
vm.swappiness = 10
vm.min_free_kbytes = 65536
EOF
sysctl --system > /dev/null 2>&1

echo -e "\u001B[1;32m[3/7] Generating SSL Certificate...\u001B[0m"
systemctl stop nginx
curl -sL https://get.acme.sh | sh
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue -d $domain --standalone -k ec-256 --force
~/.acme.sh/acme.sh --installcert -d $domain --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key --ecc --force

echo -e "\u001B[1;32m[4/7] Installing XRay Core (Version v26.2.6)...\u001B[0m"
# MENGINSTALL VERSI SPESIFIK v26.2.6
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version v26.2.6
mkdir -p /var/log/xray/
touch /var/log/xray/access.log
touch /var/log/xray/error.log
chmod 777 /var/log/xray/*

# Mengubah default path konfigurasi systemd XRay dari /usr/local/etc ke /etc/
sed -i 's|/usr/local/etc/xray/config.json|/etc/xray/config.json|g' /etc/systemd/system/xray.service

# MENGATASI DROP-IN OVERRIDE (Biang kerok yang bikin path nggak mau berubah)
if [ -f "/etc/systemd/system/xray.service.d/10-donot_touch_single_conf.conf" ]; then
    sed -i 's|/usr/local/etc/xray/config.json|/etc/xray/config.json|g' /etc/systemd/system/xray.service.d/10-donot_touch_single_conf.conf
fi

echo -e "\u001B[1;32m[5/7] Download Optimized Configurations & Menus...\u001B[0m"
# GANTI LINK DI BAWAH INI DENGAN LINK RAW GITHUB KAMU
REPO_CONF="https://raw.githubusercontent.com/kaccang/xray/main/config"
REPO_MENU="https://raw.githubusercontent.com/kaccang/xray/main/menu"

# Hapus config bawaan lalu download config optimasi
rm -f /etc/nginx/nginx.conf
rm -f /etc/xray/config.json
curl -sL ${REPO_CONF}/nginx.conf -o /etc/nginx/nginx.conf
curl -sL ${REPO_CONF}/config.json -o /etc/xray/config.json

# Mengganti domain pada Nginx Configuration secara dinamis
sed -i "s/server_name .*/server_name $domain;/" /etc/nginx/nginx.conf

# Download Menu & Tools
cd /usr/bin/
wget -O menu "${REPO_MENU}/menu"
wget -O add-ws "${REPO_MENU}/add-ws"
wget -O del-ws "${REPO_MENU}/del-ws"
wget -O renew-ws "${REPO_MENU}/renew-ws"
wget -O cek-ws "${REPO_MENU}/cek-ws"
wget -O add-vless "${REPO_MENU}/add-vless"
wget -O del-vless "${REPO_MENU}/del-vless"
wget -O renew-vless "${REPO_MENU}/renew-vless"
wget -O cek-vless "${REPO_MENU}/cek-vless"
wget -O add-tr "${REPO_MENU}/add-tr"
wget -O del-tr "${REPO_MENU}/del-tr"
wget -O renew-tr "${REPO_MENU}/renew-tr"
wget -O cek-tr "${REPO_MENU}/cek-tr"
wget -O cert "${REPO_MENU}/cert"
wget -O backup-xray "${REPO_MENU}/backup-xray"
wget -O sync-vps "${REPO_MENU}/sync-vps"
wget -O delete-sync "${REPO_MENU}/delete-sync"
wget -O xp "${REPO_MENU}/xp"
wget -O /usr/bin/user-ws "${REPO_MENU}/user-ws"
wget -O /usr/bin/user-vless "${REPO_MENU}/user-vless"
wget -O /usr/bin/user-tr "${REPO_MENU}/user-tr"
wget -O /usr/bin/user-xray "${REPO_MENU}/user-xray"

chmod +x menu add-ws del-ws renew-ws cek-ws add-vless del-vless renew-vless cek-vless add-tr del-tr renew-tr cek-tr cert backup-xray sync-vps xp user-ws user-vless user-tr user-xray
cd ~

# Pasang autostart menu di .profile (tanpa cek)
cat << 'EOF' >> ~/.profile

if [ -n "$SSH_CLIENT" ] && [ -x /usr/bin/menu ]; then
    clear
    /usr/bin/menu
fi
EOF

# Buat SWAP 2GB jika belum ada swap aktif
if [ -z "$(swapon --show --noheadings)" ]; then
    echo "No active swap found, creating 2G swapfile..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q '^/swapfile ' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    echo "Swap 2G created and enabled."
else
    echo "Swap already active, skip creating swapfile."
fi

echo -e "\u001B[1;32m[6/7] Setting Up Cronjobs...\u001B[0m"

# Auto Delete Expired Accounts at 00:00
echo "0 0 * * * root /usr/bin/xp" > /etc/cron.d/xray_expired
chmod 644 /etc/cron.d/xray_expired

# Auto Backup XRAY v1 at 02:00
echo "0 2 * * * root /usr/bin/backup-xray" > /etc/cron.d/xray_autobackup
chmod 644 /etc/cron.d/xray_autobackup

# Auto Backup XRAY v2 Watcher every 5 minutes (NO TELEGRAM)
echo "*/5 * * * * root SEND_TELEGRAM=0 /usr/bin/bckp" > /etc/cron.d/xray_watch
chmod 644 /etc/cron.d/xray_watch

# Auto Backup XRAY v2 at 23:00 (WITH TELEGRAM)
echo "0 23 * * * root SEND_TELEGRAM=1 /usr/bin/bckp" > /etc/cron.d/xray_backup_23
chmod 644 /etc/cron.d/xray_backup_23

# Auto Renew SSL Cert every 1st of the month at 04:00
cat > /etc/cron.d/xray_cert_renew << EOF
0 4 1 * * root systemctl stop nginx && /root/.acme.sh/acme.sh --cron --home /root/.acme.sh > /dev/null && systemctl start nginx && systemctl restart xray
EOF
chmod 644 /etc/cron.d/xray_cert_renew

systemctl restart cron

echo -e "\u001B[1;32m[7/7] Restarting Services...\u001B[0m"

# --- TAMBAHAN FIX NGINX SYSTEMD LIMITNOFILE ---
mkdir -p /etc/systemd/system/nginx.service.d
cat > /etc/systemd/system/nginx.service.d/override.conf << EOF
[Service]
LimitNOFILE=1000000
LimitNPROC=65535
EOF
# ----------------------------------------------

systemctl daemon-reload
systemctl restart nginx
systemctl enable nginx
systemctl restart xray
systemctl enable xray

echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6
echo 0 > /proc/sys/net/ipv6/conf/default/disable_ipv6

clear
echo -e "\u001B[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u001B[0m"
echo -e "\u001B[1;32m        INSTALLATION SUCCESSFUL!          \u001B[0m"
echo -e "\u001B[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u001B[0m"
echo -e " Domain     : $domain"
echo -e " Nginx      : Port 80, 443"
echo -e " XRay Core  : Version v26.2.6"
echo -e " TCP Tuning : BBR Enabled & Optimized"
echo -e " Cronjobs   : Auto XP (00:00), Auto Backup (02:00), Auto Cert (Tgl 1)"
echo -e "\u001B[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u001B[0m"
echo -e " Ketik \u001B[1;32mmenu\u001B[0m untuk memulai manajemen VPS."
echo -e " Atau \u001B[1;32mbackup-xray\u001B[0m untuk Setup S3 & Restore."
rm -f setup.sh