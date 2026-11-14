# lancer.ps1 - vérifie l'environnement puis lance le générateur
param([string]$Dossier = "manga_reader")
$Script = "creer_manga_reader.dart"

function Echec($msg) { Write-Host "`n[X] $msg" -ForegroundColor Red; exit 1 }
function Ok($msg)    { Write-Host "[OK] $msg" -ForegroundColor Green }

Write-Host "=== Diagnostic ===" -ForegroundColor Cyan

# 1. Le script est-il dans le dossier courant ?
if (-not (Test-Path $Script)) {
    Echec "'$Script' introuvable dans $(Get-Location).`n    Fais 'cd' vers le bon dossier (fichiers présents : $((Get-ChildItem *.dart -Name) -join ', '))."
}
Ok "Fichier $Script trouvé"

# 2. Le fichier est-il complet ? (il doit finir par '};')
$derniere = (Get-Content $Script | Where-Object { $_.Trim() -ne "" } | Select-Object -Last 1).Trim()
if ($derniere -ne "};") {
    Echec "Le fichier semble tronqué (dernière ligne : '$derniere'). Recopie-le en entier."
}
Ok "Fichier complet"

# 3. Flutter et Dart sont-ils dans le PATH ?
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Echec "'flutter' introuvable. Ajoute le dossier flutter\bin au PATH, puis FERME et rouvre VS Code."
}
Ok "Flutter trouvé : $((Get-Command flutter).Source)"

if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
    Echec "'dart' introuvable. Il est fourni avec Flutter (flutter\bin) : vérifie ton PATH."
}
Ok "Dart trouvé"

# 4. Version de Dart (3.0 minimum)
$v = (dart --version 2>&1) -join " "
if ($v -match "(\d+)\.(\d+)\.(\d+)") {
    if ([int]$Matches[1] -lt 3) { Echec "Dart $($Matches[0]) est trop ancien (3.0 minimum). Lance : flutter upgrade" }
    Ok "Dart $($Matches[0])"
}

# 5. Le dossier de destination existe-t-il déjà ?
if (Test-Path $Dossier) {
    Echec "Le dossier '$Dossier' existe déjà.`n    Supprime-le ou relance avec un autre nom :  .\lancer.ps1 mon_autre_nom"
}
Ok "Le dossier '$Dossier' est libre"

# 6. Lancement
Write-Host "`n=== Lancement du générateur ===" -ForegroundColor Cyan
dart $Script $Dossier
if ($LASTEXITCODE -ne 0) { Echec "Le générateur s'est arrêté avec une erreur (code $LASTEXITCODE). Copie-colle les messages ci-dessus." }

Write-Host "`nTerminé. Pour lancer l'appli :  cd $Dossier ; flutter run" -ForegroundColor Green