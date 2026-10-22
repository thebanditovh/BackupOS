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

# Fonction d'installation automatique et de vérification du Google Drive
install_dependencies() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    for pkg in curl rclone tar gzip; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            echo "[!] Installation automatique de $pkg..."
            apt-get install -y -qq "$pkg"
        fi
    done

    # Vérification si rclone est bien configuré (si le fichier n'existe pas ou ne contient pas le remote gdrive)
    if [ ! -f "$RCONFIG_FILE" ] || ! grep -q "\[gdrive\]" "$RCONFIG_FILE"; then
        echo ""
        echo "========================================================"
        echo "[!] ATTENTION : Le remote 'gdrive' n'est pas configuré."
        echo "========================================================"
        echo "Pour lier votre Google Drive facilement, tapez cette commande :"
        echo "  sudo rclone config"
        echo ""
        echo "Puis suivez ces choix :"
        echo "  1. Tapez 'n' (New remote)"
        echo "  2. Nommez-le exactement : gdrive"
        echo "  3. Choisissez 'Google Drive' dans la liste (entrez son numéro)"
        echo "  4. Laissez 'Client ID' et 'Client Secret' vides (Appuyez sur Entrée)"
        echo "  5. Choisissez le niveau d'accès '1' (Full access)"
        echo "  6. Laissez le reste vide et autorisez l'accès Google."
        echo "========================================================"
        exit 1
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

    if [ ${PIPESTATUS[1]} -eq 0 ]; then
        echo "[✔] Sauvegarde terminée avec succès ($ARCHIVE_NAME) !"
    else
        echo "[-] Erreur lors de l'envoi sur Google Drive."
        exit 1
    fi

# ==========================================
# MODE : RESTORE (Menu numéroté 1 à 5)
# ==========================================
elif [ "$ACTION" == "restore" ]; then
    echo "[+] Récupération de la liste des sauvegardes sur le Drive..."
    install_dependencies

    mapfile -t BACKUPS < <(rclone lsf "$REMOTE" --format "tpath" --sort-by modtime 2>/dev/null | grep "backup_")

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
    echo "  Pour sauvegarder : curl -s URL | sudo bash -s save"
    echo "  Pour restaurer   : curl -s URL | sudo bash -s restore"
    exit 1
fi
