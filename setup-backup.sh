#!/bin/bash

# 1. Vérification des droits root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Veuillez lancer ce script avec sudo !"
  exit 1
fi

ACTION="$1"
REMOTE="gdrive:DebianBackups"

# Fonction d'installation automatique des dépendances en mode silencieux
install_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    for pkg in curl rclone tar gzip; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            apt-get install -y -qq "$pkg"
        fi
    done

    # Vérification et configuration de rclone si absent
    if ! rclone listremotes | grep -q "gdrive:"; then
        echo "[!] Le remote 'gdrive' n'est pas configuré. Veuillez configurer Google Drive :"
        rclone config
    fi
}

# ==========================================
# MODE : SAVE (Sauvegarde + Rétention 5 max)
# ==========================================
if [ "$ACTION" == "save" ]; then
    echo "[+] Préparation de la sauvegarde système..."
    install_dependencies

    DATE=$(date +%Y-%m-%d_%H-%M-%S)
    ARCHIVE_NAME="backup_${HOSTNAME}_${DATE}.tar.gz"

    echo "[+] Démarrage de la sauvegarde complète vers Google Drive (Streaming direct)..."
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

    echo "[✔] Sauvegarde terminée avec succès !"

    echo "[+] Nettoyage des anciennes sauvegardes (Max 5 conservées)..."
    rclone lsf --fs-listing --sort-by modtime "$REMOTE" | head -n -5 | while read -r old_file; do
        if [ ! -z "$old_file" ]; then
            echo "Suppression de l'ancienne sauvegarde : $old_file"
            rclone delete "$REMOTE/$old_file"
        fi
    done
    echo "[✔] Opération terminée !"

# ==========================================
# MODE : RESTORE (Restauration interactive)
# ==========================================
elif [ "$ACTION" == "restore" ]; then
    echo "[+] Préparation de la restauration..."
    install_dependencies

    echo ""
    echo "=== LISTE DES SAUVEGARDES DISPONIBLES SUR LE DRIVE ==="
    rclone lsf "$REMOTE" --sort-by modtime
    echo "======================================================="
    
    read -p "Entrez le nom exact de l'archive à restaurer (ex: backup_debian_2026-06-06.tar.gz) : " ARCHIVE_TO_RESTORE

    if [ -z "$ARCHIVE_TO_RESTORE" ]; then
        echo "[-] Aucun nom saisi. Annulation."
        exit 1
    fi

    echo "[!] ATTENTION : Vous allez écraser le système actuel avec l'archive $ARCHIVE_TO_RESTORE."
    read -p "Êtes-vous sûr ? (oui/non) : " CONFIRM
    
    if [ "$CONFIRM" != "oui" ]; then
        echo "Restauration annulée."
        exit 0
    fi

    echo "[+] Téléchargement et application de la restauration en cours..."
    rclone cat "$REMOTE/$ARCHIVE_TO_RESTORE" | tar -xzf - -C /

    echo "[✔] Restauration terminée ! Veuillez redémarrer votre système."

# ==========================================
# ERREUR / USAGE
# ==========================================
else
    echo "[-] Action non reconnue ou manquante."
    echo "Utilisation :"
    echo "  Pour sauvegarder : sudo bash <(curl -s https://raw.githubusercontent.com/thebanditovh/BackupOS/refs/heads/main/setup-backup.sh) save"
    echo "  Pour restaurer   : sudo bash <(curl -s https://raw.githubusercontent.com/thebanditovh/BackupOS/refs/heads/main/setup-backup.sh) restore"
    exit 1
fi
