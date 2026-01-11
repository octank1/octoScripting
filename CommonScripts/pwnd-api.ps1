#Requires -Version 5.1

<#
.SYNOPSIS
    HIBP Password Check via k-Anonymity API (SCHNELL!)
.DESCRIPTION
    Nutzt die offizielle HIBP API - kein 80GB Download nötig!
#>

param(
  [Parameter(Mandatory = $false)]
  [string]$Password,
    
  [Parameter(Mandatory = $false)]
  [string]$PasswordFile,
    
  [Parameter(Mandatory = $false)]
  [switch]$ShowPassword = $true,
  
  [Parameter(Mandatory = $false)]
  [switch]$ExportCsv = $false
)

function ConvertTo-SHA1Hash {
  param([string]$String)
    
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($String)
  $hash = $sha1.ComputeHash($bytes)
  $hashString = [System.BitConverter]::ToString($hash) -replace '-'
    
  return $hashString.ToUpper()
}

function Test-PasswordWithAPI {
  param([string]$Password)
    
  # Hash berechnen
  $hash = ConvertTo-SHA1Hash -String $Password
    
  # k-Anonymity: Nur erste 5 Zeichen senden
  $prefix = $hash.Substring(0, 5)
  $suffix = $hash.Substring(5)
    
  Write-Host "`nPrüfe Passwort..." -ForegroundColor Cyan
  Write-Host "SHA1: $hash" -ForegroundColor Gray
  Write-Host "API-Anfrage: Sende nur '$prefix' (k-Anonymity)" -ForegroundColor Gray
    
  try {
    # HIBP API abfragen
    $apiUrl = "https://api.pwnedpasswords.com/range/$prefix"
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -UseBasicParsing
    # DEBUG: Response in Datei schreiben
    $debugFile = Join-Path $PSScriptRoot "api_response_$prefix.txt"
    $response | Out-File -FilePath $debugFile -Encoding UTF8
    Write-Host "DEBUG: Response gespeichert in $debugFile" -ForegroundColor Magenta
 
    # Response durchsuchen
    $lines = $response -split "`n"
    $found = $false
    $count = 0
        
    foreach ($line in $lines) {
      if ($line.Trim()) {
        $parts = $line -split ':'
        $hashSuffix = $parts[0].Trim()
                
        if ($hashSuffix -eq $suffix) {
          $found = $true
          $count = [int]$parts[1].Trim()
          break
        }
      }
    }
        
    return @{
      Found = $found
      Hash  = $hash
      Count = $count
    }
        
  }
  catch {
    Write-Host "FEHLER bei API-Anfrage: $_" -ForegroundColor Red
    return @{
      Found = $false
      Hash  = $hash
      Count = 0
      Error = $_.Exception.Message
    }
  }
}

# Hauptlogik
Clear-Host
Write-Host "=== HIBP Password Breach Checker (API) ===" -ForegroundColor Cyan
Write-Host "Verwendet k-Anonymity API - kein Download nötig!" -ForegroundColor Green
Write-Host

# Passwort-Quelle
$passwordsToCheck = @()

if ($PasswordFile -and (Test-Path $PasswordFile)) {
  $passwordsToCheck = Get-Content $PasswordFile
  Write-Host "Lade $($passwordsToCheck.Count) Passwörter aus Datei" -ForegroundColor Cyan
}
elseif ($Password) {
  $passwordsToCheck = @($Password)
}
else {
  Write-Host "Passwort eingeben (wird sichtbar angezeigt):" -ForegroundColor Yellow
  $plainPw = Read-Host "Passwort"
    
  if ($plainPw) {
    $passwordsToCheck = @($plainPw)
  }
}

if ($passwordsToCheck.Count -eq 0) {
  Write-Host "Keine Passwörter zum Prüfen!" -ForegroundColor Red
  exit 1
}

# Prüfen
Write-Host "`n=== Prüfe Passwörter ===" -ForegroundColor Cyan

$results = @()
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($pw in $passwordsToCheck) {
  $pwStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
  $result = Test-PasswordWithAPI -Password $pw
    
  $pwStopwatch.Stop()
    
  $pwDisplay = if ($pw.Length -gt 20) { 
    "$($pw.Substring(0, 3))***$($pw.Substring($pw.Length - 3))" 
  }
  else { 
    "***" 
  }
    
  Write-Host ""
  if ($result.Found) {
    Write-Host "❌ KOMPROMITTIERT: $pwDisplay" -ForegroundColor Red
    Write-Host "   Gesehen: $($result.Count) mal in Datenlecks" -ForegroundColor Yellow
  }
  else {
    Write-Host "✅ SICHER: $pwDisplay" -ForegroundColor Green
    Write-Host "   Nicht in bekannten Datenlecks gefunden" -ForegroundColor Gray
  }
    
  Write-Host "   Prüfzeit: $($pwStopwatch.ElapsedMilliseconds) ms" -ForegroundColor DarkGray
    
  $results += [PSCustomObject]@{
    Password    = $pwDisplay
    PasswordTxt = $pw
    Found       = $result.Found
    Count       = $result.Count
    Hash        = $result.Hash
    TimeMs      = $pwStopwatch.ElapsedMilliseconds
  }
}

$stopwatch.Stop()

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "ZUSAMMENFASSUNG:" -ForegroundColor Cyan
Write-Host "Geprüfte Passwörter: $($results.Count)"
Write-Host "Sicher: $(($results | Where-Object { -not $_.Found }).Count)" -ForegroundColor Green
Write-Host "Kompromittiert: $(($results | Where-Object { $_.Found }).Count)" -ForegroundColor Red
Write-Host "Gesamtzeit: $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) Sekunden"
Write-Host "Durchschnitt: $([Math]::Round($stopwatch.Elapsed.TotalMilliseconds / $results.Count, 2)) ms pro Passwort"
Write-Host ("=" * 60) -ForegroundColor Cyan

# Tabelle anzeigen
if ($PasswordFile) {
  $results | Format-Table -Property `
  @{Label = 'Password'; Expression = {
      if ($ShowPassword) { 
        $_.PasswordTxt
      }
      else { 
        "***" 
      } }; Width = 20
  } -Wrap

  $export = $results | Select-Object PasswordTxt, Found, Count
  # CSV Export optional
  if ($ExportCsv) {
    $csvPath = Join-Path $PSScriptRoot "pwnd_passwords_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $export | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "📄 CSV exportiert: $csvPath" -ForegroundColor Yellow
  }
}
# Zusatzinfo
Write-Host "`n💡 Tipp: Mit -ShowPassword werden Passwörter im Klartext angezeigt" -ForegroundColor DarkGray
Write-Host "💡 Tipp: Mit -ExportCsv wird eine CSV-Datei erstellt" -ForegroundColor DarkGray
