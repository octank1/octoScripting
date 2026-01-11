<#
.SYNOPSIS
    Zentrale Konfigurationsverwaltung mit Verschlüsselung
.DESCRIPTION
    Verwaltet Config-Dateien und verschlüsselte Secrets
#>

# ================================
# .NET ASSEMBLY LADEN
# ================================
Add-Type -AssemblyName System.Security

# ================================
# PFADE
# ================================
$script:ConfigPath = Join-Path $PSScriptRoot "..\config"
$script:ConfigFile = Join-Path $ConfigPath "config.json"
$script:SecretsFile = Join-Path $ConfigPath "secrets.encrypted"
$script:ConfigTemplateFile = Join-Path $ConfigPath "config.template.json"

# ================================
# CONFIG ERSTELLEN/LADEN
# ================================

function Initialize-Config {
    <#
    .SYNOPSIS
    Erstellt Config-Ordner und Template falls nicht vorhanden
    #>
    
    # Config-Ordner erstellen
    if (-not (Test-Path $script:ConfigPath)) {
        New-Item -ItemType Directory -Path $script:ConfigPath -Force | Out-Null
        Write-Host "📁 Config-Ordner erstellt: $script:ConfigPath" -ForegroundColor Green
    }
    
    # Template erstellen falls nicht vorhanden
    if (-not (Test-Path $script:ConfigTemplateFile)) {
        $template = @{
            version = "1.0"
            settings = @{
                bluesky = @{
                    handle = "your-handle.bsky.social"
                    outputPath = "G:\Export\Bluesky"
                }
                discord = @{
                    outputPath = "G:\Export\Discord"
                }
                general = @{
                    scriptPath = "G:\Programmierung\Powershell"
                    obsidianVault = "G:\Obsidian"
                }
            }
        }
        
        $template | ConvertTo-Json -Depth 5 | Out-File -FilePath $script:ConfigTemplateFile -Encoding UTF8
        Write-Host "📋 Template erstellt: $script:ConfigTemplateFile" -ForegroundColor Green
    }
    
    # Prüfen ob config.json existiert
    if (-not (Test-Path $script:ConfigFile)) {
        Write-Host "`n⚠️  Keine Konfiguration gefunden!" -ForegroundColor Yellow
        Write-Host "📝 Bitte config.template.json -> config.json kopieren und ausfüllen:" -ForegroundColor Cyan
        Write-Host "   $script:ConfigTemplateFile" -ForegroundColor Gray
        Write-Host "   -> $script:ConfigFile" -ForegroundColor Gray
        
        # Template kopieren
        Copy-Item $script:ConfigTemplateFile $script:ConfigFile
        
        Write-Host "`n✅ config.json erstellt! Bitte anpassen und Script neu starten." -ForegroundColor Green
        
        return $false
    }
    
    return $true
}

