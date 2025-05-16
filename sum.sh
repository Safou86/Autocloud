#!/bin/bash
set -e

# Variabelen
NEXTCLOUD_DIR="/var/www/nextcloud"
STORAGE_ACCOUNT_NAME="ezyinm7lu4klq"  # Vervang met je eigen storage account
CONTAINER_NAME="nextclouddata"
MOUNT_POINT="/mnt/nextclouddata"

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

### 🔥 Kritieke aanpassing: Correcte blobfuse2 installatie ###
# Microsoft's repository toevoegen (specifiek voor Ubuntu 22.04)
echo "deb [arch=amd64] https://packages.microsoft.com/ubuntu/22.04/prod jammy main" | sudo tee /etc/apt/sources.list.d/microsoft.list
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
sudo apt update

# blobfuse2 installeren (nu zou het moeten werken)
sudo apt install -y blobfuse2

# Mount directory voorbereiden
sudo mkdir -p "$MOUNT_POINT"
sudo chown -R www-data:www-data "$MOUNT_POINT"

### 🔥 Verbeterde configuratie met SAS-token of managed identity ###
# Maak eerst een tijdelijke SAS-token aan (vervang met je eigen token)
# Of gebruik managed identity als je Azure AD-integratie hebt
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
  auth-type: msi  # 🔥 Gebruik Managed Identity (aanbevolen) of "sas" met token
  endpoint: https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net
  mode: readwrite
EOF

# Mount testen (voeg --allow-other toe voor Apache toegang)
sudo blobfuse2 mount "$MOUNT_POINT" --config-file="$CONFIG_PATH" --allow-other

# Apache configuratie (zelfde als voorheen)
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
</VirtualHost>
EOF

# Apache herstarten
sudo a2ensite nextcloud.conf
sudo a2enmod rewrite headers env dir mime
sudo systemctl restart apache2

echo "✅ Nextcloud is klaar! Open http://$(curl -s ifconfig.me)/nextcloud"
