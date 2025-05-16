#!/bin/bash
set -e
exec > >(tee /var/log/nextcloud-blobfuse-install.log) 2>&1

# Configuratie
STORAGE_ACCOUNT="ezyinm7lu4klq"          # Vervang met je Azure Storage Account
CONTAINER="nextclouddata"                # Container naam
MOUNT_POINT="/mnt/nextclouddata"         # Mount directory
BLOBFUSE_CONFIG="/etc/blobfuse2.cfg"     # Configuratiebestand

main() {
  echo "🚀 Nextcloud + Azure Blob Storage Installatie"
  install_dependencies
  install_nextcloud_snap
  setup_blobfuse2
  configure_nextcloud_external_storage
  echo "✅ Klaar! Nextcloud is bereikbaar op http://$(hostname -I | cut -d' ' -f1)"
}

install_dependencies() {
  echo "🔄 Installeer dependencies..."
  apt update -y
  apt install -y snapd fuse blobfuse2
}

install_nextcloud_snap() {
  echo "📦 Installeer Nextcloud via Snap..."
  if ! snap list | grep -q nextcloud; then
    snap install nextcloud
    snap start nextcloud
  else
    echo "ℹ️ Nextcloud is al geïnstalleerd via Snap."
  fi
}

setup_blobfuse2() {
  echo "🔗 Configureer BlobFuse2..."
  
  # Maak mount directory
  mkdir -p "$MOUNT_POINT"
  chown -R www-data:www-data "$MOUNT_POINT"

  # Maak configuratiebestand
  cat > "$BLOBFUSE_CONFIG" <<EOF
version: 2
components:
  - libfuse
  - azstorage
azstorage:
  type: block
  account-name: $STORAGE_ACCOUNT
  container: $CONTAINER
  auth-type: msi
  endpoint: https://${STORAGE_ACCOUNT}.blob.core.windows.net
  blob-cache-timeout: 120
  attr-cache-timeout: 120
EOF

  # Maak systemd service voor automount
  cat > /etc/systemd/system/blobfuse2.service <<EOF
[Unit]
Description=Mount Azure Blob Storage via BlobFuse2
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/blobfuse2 mount $MOUNT_POINT --config-file=$BLOBFUSE_CONFIG -o allow_other
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  # Start de service
  systemctl daemon-reload
  systemctl enable --now blobfuse2.service
}

configure_nextcloud_external_storage() {
  echo "🛠️ Configureer externe opslag in Nextcloud..."
  # Wacht tot Nextcloud actief is
  while ! snap services nextcloud | grep -q "active"; do
    sleep 5
  done

  # Voeg externe opslag toe via occ-commando
  sudo nextcloud.occ app:enable files_external
  sudo nextcloud.occ files_external:create \
    "Azure Blob" \
    local \
    "$MOUNT_POINT" \
    -c datadir="$MOUNT_POINT"
}

main
