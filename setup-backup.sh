#!/bin/bash

# 1. Vérification des droits root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Veuillez lancer ce script avec sudo !"
  exit 1
fi

ACTION="$1"
REMOTE="gdrive:DebianBackups"
RCONFIG_DIR="/root/.config/rclone"
RCONFIG_FILE="$RCONFIG_DIR/rclone.conf"

# Fonction d'installation automatique des dépendances et du token Google Drive
install_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    for pkg in curl rclone tar gzip; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            echo "[!] Installation automatique de $pkg..."
            apt-get install -y -qq "$pkg"
        fi
    done

    # Création automatique du fichier de configuration Google Drive s'il n'existe pas
    if [ ! -f "$RCONFIG_FILE" ]; then
        echo "[+] Injection automatique de la configuration Google Drive..."
        mkdir -p "$RCONFIG_DIR"
        cat << 'EOF' > "$RCONFIG_FILE"
[gdrive]
type = drive
scope = drive
token = {"access_token":"METTEZ_VOTRE_ACCESS_TOKEN_ICI","refresh_token":"METTEZ_VOTRE_REFRESH_TOKEN_ICI","expiry":"2030-01-01T00:00:00Z"}
EOF
    fi
}

# ==========================================
# MODE : SAVE (Sauvegarde + Limite 5 max, écrasement de la plus vieille)
# ==========================================
if [ "$ACTION" == "save" ]; then
    echo "[+] Préparation de la sauvegarde système..."
    install_dependencies

    DATE=$(date +%Y-%m-%d_%H-%M-%S)
    ARCHIVE_NAME="backup_${HOSTNAME}_${DATE}.tar.gz"

    # Vérifier le nombre actuel de sauvegardes sur le Drive
    CURRENT_COUNT=$(rclone lsf "$REMOTE" --format "tpath" 2>/dev/null | grep -c "backup_")
    
    if [ "$CURRENT_COUNT" -ge 5 ]; then
        echo "[!] Limite de 5 sauvegardes atteinte. Suppression de la plus ancienne..."
        OLDEST_FILE=$(rclone lsf "$REMOTE" --format "tpath" --sort-by modtime | grep "backup_" | head -n 1)
        if [ ! -z "$OLDEST_FILE" ]; then
            echo "[+] Suppression de : $OLDEST_FILE"
            rclone delete "$REMOTE/$OLDEST_FILE"
        fi
    fi

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

    echo "[✔] Sauvegarde terminée avec succès ($ARCHIVE_NAME) !"

# ==========================================
# MODE : RESTORE (Menu numéroté 1 à 5)
# ==========================================
elif [ "$ACTION" == "restore" ]; then
    echo "[+] Récupération de la liste des sauvegardes sur le Drive..."
    install_dependencies

    # Récupérer la liste triée des sauvegardes
    mapfile -t BACKUPS < <(rclone lsf "$REMOTE" --format "tpath" --sort-by modtime | grep "backup_")

    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "[-] Aucune sauvegarde trouvée sur Google Drive."
        exit 1
    fi

    echo ""
    echo "======================================================="
    echo "       MENU DE RESTAURATION (SAUVEGARDES DISPOS)       "
    echo "======================================================="
    
    i=1
    for b in "${BACKUPS[@]}"; do
        echo "  [$i] $b"
        i=$((i+1))
    done
    echo "======================================================="
    
    read -p "Entrez le numéro de la sauvegarde à restaurer (1-${#BACKUPS[@]}) : " CHOICE

    # Vérification de la saisie
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "${#BACKUPS[@]}" ]; then
        echo "[-] Choix invalide. Annulation."
        exit 1
    fi

    SELECTED_ARCHIVE="${BACKUPS[$((CHOICE-1))]}"

    echo ""
    echo "[!] ATTENTION : Vous allez écraser le système actuel avec la sauvegarde :"
    echo "    -> $SELECTED_ARCHIVE"
    read -p "Êtes-vous sûr de vouloir continuer ? (oui/non) : " CONFIRM
    
    if [ "$CONFIRM" != "oui" ]; then
        echo "Restauration annulée."
        exit 0
    fi

    echo "[+] Téléchargement et application de la restauration en cours..."
    rclone cat "$REMOTE/$SELECTED_ARCHIVE" | tar -xzf - -C /

    echo "[✔] Restauration terminée ! Veuillez redémarrer votre système."

# ==========================================
# ERREUR / USAGE
# ==========================================
else
    echo "[-] Action non reconnue ou manquante."
    echo "Utilisation :"
    echo "  Pour sauvegarder : curl -s https://raw.githubusercontent.com/thebanditovh/BackupOS/refs/heads/main/setup-backup.sh | sudo bash -s save"
    echo "  Pour restaurer   : curl -s https://raw.githubusercontent.com/thebanditovh/BackupOS/refs/heads/main/setup-backup.sh | sudo bash -s restore"
    exit 1
fi
