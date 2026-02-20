#!/bin/bash
# ==========================================
# XRAY Auto Installer - Optimized for High Traffic + BBR + S3 Backup + Auto Renew
# Core Version: v26.2.6
# ==========================================

# Mencegah pop-up interaktif saat instalasi package (grub, dll)
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

clear
echo -e "\u001B[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u001B[0m"
echo -e "\u001B[1;32m      XRAY SERVER AUTO INSTALLER          \u001B[0m"
echo -e "\u001B[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u001B[0m"

# 1. Input Domain di awal biar bisa ditinggal tidur
read -rp "Masukkan Domain VPS Anda (contoh: sg1.domain.com): " domain
echo "$domain" > /root/domain
mkdir -p /etc/xray
echo "$domain" > /etc/xray/domain

echo -e "
\u001B[1;32m[1/7] Mengupdate OS & Install Dependencies...\u001B[0m"
# Install dengan argumen force agar 100% yes dan default
apt-get update -yq
apt-get -yq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade
apt-get -yq -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" install nginx curl wget unzip jq vnstat lsof net-tools iptables socat cron rclone

systemctl enable vnstat
systemctl start vnstat

echo -e "\u001B[1;32m[2/7] Setup BBR & Tuning TCP Kernel...\u001B[0m"
# Menggunakan sysctl.d agar lebih rapi dan aman
cat > /etc/sysctl.d/99-xray-bbr.conf << EOF
# TCP BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP Optimizations for High Concurrent Connections
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_syncookies = 1
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

echo -e "\u001B[1;32m[5/7] Download Optimized Configurations & Menus...\u001B[0m"
# GANTI LINK DI BAWAH INI DENGAN LINK RAW GITHUB KAMU
REPO_CONF="https://raw.githubusercontent.com/kaccang/xray/main/config"
REPO_MENU="https://raw.githubusercontent.com/kaccang/xray/main/menu"

# Hapus config bawaan lalu download config optimasi
rm -f /etc/nginx/nginx.conf
rm -f /etc/xray/config.json
curl -sL ${REPO_CONF}/nginx.conf -o /etc/nginx/nginx.conf
curl -sL ${REPO_CONF}/config.json -o /etc/xray/config.json

# Download Menu & Tools
cd /usr/bin/
wget -qO menu "${REPO_MENU}/menu"
wget -qO add-ws "${REPO_MENU}/add-ws"
wget -qO del-ws "${REPO_MENU}/del-ws"
wget -qO renew-ws "${REPO_MENU}/renew-ws"
wget -qO cek-ws "${REPO_MENU}/cek-ws"
wget -qO add-vless "${REPO_MENU}/add-vless"
wget -qO del-vless "${REPO_MENU}/del-vless"
wget -qO renew-vless "${REPO_MENU}/renew-vless"
wget -qO cek-vless "${REPO_MENU}/cek-vless"
wget -qO add-tr "${REPO_MENU}/add-tr"
wget -qO del-tr "${REPO_MENU}/del-tr"
wget -qO renew-tr "${REPO_MENU}/renew-tr"
wget -qO cek-tr "${REPO_MENU}/cek-tr"
wget -qO cert "${REPO_MENU}/cert"
wget -qO backup-xray "${REPO_MENU}/backup-xray"
wget -qO sync-vps "${REPO_MENU}/sync-vps"
wget -qO xp "${REPO_MENU}/xp"

chmod +x menu add-ws del-ws renew-ws cek-ws add-vless del-vless renew-vless cek-vless add-tr del-tr renew-tr cek-tr cert backup-xray sync-vps xp
cd ~

echo -e "\u001B[1;32m[6/7] Setting Up Cronjobs...\u001B[0m"

# Auto Delete Expired Accounts at 00:00
echo "0 0 * * * root /usr/bin/xp" > /etc/cron.d/xray_expired
chmod 644 /etc/cron.d/xray_expired

# Auto Backup XRAY S3+Tele at 02:00
echo "0 2 * * * root /usr/bin/backup-xray --auto" > /etc/cron.d/xray_autobackup
chmod 644 /etc/cron.d/xray_autobackup

# Auto Renew SSL Cert every 1st of the month at 04:00
cat > /etc/cron.d/xray_cert_renew << EOF
0 4 1 * * root systemctl stop nginx && /root/.acme.sh/acme.sh --cron --home /root/.acme.sh > /dev/null && systemctl start nginx && systemctl restart xray
EOF
chmod 644 /etc/cron.d/xray_cert_renew

systemctl restart cron

echo -e "\u001B[1;32m[7/7] Restarting Services...\u001B[0m"
systemctl daemon-reload
systemctl restart nginx
systemctl enable nginx
systemctl restart xray
systemctl enable xray

clear
echo -e "\u001B[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u001B[0m"
echo -e "\u001B[1;32m        INSTALLATION SUCCESSFUL!          \u001B[0m"
echo -e "\u001B[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u001B[0m"
echo -e " Domain     : $domain"
echo -e " Nginx      : Port 80, 443"
echo -e " XRay Core  : Version v26.2.6"
echo -e " TCP Tuning : BBR Enabled"
echo -e " Cronjobs   : Auto XP (00:00), Auto Backup (02:00), Auto Cert (Tgl 1)"
echo -e "\u001B[1;36m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\u001B[0m"
echo -e " Ketik \u001B[1;32mmenu\u001B[0m untuk memulai manajemen VPS."
echo -e " Atau \u001B[1;32mbackup-xray\u001B[0m untuk Setup S3 & Restore."
rm -f setup.sh