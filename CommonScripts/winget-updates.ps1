function Get-WingetUpdates {
    Write-Host "Suche nach verfügbaren Updates..." -ForegroundColor Cyan
    
    # Setze Console-Encoding auf UTF-8
    $previousOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    
    # Verwende --source winget um nur winget-Pakete zu bekommen
    # und parse mit fester Spaltenbreite
    $env:TERM = 'xterm'
    $output = winget upgrade --source winget 2>&1 | Out-String
    [Console]::OutputEncoding = $previousOutputEncoding

    $updates = @()
    
    # Parse winget output
    $lines = $output -split "`n"
    $startParsing = $false
    
    foreach ($line in $lines) {
        if ($line -match "^Name\s+ID\s+Version\s+Verf") {
            $id_pos = $line.IndexOf("ID")
            $version_pos = $line.IndexOf("Version")
            $available_pos = $line.IndexOf("Verf")
            continue
        }
        if ($line -match "^-+") {
            $startParsing = $true
            continue
        }
        if ($line -match "[0-9]. Aktualisierungen verfügbar") {
            $startParsing = $false
            break
        }
        
        if ($startParsing -and $line.Trim() -and $line -notmatch "Aktualisierungen verfügbar") {
            $updates += [PSCustomObject]@{
                Name = $line.Substring(0, $id_pos).Trim()
                Id = $line.Substring($id_pos, $version_pos - $id_pos).Trim()
                CurrentVersion = $line.Substring($version_pos, $available_pos - $version_pos).Trim()
                AvailableVersion = $line.Substring($available_pos).Trim()
            }
        }
    }
    
    return $updates
}

function Show-UpdateMenu {
    param([array]$Updates)
    
    #Clear-Host
    Write-Host "=== Winget Update Manager ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Verfügbare Updates:" -ForegroundColor Yellow
    Write-Host ""
    
    for ($i = 0; $i -lt $Updates.Count; $i++) {
        $update = $Updates[$i]
        Write-Host ("{0,3}. " -f ($i + 1))  -NoNewline -ForegroundColor Magenta
        Write-Host $update.Name -ForegroundColor Gray
        Write-Host ("     ID: {0}" -f $update.Id) -ForegroundColor Yellow
        Write-Host ("     {0} -> {1}" -f $update.CurrentVersion, $update.AvailableVersion) -ForegroundColor Cyan
        Write-Host ""
    }
    
    Write-Host "0. Beenden" -ForegroundColor Red
    Write-Host ""
}

function Update-WingetPackage {
    param([string]$PackageId)
    
    Write-Host "Versuche Update für: $PackageId" -ForegroundColor Cyan
    
    # Erst ohne Admin-Rechte versuchen
    Write-Host "Versuch 1: Update ohne erhöhte Rechte..." -ForegroundColor Yellow
    $result = winget upgrade --id $PackageId --accept-source-agreements --accept-package-agreements 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Update erfolgreich!" -ForegroundColor Green
        return $true
    }
    
    # Prüfen ob Admin-Rechte benötigt werden
    if ($result -match "administrator|elevated|admin|Access is denied") {
        Write-Host "Administrator-Rechte erforderlich. Starte erhöhte Shell..." -ForegroundColor Yellow
        
        $scriptBlock = "winget upgrade --id '$PackageId' --accept-source-agreements --accept-package-agreements; pause"
        
        Start-Process powershell -Verb RunAs -ArgumentList "-Command", $scriptBlock #-Wait
        
        Write-Host "✓ Update in erhöhter Shell ausgeführt" -ForegroundColor Green
        return $true
    } else {
        Write-Host "✗ Update fehlgeschlagen" -ForegroundColor Red
        Write-Host $result -ForegroundColor DarkRed
        return $false
    }
}

# Hauptprogramm
$updates = Get-WingetUpdates

if ($updates.Count -eq 0) {
    Write-Host "Keine Updates verfügbar!" -ForegroundColor Green
    exit
}

do {
    Show-UpdateMenu -Updates $updates
    
    $choice = Read-Host "Wähle eine Nummer"
    
    if ($choice -eq "0") {
        Write-Host "Programm beendet." -ForegroundColor Yellow
        break
    }
    
    $index = [int]$choice - 1
    
    if ($index -ge 0 -and $index -lt $updates.Count) {
        $selectedUpdate = $updates[$index]
        Write-Host ""
        Update-WingetPackage -PackageId $selectedUpdate.Id
        Write-Host ""
        Read-Host "Drücke Enter um fortzufahren"
        $updates = Get-WingetUpdates
    } else {
        Write-Host "Ungültige Auswahl!" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
    
} while ($true)
