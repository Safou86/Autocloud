#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

main() {
  local nextcloud_dir="/var/www/nextcloud"
  local storage_account="ezyinm7lu4klq"
  local container="nextclouddata"
  local mount_point="/mnt/nextclouddata"
  local config_path="/etc/blobfuse2.yaml"

  install_dependencies
  install_nextcloud "$nextcloud_dir"
  setup_blobfuse2 "$storage_account" "$container" "$config_path"
  mount_blobfuse2 "$config_path" "$mount_point"
  configure_apache "$nextcloud_dir"
}

install_dependencies() {
  apt update -y
  apt upgrade -y
  apt install -y apache2 mariadb-server libapache2-mod-php \
    php php-mysql php-gd php-xml php-mbstring php-curl php-zip php-intl \
    php-bcmath php-gmp php-imagick unzip wget
}

install_nextcloud() {
  local dir="$1"
  wget https://download.nextcloud.com/server/releases/latest.zip
  unzip latest.zip
  mv nextcloud "$dir"
  chown -R www-data:www-data "$dir"
}

setup_blobfuse2() {
  local account="$1"
  local container="$2"
  local config="$3"

  wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb
  dpkg -i packages-microsoft-prod.deb
  rm -f packages-microsoft-prod.deb

  apt update
  apt install -y blobfuse2

  mkdir -p /mnt/nextclouddata
  chown -R www-data:www-data /mnt/nextclouddata

  tee "$config" > /dev/null <<EOF
version: 2
logging:
  type: syslog
components:
  - libfuse
  - azstorage
azstorage:
  type: block
  account-name: $account
  container: $container
  auth-type: msi
  endpoint: https://${account}.blob.core.windows.net
EOF

  chown root:root "$config"
  chmod 644 "$config"
}

mount_blobfuse2() {
  local config="$1"
  local mount="$2"
  blobfuse2 mount "$mount" --config-file="$config" --log-level=LOG_DEBUG --file-cache-timeout=120
}

configure_apache() {
  local dir="$1"
  cat <<EOF > /etc/apache2/sites-available/nextcloud.conf
<VirtualHost *:80>
    DocumentRoot $dir
    <Directory $dir/>
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews
    </Directory>
</VirtualHost>
EOF

  a2ensite nextcloud.conf
  a2enmod rewrite
  systemctl restart apache2
}

main
