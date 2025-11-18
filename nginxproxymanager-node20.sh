#!/usr/bin/env bash
# ===============================================
# Proxmox LXC - Nginx Proxy Manager (Node 20) Auto Install
# Author: ChatGPT (based on Community Scripts)
# License: MIT
# ===============================================

APP="Nginx Proxy Manager"
NODE_VERSION="20"

# Function for logging
function msg() { echo -e "\e[1;34m[INFO]\e[0m $1"; }
function msg_ok() { echo -e "\e[1;32m[OK]\e[0m $1"; }
function msg_err() { echo -e "\e[1;31m[ERROR]\e[0m $1"; }

# --- Update & Install Dependencies ---
msg "Updating container OS..."
apt update && apt upgrade -y
apt install -y curl gnupg lsb-release sudo software-properties-common build-essential python3 python3-pip

# --- Node.js 20 Setup ---
msg "Setting up Node.js ${NODE_VERSION}..."
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
apt install -y nodejs
npm install -g yarn

# --- OpenResty Setup ---
msg "Installing OpenResty..."
curl -fsSL https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/openresty.gpg
cat <<EOF >/etc/apt/sources.list.d/openresty.sources
Types: deb
URIs: http://openresty.org/package/debian/
Suites: bookworm
Components: openresty
Signed-By: /etc/apt/trusted.gpg.d/openresty.gpg
EOF
apt update
apt install -y openresty

# --- Create Nginx Proxy Manager Directories ---
msg "Creating Nginx Proxy Manager directories..."
mkdir -p /opt/nginxproxymanager
mkdir -p /data/nginx /data/custom_ssl /data/logs /data/access /data/nginx/{default_host,default_www,proxy_host,redirection_host,stream,dead_host,temp}
mkdir -p /var/lib/nginx/cache/{public,private} /var/cache/nginx/proxy_temp

chmod -R 777 /var/cache/nginx

# --- Fetch NPM Source ---
msg "Downloading Nginx Proxy Manager source..."
LATEST=$(curl -fsSL https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest \
    | grep tag_name | awk '{print substr($2, 3, length($2)-4)}')
msg "Latest release: $LATEST"

curl -fsSL https://github.com/NginxProxyManager/nginx-proxy-manager/archive/refs/tags/v$LATEST.tar.gz | tar xz -C /opt/nginxproxymanager --strip-components=1

# --- Backend Setup ---
msg "Installing backend dependencies..."
cd /opt/nginxproxymanager
yarn install --network-timeout 600000

# --- Frontend Setup ---
msg "Building frontend..."
cd frontend
sed -E -i 's/"node-sass" *: *"([^"]*)"/"sass": "\1"/g' package.json
yarn install --network-timeout 600000
yarn build
cp -r dist/* /opt/nginxproxymanager/frontend

# --- Production Config ---
msg "Setting up production config..."
cat <<'EOF' >/opt/nginxproxymanager/config/production.json
{
  "database": {
    "engine": "knex-native",
    "knex": {
      "client": "sqlite3",
      "connection": {
        "filename": "/data/database.sqlite"
      }
    }
  }
}
EOF

# --- Create Dummy SSL ---
if [ ! -f /data/nginx/dummycert.pem ] || [ ! -f /data/nginx/dummykey.pem ]; then
    msg "Creating dummy SSL certificate..."
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/O=Nginx Proxy Manager/OU=Dummy Certificate/CN=localhost" \
        -keyout /data/nginx/dummykey.pem -out /data/nginx/dummycert.pem
fi

# --- Start Services ---
msg "Starting OpenResty..."
systemctl enable --now openresty
systemctl restart openresty

msg_ok "Nginx Proxy Manager setup completed!"
echo "Access it via http://<CONTAINER_IP>:81"

