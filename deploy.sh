#!/bin/bash
# deploy.sh - Wrapper pour déployer claude-utils sur Windows depuis WSL
# Usage: ./deploy.sh [--skip-build] [--skip-startup] [--uninstall]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔═══════════════════════════════════════════════╗"
echo "║  Claude-Utils - Déploiement Windows via WSL   ║"
echo "╚═══════════════════════════════════════════════╝"
echo ""
echo "Source: $SCRIPT_DIR"
echo ""

# Copier vers un dossier Windows local (évite les problèmes de chemin UNC)
WIN_BUILD_DIR="C:\\temp\\claude-utils-build"
echo "Copie vers $WIN_BUILD_DIR (sans target/)..."
rm -rf /mnt/c/temp/claude-utils-build 2>/dev/null || true
mkdir -p /mnt/c/temp/claude-utils-build
# Copier sans le dossier target/ pour forcer une recompilation propre
rsync -a --exclude='target' "$SCRIPT_DIR"/ /mnt/c/temp/claude-utils-build/
# Convertir les scripts PowerShell en CRLF (Windows)
if command -v unix2dos &> /dev/null; then
    unix2dos /mnt/c/temp/claude-utils-build/*.ps1 2>/dev/null
else
    sed -i 's/$/\r/' /mnt/c/temp/claude-utils-build/*.ps1 2>/dev/null
fi
echo "Copie terminée"
echo ""

# Construire les arguments PowerShell
SKIP_BUILD=""
SKIP_STARTUP=""
UNINSTALL=""

for arg in "$@"; do
    case $arg in
        --skip-build)
            SKIP_BUILD="-SkipBuild"
            ;;
        --skip-startup)
            SKIP_STARTUP="-SkipStartup"
            ;;
        --uninstall)
            UNINSTALL="-Uninstall"
            ;;
        *)
            echo "Option inconnue: $arg"
            echo "Usage: $0 [--skip-build] [--skip-startup] [--uninstall]"
            exit 1
            ;;
    esac
done

# Exécuter PowerShell avec sudo (nécessaire pour créer la tâche planifiée avec privilèges élevés)
# Requiert: Windows 11 24H2+ avec sudo activé (Paramètres → Système → Pour les développeurs → sudo)
sudo.exe powershell.exe -ExecutionPolicy Bypass -File "C:\\temp\\claude-utils-build\\deploy-windows.ps1" -SourcePath "$WIN_BUILD_DIR" $SKIP_BUILD $SKIP_STARTUP $UNINSTALL

# Afficher l'IP WSL pour référence
echo ""
echo "─────────────────────────────────────────────────"
WSL_IP=$(ip route show default | awk '{print $3}')
echo "IP Windows depuis WSL: $WSL_IP"
echo ""
echo "Test rapide:"
echo "  curl http://$WSL_IP:3830/health"
echo "─────────────────────────────────────────────────"
