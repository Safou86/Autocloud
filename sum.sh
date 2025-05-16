#!/bin/bash

# Exit bij fout
set -e

# Variabelen
NEXTCLOUD_DIR="/var/www/nextcloud"
STORAGE_ACCOUNT_NAME="ezyinm7lu4klq"
CONTAINER_NAME="nextclouddata"
MOUNT_POINT="/mnt/nextclouddata"
RESOURCE_GROUP="myResourceGroup"
LOCATION="westeurope"

# Updates en vereisten
sudo apt update && sudo apt upgrade -y
sudo apt install -y apache2 mariadb-server libapache2-mod-php \
 php php-mysql php-gd php-xml php-mbstring php-curl php-zip php-intl \
 php-bcmath php-gmp php-imagick unzip wget

# Nextcloud downloaden
wget https://download.nextcloud.com/server/releases/latest.zip
unzip latest.zip
sudo mv nextcloud "$NEXTCLOUD_DIR"
sudo chown -R www-data:www-data "$NEXTCLOUD_DIR"

# BlobFuse2 installeren
sudo mkdir -p /usr/share/keyrings
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt update
sudo apt install -y blobfuse2

# Mount directory voorbereiden
sudo mkdir -p "$MOUNT_POINT"
sudo chown -R www-data:www-data "$MOUNT_POINT"

# Configuratiebestand maken
CONFIG_PATH="/etc/blobfuse2.cfg"
cat <<EOF | sudo tee "$CONFIG_PATH"
configversion: 2
logging:
  type: syslog
components:
  - libfuse
  - azstorage
azstorage:
  type: block
  account-name: ${STORAGE_ACCOUNT_NAME}
  container: ${CONTAINER_NAME}
  auth-type: anonymous
  endpoint: https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net
  mode: readwrite
EOF

# Mount uitvoeren
sudo blobfuse2 mount "$MOUNT_POINT" --config-file="$CONFIG_PATH" --log-level=LOG_DEBUG

# Apache configureren
cat <<EOF | sudo tee /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    ServerAdmin admin@example.com
    DocumentRoot $NEXTCLOUD_DIR
    Alias /nextcloud "$NEXTCLOUD_DIR/"

    <Directory $NEXTCLOUD_DIR/>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/nextcloud_error.log
    CustomLog \${APACHE_LOG_DIR}/nextcloud_access.log combined
</VirtualHost>
EOF

# Apache modules activeren en herstarten
sudo a2ensite nextcloud.conf
sudo a2enmod rewrite headers env dir mime ssl
sudo systemctl reload apache2

echo "✅ Installatie voltooid. Open http://<VM-IP>/ om Nextcloud te configureren via de browser."
