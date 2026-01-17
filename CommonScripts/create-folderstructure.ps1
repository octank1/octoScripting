<#
.SYNOPSIS
    Erstellt eine konfigurierbare Verzeichnisstruktur für ein bestimmtes Jahr.
.DESCRIPTION
    Dieses Script legt basierend auf einer konfigurierbaren Struktur Verzeichnisse an.
    Es ist idempotent - mehrfache Ausführungen überschreiben keine vorhandenen Ordner.
.PARAMETER Year
    Das Jahr, für das die Struktur angelegt werden soll.
.PARAMETER BasePath
    Der Basispfad, unter dem die Struktur angelegt werden soll. Standard: aktuelles Verzeichnis.
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$Year,
    
    [Parameter(Mandatory=$false)]
    [string]$BasePath = ""
)
# Windows-Pfad zum Basisverzeichnis der Dateien
$WinPath = "C:\Daten\...\"
# WSL-Pfad zum Basisverzeichnis der Dateien
$WSLPath = "/mnt/c/Daten/.../"

# Prüfen, ob wir in WSL sind
$isWSL = (Test-Path "/proc/version") -and (Get-Content "/proc/version" -ErrorAction SilentlyContinue) -match "microsoft|WSL"

# Basispfad setzen, falls nicht als Parameter übergeben
if (-not $BasePath -or $BasePath -eq "") {
    if ($isWSL) {
        $BasePath = $WSLPath
        Write-Host "WSL-Umgebung erkannt - verwende WSL-Pfad" -ForegroundColor Magenta
    }
    else {
        $BasePath = $WinPath
        Write-Host "Windows-Umgebung erkannt - verwende Windows-Pfad" -ForegroundColor Magenta
    }
}

# Konfiguration: Verzeichnisstruktur als Hashtable
# Hier müssen alle Unterverzeichnisse einmalig definiert werden
$DirectoryStructure = @(
    "Ausgangsrechnungen",
    "Eingangsrechnungen/Bürobedarf",
    "Eingangsrechnungen/Software",
    "Kontoauszüge"
)

# Jahr abfragen, falls nicht als Parameter übergeben
if (-not $Year) {
    $Year = Read-Host "Bitte geben Sie das Jahr ein (z.B. $(Get-Date -Format yyyy))"
    
    # Validierung
    if (-not ($Year -match '^\d{4}$')) {
        Write-Error "Ungültiges Jahr. Bitte geben Sie ein 4-stelliges Jahr ein."
        exit 1
    }
}

# Hauptverzeichnis mit Jahr erstellen
$RootPath = Join-Path -Path $BasePath -ChildPath $Year

Write-Host "Erstelle Verzeichnisstruktur für Jahr $Year..." -ForegroundColor Cyan
Write-Host "Basispfad: $RootPath" -ForegroundColor Gray

# Verzeichnisse erstellen
$CreatedCount = 0
$ExistingCount = 0

foreach ($directory in $DirectoryStructure) {
    # Pfad zusammensetzen (/ durch Plattform-spezifischen Separator ersetzen)
    $fullPath = Join-Path -Path $RootPath -ChildPath $directory.Replace('/', [IO.Path]::DirectorySeparatorChar)
    
    if (Test-Path -Path $fullPath) {
        Write-Host "  [EXISTS] $directory" -ForegroundColor Yellow
        $ExistingCount++
    }
    else {
        try {
            New-Item -Path $fullPath -ItemType Directory -Force | Out-Null
            Write-Host "  [CREATED] $directory" -ForegroundColor Green
            $CreatedCount++
        }
        catch {
            Write-Error "Fehler beim Erstellen von '$directory': $_"
        }
    }
}

# Zusammenfassung
Write-Host "`nZusammenfassung:" -ForegroundColor Cyan
Write-Host "  Neu erstellt: $CreatedCount" -ForegroundColor Green
Write-Host "  Bereits vorhanden: $ExistingCount" -ForegroundColor Yellow
Write-Host "  Gesamt: $($DirectoryStructure.Count)" -ForegroundColor White
Write-Host "`nVerzeichnisstruktur für $Year erfolgreich angelegt unter:" -ForegroundColor Green
Write-Host "  $RootPath" -ForegroundColor White

# # Interaktive Ausführung (fragt nach dem Jahr)
# .\Create-DirectoryStructure.ps1

# # Mit Jahresangabe
# .\Create-DirectoryStructure.ps1 -Year 2025

# # Mit benutzerdefiniertem Basispfad
# .\Create-DirectoryStructure.ps1 -Year 2025 -BasePath "C:\Buchhaltung"
