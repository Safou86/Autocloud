#!/bin/bash
set -e

# Variabelen
NEXTCLOUD_DIR="/var/www/nextcloud"
STORAGE_ACCOUNT_NAME="ezyinm7lu4klq"  # Vervang met je eigen storage account
CONTAINER_NAME="nextclouddata"
MOUNT_POINT="/mnt/nextclouddata"

# 1. Basisvereisten
sudo apt update && sudo apt upgrade -y
sudo apt install -y apache2 mariadb-server libapache2-mod-php \
 php php-mysql php-gd php-xml php-mbstring php-curl php-zip php-intl \
 php-bcmath php-gmp php-imagick unzip wget

# 2. Nextcloud installeren
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
sudo mv nextcloud "$NEXTCLOUD_DIR"
sudo chown -R www-data:www-data "$NEXTCLOUD_DIR"

# 3. 🔥 CORRECTE blobfuse2 installatie
# Microsoft's repository toevoegen (specifiek voor blobfuse2)
wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo rm packages-microsoft-prod.deb
sudo apt update
sudo apt install -y blobfuse2

# 4. Mount voorbereiden
sudo mkdir -p "$MOUNT_POINT"
sudo chown -R www-data:www-data "$MOUNT_POINT"

# 5. 🔥 Authenticatie via Managed Identity
cat <<EOF | sudo tee /var/www/blobfuse2.yaml
configversion: 2
components:
  - libfuse
  - azstorage
azstorage:
  type: block
  account-name: ${STORAGE_ACCOUNT_NAME}
  container: ${CONTAINER_NAME}
  auth-type: msi  # 🔥 Gebruik VM's managed identity
  endpoint: https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net
EOF

sudo chown www-data:www-data /var/www/blobfuse2.yaml
# 6. Mounten met debug-logging
sudo blobfuse2 mount "$MOUNT_POINT" --config-file=/var/www/blobfuse2.yaml --allow-other --log-level=LOG_DEBUG --file-cache-timeout=120

# 7. Apache configuratie
cat <<EOF | sudo tee /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    DocumentRoot $NEXTCLOUD_DIR
    <Directory $NEXTCLOUD_DIR/>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>
</VirtualHost>
EOF

sudo a2ensite nextcloud.conf
sudo a2enmod rewrite
sudo systemctl restart apache2

echo "✅ Nextcloud is bereikbaar op http://$(curl -s ifconfig.me)"