function Get-Config {
    <#
    .SYNOPSIS
    Lädt die Konfiguration
    #>
    
    if (-not (Test-Path $script:ConfigFile)) {
        Write-Host "❌ config.json nicht gefunden!" -ForegroundColor Red
        return $null
    }
    
    try {
        $config = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
        return $config
    } catch {
        Write-Host "❌ Fehler beim Laden der Config: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# ================================
# SECRETS (VERSCHLÜSSELT)
# ================================

function Set-Secret {
    <#
    .SYNOPSIS
    Speichert ein Secret verschlüsselt (DPAPI)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key,
        
        [Parameter(Mandatory=$true)]
        [string]$Value
    )
    
    # Bestehende Secrets laden (wenn vorhanden)
    $secrets = @{}
    
    if (Test-Path $script:SecretsFile) {
        try {
            $encryptedData = Get-Content $script:SecretsFile -Raw -ErrorAction Stop
            
            # Prüfen ob Datei nicht leer ist
            if (-not [string]::IsNullOrWhiteSpace($encryptedData)) {
                $decryptedBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
                    [System.Convert]::FromBase64String($encryptedData.Trim()),
                    $null,
                    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
                )
                
                $decryptedJson = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
                
                # PSCustomObject -> Hashtable konvertieren (PS 5.x kompatibel)
                $secretsObj = $decryptedJson | ConvertFrom-Json
                
                foreach ($property in $secretsObj.PSObject.Properties) {
                    $secrets[$property.Name] = $property.Value
                }
                
                Write-Verbose "Bestehende Secrets geladen: $($secrets.Keys -join ', ')"
            }
        } catch {
            Write-Warning "Bestehende Secrets konnten nicht geladen werden: $($_.Exception.Message)"
            Write-Warning "Erstelle neue Secrets-Datei..."
            $secrets = @{}
        }
    }
    
    # Secret hinzufügen/aktualisieren
    $oldValue = $secrets[$Key]
    $secrets[$Key] = $Value
    
    if ($oldValue) {
        Write-Verbose "Secret '$Key' wird aktualisiert"
    } else {
        Write-Verbose "Secret '$Key' wird neu erstellt"
    }
    
    # Verschlüsseln und speichern
    try {
        $json = $secrets | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
            $bytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $encryptedString = [System.Convert]::ToBase64String($encryptedBytes)
        
        # Atomares Schreiben (erst in temp, dann umbenennen)
        $tempFile = "$script:SecretsFile.tmp"
        $encryptedString | Out-File -FilePath $tempFile -Encoding UTF8 -Force
        
        if (Test-Path $script:SecretsFile) {
            Remove-Item $script:SecretsFile -Force
        }
        
        Move-Item $tempFile $script:SecretsFile -Force
        
        Write-Host "🔒 Secret '$Key' gespeichert (verschlüsselt)" -ForegroundColor Green
        Write-Verbose "Alle Secrets in Datei: $($secrets.Keys -join ', ')"
        
    } catch {
        Write-Host "❌ Fehler beim Speichern: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

function Get-Secret {
    <#
    .SYNOPSIS
    Lädt ein verschlüsseltes Secret (DPAPI)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key
    )
    
    if (-not (Test-Path $script:SecretsFile)) {
        Write-Host "⚠️  Keine Secrets gefunden. Bitte Setup durchführen!" -ForegroundColor Yellow
        return $null
    }
    
    try {
        $encryptedData = Get-Content $script:SecretsFile -Raw
        $decryptedJson = [System.Text.Encoding]::UTF8.GetString(
            [System.Security.Cryptography.ProtectedData]::Unprotect(
                [System.Convert]::FromBase64String($encryptedData),
                $null,
                [System.Security.Cryptography.DataProtectionScope]::CurrentUser
            )
        )
        
        # PSCustomObject -> Hashtable konvertieren (PS 5.x kompatibel)
        $secretsObj = $decryptedJson | ConvertFrom-Json
        $secrets = @{}
        foreach ($property in $secretsObj.PSObject.Properties) {
            $secrets[$property.Name] = $property.Value
        }
        
        if ($secrets.ContainsKey($Key)) {
            return $secrets[$Key]
        } else {
            Write-Host "⚠️  Secret '$Key' nicht gefunden!" -ForegroundColor Yellow
            return $null
        }
        
    } catch {
        Write-Host "❌ Fehler beim Entschlüsseln: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

function Remove-Secret {
    <#
    .SYNOPSIS
    Löscht ein Secret
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key
    )
    
    if (-not (Test-Path $script:SecretsFile)) {
        return
    }
    
    try {
        $encryptedData = Get-Content $script:SecretsFile -Raw
        $decryptedJson = [System.Text.Encoding]::UTF8.GetString(
            [System.Security.Cryptography.ProtectedData]::Unprotect(
                [System.Convert]::FromBase64String($encryptedData),
                $null,
                [System.Security.Cryptography.DataProtectionScope]::CurrentUser
            )
        )
        
        # PSCustomObject -> Hashtable konvertieren (PS 5.x kompatibel)
        $secretsObj = $decryptedJson | ConvertFrom-Json
        $secrets = @{}
        foreach ($property in $secretsObj.PSObject.Properties) {
            $secrets[$property.Name] = $property.Value
        }
        
        if ($secrets.ContainsKey($Key)) {
            $secrets.Remove($Key)
            
            # Neu verschlüsseln
            $json = $secrets | ConvertTo-Json
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $encryptedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
                $bytes,
                $null,
                [System.Security.Cryptography.DataProtectionScope]::CurrentUser
            )
            $encryptedString = [System.Convert]::ToBase64String($encryptedBytes)
            
            $encryptedString | Out-File -FilePath $script:SecretsFile -Encoding UTF8
            
            Write-Host "🗑️ Secret '$Key' gelöscht" -ForegroundColor Gray
        }
        
    } catch {
        Write-Host "❌ Fehler: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ================================
# SETUP-ASSISTENT
# ================================

function Start-ConfigSetup {
    <#
    .SYNOPSIS
    Interaktiver Setup-Assistent
    #>
    
    Clear-Host
    
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                                                                ║" -ForegroundColor Cyan
    Write-Host "║           🔧 WOLLI'S POWERUSER CONFIG SETUP 🔧                ║" -ForegroundColor Cyan
    Write-Host "║                                                                ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Config initialisieren
    Initialize-Config | Out-Null
    
    Write-Host "📝 Secrets einrichten (verschlüsselt mit DPAPI):`n" -ForegroundColor Yellow
    
    # Bluesky App-Password
    Write-Host "🦋 Bluesky App-Password (optional, Enter zum Überspringen)" -ForegroundColor Cyan
    Write-Host "   (Erstellen auf: https://bsky.app/settings/app-passwords)" -ForegroundColor Gray
    $bskyPass = Read-Host "   Passwort" -AsSecureString
    $bskyPassPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($bskyPass)
    )
    if (-not [string]::IsNullOrEmpty($bskyPassPlain)) {
        Set-Secret -Key "bluesky.appPassword" -Value $bskyPassPlain
    }
    
    # Discord Token (optional)
    Write-Host "`n💬 Discord User Token (optional, Enter zum Überspringen)" -ForegroundColor Cyan
    Write-Host "   (Aus Browser DevTools - siehe discord-chat.ps1 Kommentare)" -ForegroundColor Gray
    $discordToken = Read-Host "   Token"
    
    if (-not [string]::IsNullOrEmpty($discordToken)) {
        Set-Secret -Key "discord.userToken" -Value $discordToken
    }
    
    Write-Host "`n✅ Setup abgeschlossen!" -ForegroundColor Green
    Write-Host "`n📋 Config-Dateien:" -ForegroundColor Cyan
    Write-Host "   Einstellungen: $script:ConfigFile" -ForegroundColor Gray
    Write-Host "   Secrets:       $script:SecretsFile (verschlüsselt)" -ForegroundColor Gray
    Write-Host ""
    
    Read-Host "Enter drücken zum Fortfahren"
}

# ================================
# EXPORT FUNCTIONS
# ================================

Export-ModuleMember -Function @(
    'Initialize-Config',
    'Get-Config',
    'Get-Secret',
    'Set-Secret',
    'Remove-Secret',
    'Start-ConfigSetup'
)