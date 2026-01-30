# deploy-windows.ps1
# Script de déploiement de claude-utils sur Windows
# Usage: powershell -ExecutionPolicy Bypass -File deploy-windows.ps1 [-SourcePath <path>]

param(
    [string]$SourcePath = "",
    [switch]$SkipBuild,
    [switch]$SkipStartup,
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# Configuration
$AppName = "claude-utils"
$TaskName = "claude-utils-server"
$LocalAppData = [Environment]::GetFolderPath('LocalApplicationData')
$AppData = [Environment]::GetFolderPath('ApplicationData')
$InstallDir = Join-Path $LocalAppData $AppName
$StartupDir = Join-Path $AppData "Microsoft\Windows\Start Menu\Programs\Startup"
$OldShortcutPath = Join-Path $StartupDir "$AppName.lnk"  # Pour migration
$ExePath = Join-Path $InstallDir "$AppName.exe"
$ServerArgs = "start --no-auth --watch --write --wsl --host 0.0.0.0"

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Claude-Utils Windows Deployment Script" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# Désinstallation
if ($Uninstall) {
    Write-Host "[1/4] Arrêt du serveur..." -ForegroundColor Yellow
    Stop-Process -Name $AppName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    Write-Host "[2/4] Suppression de la tâche planifiée..." -ForegroundColor Yellow
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "      Tâche planifiée supprimée" -ForegroundColor Green
    } else {
        Write-Host "      Aucune tâche planifiée trouvée" -ForegroundColor Gray
    }

    Write-Host "[3/4] Suppression de l'ancien raccourci (si présent)..." -ForegroundColor Yellow
    if (Test-Path $OldShortcutPath) {
        Remove-Item $OldShortcutPath -Force
        Write-Host "      Raccourci supprimé" -ForegroundColor Green
    } else {
        Write-Host "      Aucun raccourci trouvé" -ForegroundColor Gray
    }

    Write-Host "[4/4] Suppression du dossier d'installation..." -ForegroundColor Yellow
    if (Test-Path $InstallDir) {
        Remove-Item $InstallDir -Recurse -Force
        Write-Host "      Dossier supprimé: $InstallDir" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Désinstallation terminée!" -ForegroundColor Green
    exit 0
}

# Déterminer le chemin source
if (-not $SourcePath) {
    # Essayer de détecter automatiquement depuis WSL
    $WslPaths = @(
        "\\wsl$\Ubuntu\home\mks\projects\claude-utils",
        "\\wsl.localhost\Ubuntu\home\mks\projects\claude-utils",
        "C:\temp\claude-utils-build"
    )
    foreach ($path in $WslPaths) {
        if (Test-Path $path) {
            $SourcePath = $path
            break
        }
    }
}

if (-not $SourcePath -or -not (Test-Path $SourcePath)) {
    Write-Host "ERREUR: Chemin source non trouvé. Spécifiez -SourcePath" -ForegroundColor Red
    exit 1
}

Write-Host "Source: $SourcePath" -ForegroundColor Gray
Write-Host "Install: $InstallDir" -ForegroundColor Gray
Write-Host ""

# Étape 1: Compilation
if (-not $SkipBuild) {
    Write-Host "[1/5] Compilation..." -ForegroundColor Yellow
    Write-Host "      (cela peut prendre quelques minutes)" -ForegroundColor Gray

    # Utiliser cmd.exe pour éviter les problèmes de stderr avec PowerShell
    $originalLocation = Get-Location
    Set-Location $SourcePath
    cmd /c "cargo build --release 2>&1" | Out-Null
    Set-Location $originalLocation

    # Vérifier si le binaire existe
    $CompiledExe = Join-Path $SourcePath "target\release\$AppName.exe"
    if (Test-Path $CompiledExe) {
        Write-Host "      Compilation réussie" -ForegroundColor Green
    } else {
        Write-Host "ERREUR: Binaire non généré" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[1/5] Compilation ignorée (-SkipBuild)" -ForegroundColor Gray
}

# Étape 2: Arrêt du serveur existant
Write-Host "[2/5] Arrêt du serveur existant..." -ForegroundColor Yellow
$process = Get-Process -Name $AppName -ErrorAction SilentlyContinue
if ($process) {
    Stop-Process -Name $AppName -Force
    Start-Sleep -Seconds 2
    Write-Host "      Serveur arrêté" -ForegroundColor Green
} else {
    Write-Host "      Aucun serveur en cours" -ForegroundColor Gray
}

# Étape 3: Installation du binaire
Write-Host "[3/5] Installation du binaire..." -ForegroundColor Yellow
Write-Host "      InstallDir: $InstallDir" -ForegroundColor Gray
Write-Host "      ExePath: $ExePath" -ForegroundColor Gray

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "      Dossier créé: $InstallDir" -ForegroundColor Gray
}

$SourceExe = Join-Path $SourcePath "target\release\$AppName.exe"
Write-Host "      SourceExe: $SourceExe" -ForegroundColor Gray

if (-not (Test-Path $SourceExe)) {
    Write-Host "ERREUR: Binaire non trouvé: $SourceExe" -ForegroundColor Red
    exit 1
}

if ($SourceExe -eq $ExePath) {
    Write-Host "      Source = Destination, pas de copie nécessaire" -ForegroundColor Yellow
} else {
    Copy-Item $SourceExe $ExePath -Force
    Write-Host "      Binaire installé: $ExePath" -ForegroundColor Green
}

# Étape 4: Création de la tâche planifiée (avec privilèges élevés)
if (-not $SkipStartup) {
    Write-Host "[4/5] Création de la tâche planifiée..." -ForegroundColor Yellow

    # Supprimer l'ancien raccourci startup s'il existe (migration)
    if (Test-Path $OldShortcutPath) {
        Remove-Item $OldShortcutPath -Force
        Write-Host "      Ancien raccourci supprimé (migration)" -ForegroundColor Gray
    }

    # Créer la tâche planifiée avec privilèges élevés
    $Action = New-ScheduledTaskAction -Execute $ExePath -Argument $ServerArgs -WorkingDirectory $InstallDir
    $Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
    $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    # Supprimer l'ancienne tâche si elle existe
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }

    # Enregistrer la nouvelle tâche
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Description "Claude-Utils MCP Server - Clipboard integration for Claude Code" | Out-Null

    Write-Host "      Tâche planifiée créée: $TaskName" -ForegroundColor Green
    Write-Host "      → Privilèges élevés (symlinks autorisés)" -ForegroundColor Gray
    Write-Host "      → Démarrage automatique à la connexion" -ForegroundColor Gray
} else {
    Write-Host "[4/5] Tâche planifiée ignorée (-SkipStartup)" -ForegroundColor Gray
}

# Étape 5: Démarrage du serveur
Write-Host "[5/5] Démarrage du serveur..." -ForegroundColor Yellow
Start-Process -FilePath $ExePath -ArgumentList $ServerArgs.Split(" ") -WindowStyle Hidden
Start-Sleep -Seconds 2

# Vérification
try {
    $health = Invoke-RestMethod -Uri "http://localhost:3830/health" -TimeoutSec 5
    if ($health.status -eq "healthy") {
        Write-Host "      Serveur démarré (version $($health.version))" -ForegroundColor Green
    }
} catch {
    Write-Host "      ATTENTION: Impossible de vérifier le serveur" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Déploiement terminé!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Le serveur MCP est accessible sur:" -ForegroundColor White
Write-Host "  - http://localhost:3830 (Windows)" -ForegroundColor Gray
Write-Host "  - http://172.22.32.1:3830 (depuis WSL)" -ForegroundColor Gray
Write-Host ""
Write-Host "Configuration Claude Code:" -ForegroundColor White
Write-Host "  claude mcp add --transport http claude-utils http://localhost:3830/" -ForegroundColor Gray
Write-Host ""
