#!/bin/bash

# 1. Vérification des droits root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Veuillez lancer ce script avec sudo : sudo bash <(curl -s ...)"
  exit 1
fi

echo "[+] Vérification des prérequis..."

# 2. Vérification et installation automatique de Rclone si absent
if ! command -v rclone &> /dev/null; then
    echo "[!] Rclone n'est pas installé. Installation en cours..."
    apt update && apt install -y curl rclone tar gzip
else
    echo "[✔] Rclone est déjà installé."
fi

# 3. Configuration de Rclone (si le remote 'gdrive' n'existe pas encore)
if ! rclone listremotes | grep -q "gdrive:"; then
    echo "[!] Le remote Google Drive ('gdrive') n'est pas configuré."
    echo "--- Suivez l'assistant ci-dessous ---"
    rclone config
else
    echo "[✔] Le remote Rclone 'gdrive' est déjà configuré."
fi

# 4. Création du script de sauvegarde global dans /usr/local/bin
echo "[+] Mise en place du script de sauvegarde système..."

cat << 'EOF' > /usr/local/bin/backup-system-gdrive.sh
#!/bin/bash

REMOTE="gdrive:DebianBackups"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
ARCHIVE_NAME="backup_${HOSTNAME}_${DATE}.tar.gz"

echo "Démarrage de la sauvegarde complète vers Google Drive..."

tar --exclude='/dev' \
    --exclude='/proc' \
    --exclude='/sys' \
    --exclude='/tmp' \
    --exclude='/run' \
    --exclude='/mnt' \
    --exclude='/media' \
    --exclude='/lost+found' \
    --exclude='/var/cache' \
    -czf - / | rclone rcat "$REMOTE/$ARCHIVE_NAME"

echo "Sauvegarde terminée avec succès !"

echo "Nettoyage des anciennes sauvegardes (Max 5 conservées)..."
rclone lsf --fs-listing --sort-by modtime "$REMOTE" | head -n -5 | while read -r old_file; do
    if [ ! -z "$old_file" ]; then
        echo "Suppression de l'ancienne sauvegarde : $old_file"
        rclone delete "$REMOTE/$old_file"
    fi
done

echo "Opération terminée !"
EOF

chmod +x /usr/local/bin/backup-system-gdrive.sh

echo ""
echo "=================================================="
echo "[✔] TOUT EST PRÊT !"
echo "=================================================="
echo "Pour lancer une sauvegarde immédiate : sudo backup-system-gdrive.sh"
echo "Pour voir vos sauvegardes sur le Drive : rclone lsf gdrive:DebianBackups --sort-by modtime"
echo "=================================================="
