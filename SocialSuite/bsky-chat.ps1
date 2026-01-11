<#
.SYNOPSIS
    Bluesky Chat Client - Interaktive Console Version

.DESCRIPTION
    Interaktiver Chat-Client für Bluesky mit Hauptmenü, mehrzeiliger Eingabe,
    automatischer Session-Erneuerung und korrekter UTF-8-Codierung.

.NOTES
    File Name      : bsky-chat.ps1
    Author         : Oliver C. Tank
    Prerequisite   : PowerShell 7.0+
    Copyright      : 2025 - MIT License
    Version        : 1.0.0
    Created        : 2025-01-15
    Last Modified  : 2025-12-28

.LINK
    https://github.com/octank1/octoScripts/tree/main/SocialMediaController

.EXAMPLE
    .\bsky-chat.ps1
    Startet den interaktiven Chat-Client

.COMPONENT
    Benötigt: lib/config-mgr.psm1

.LICENSE
    MIT License
    
    Copyright (c) 2025 Oliver C. Tank
    
    Details siehe .\LICENSE 
#>

# ================================
# ENCODING SETUP
# ================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues = @{
    '*:Encoding' = 'utf8'
    'Out-File:Encoding' = 'utf8'
}

# ================================
# CONFIG LADEN
# ================================
$LibPath = Join-Path $PSScriptRoot "lib"
Import-Module (Join-Path $LibPath "config-mgr.psm1") -Force

# Config initialisieren
if (-not (Initialize-Config)) {
    Write-Host "`n⚠️  Bitte config.json anpassen und Script neu starten!" -ForegroundColor Yellow
    Read-Host "Enter drücken zum Beenden"
    exit
}

# Einstellungen laden
$config = Get-Config

if (-not $config) {
    Write-Host "❌ Konfiguration konnte nicht geladen werden!" -ForegroundColor Red
    Read-Host "Enter drücken zum Beenden"
    exit
}

# Secrets laden
$Password = Get-Secret -Key "bluesky.appPassword"

if ([string]::IsNullOrEmpty($Password)) {
    Write-Host "`n⚠️  Bluesky App-Password nicht konfiguriert!" -ForegroundColor Yellow
    Write-Host "📝 Bitte Setup durchführen:`n" -ForegroundColor Cyan
    Write-Host "   Import-Module .\lib\config-manager.ps1" -ForegroundColor Gray
    Write-Host "   Start-ConfigSetup" -ForegroundColor Gray
    Write-Host ""
    Read-Host "Enter drücken zum Beenden"
    exit
}

# ==== KONFIGURATION ====
$Username = $config.settings.bluesky.handle
$BaseUrl = "https://bsky.social/xrpc"
$ChatUrl = "https://api.bsky.chat/xrpc"

$textColor = $config.settings.general.textColor
$subtextColor = $config.settings.general.subtextColor
$titleColor = $config.settings.general.titleColor
$highlightColor = $config.settings.general.highlightColor
$statusColor = $config.settings.general.statusColor
$errorColor = $config.settings.general.errorColor
$successColor = $config.settings.general.successColor
$menuColor = $config.settings.general.menuColor

# Globale Variablen
$script:AccessToken = $null
$script:MyDid = $null
$script:MyHandle = $null
$script:AllChats = @()

# ================================
# FUNKTIONEN
# ================================

function Connect-Bluesky {
    param([bool]$Silent = $false)
    
    if (-not $Silent) {
        Write-Host "🔑 Melde mich bei Bluesky an..." -ForegroundColor $statusColor
    }
    
    $loginBody = @{
        identifier = $Username
        password   = $Password
    } | ConvertTo-Json

    try {
        $loginResponse = Invoke-RestMethod -Uri "$BaseUrl/com.atproto.server.createSession" `
            -Method POST -ContentType "application/json" -Body $loginBody
        
        $script:AccessToken = $loginResponse.accessJwt
        $script:MyDid = $loginResponse.did
        $script:MyHandle = $loginResponse.handle
        
        if (-not $Silent) {
            Write-Host "✅ Login erfolgreich als: $script:MyHandle" -ForegroundColor $successColor
            Write-Host "   DID: $script:MyDid" -ForegroundColor $subtextColor
        }
        return $true
    } catch {
        if (-not $Silent) {
            Write-Host "❌ Login fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor $errorColor
        }
        return $false
    }
}

function Test-SessionValid {
    <#
    .SYNOPSIS
    Prüft, ob die aktuelle Session noch gültig ist
    #>
    if ([string]::IsNullOrEmpty($script:AccessToken)) {
        return $false
    }
    
    try {
        # Schneller Test-Request
        $null = Invoke-RestMethod -Uri "$ChatUrl/chat.bsky.convo.listConvos?limit=1" `
            -Headers @{ Authorization = "Bearer $script:AccessToken" } `
            -ContentType "application/json" `
            -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}
function Invoke-WithSessionRefresh {
    <#
    .SYNOPSIS
    Führt einen API-Call aus und macht bei 400/401 automatisch Re-Login
    #>
    param(
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetries = 2
    )
    
    $attempt = 0
    
    while ($attempt -lt $MaxRetries) {
        try {
            return & $ScriptBlock
        } catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            
            # Bei 400 (Bad Request) oder 401 (Unauthorized) → Re-Login
            if ($statusCode -in @(400, 401) -and $attempt -lt ($MaxRetries - 1)) {
                Write-Host "⚠️  Session abgelaufen, erneuere Login..." -ForegroundColor $statusColor
                
                if (Connect-Bluesky -Silent $true) {
                    Write-Host "✅ Session erneuert!" -ForegroundColor $successColor
                    $attempt++
                    Start-Sleep -Milliseconds 500
                    continue
                } else {
                    throw "Re-Login fehlgeschlagen!"
                }
            }
            
            # Andere Fehler oder Max-Retries erreicht
            throw
        }
    }
}

function Get-AllChats {
    Write-Host "`n💬 Lade Chat-Liste..." -ForegroundColor Cyan
    
    try {
        return Invoke-WithSessionRefresh {
            $convos = Invoke-RestMethod -Uri "$ChatUrl/chat.bsky.convo.listConvos?limit=50" `
                -Headers @{ Authorization = "Bearer $script:AccessToken" } `
                -ContentType "application/json"
            
            if (-not $convos.convos -or $convos.convos.Count -eq 0) {
                Write-Host "ℹ️  Keine Chats gefunden." -ForegroundColor $statusColor
                return @()
            }
            
            $script:AllChats = $convos.convos
            return $script:AllChats
        }
    } catch {
        Write-Host "❌ Konnte Chats nicht abrufen: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Show-ChatList {
    param($Chats)
    
    Write-Host "`n═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    Write-Host "                              📋 VERFÜGBARE CHATS" -ForegroundColor $titleColor
    Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    
    for ($i = 0; $i -lt $Chats.Count; $i++) {
        $chat = $Chats[$i]
        
        # Partner-Name extrahieren
        $partner = $chat.members | Where-Object { $_.did -ne $script:MyDid }
        $userName = if ($partner.displayName) {
            $partner.displayName
        } else {
            $partner.handle -replace '\.bsky\.social$', ''
        }
        
        # Letzte Nachricht
        $lastMessage = if ($chat.lastMessage.text) {
            $chat.lastMessage.text -replace '[\r\n]+', ' '
        } else { 
            "(keine Nachricht)" 
        }
        
        # Ungelesen Marker
        $unreadMarker = if ($chat.unreadCount -gt 0) { " 🔴 ($($chat.unreadCount) neu)" } else { "" }
        
        Write-Host "`n[$i] " -NoNewline -ForegroundColor $subtextColor
        Write-Host $userName -NoNewline -ForegroundColor $highlightColor
        Write-Host $unreadMarker -ForegroundColor $errorColor
        Write-Host "    $lastMessage" -ForegroundColor $textColor
    }
    
    Write-Host "`n═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}


function Get-ChatMessages {
    param([string]$ChatId, [int]$Limit = 50)
    
    try {
        return Invoke-WithSessionRefresh {
            $url = "$ChatUrl/chat.bsky.convo.getMessages?convoId=$ChatId&limit=$Limit"
            
            $messages = Invoke-RestMethod -Uri $url `
                -Headers @{ Authorization = "Bearer $script:AccessToken" } `
                -ContentType "application/json"
            
            if ($messages.messages) {
                return $messages.messages | Sort-Object sentAt
            }
            return @()
        }
    } catch {
        Write-Host "❌ Konnte Nachrichten nicht abrufen: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Show-ChatMessages {
    param($Messages, $PartnerName)
    Clear-Host

    Write-Host "`n═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    Write-Host " 💬 Chat mit: $PartnerName" -ForegroundColor $titleColor
    Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    
    if (-not $Messages -or $Messages.Count -eq 0) {
        Write-Host "`nℹ️  Keine Nachrichten in diesem Chat." -ForegroundColor $statusColor
    } else {
        foreach ($msg in $Messages) {
            #$msg_sender = $msg.sender.handle -replace '\.bsky\.social$', ''
            $text = $msg.text
            $time = try { 
                [DateTime]::Parse($msg.sentAt).ToString("dd.MM. HH:mm") 
                $lastTimestamp = [DateTime]::Parse($msg.sentAt)
            } catch { 
                $msg.sentAt.ToString("dd.MM. HH:mm") 
                $lastTimestamp = $msg.sentAt
            }

            
            $isMe = $msg.sender.did -eq $script:MyDid
            $prefix = if ($isMe) { "▶️  Du" } else { "◀️  $PartnerName" }
            $color = if ($isMe) { $successColor } else { $highlightColor }
            
            # Mehrzeilige Nachrichten mit Zeilenumbruch
            $lines = $text -split "`n"
            
            # Header mit Sender und Zeit
            Write-Host "`n[$time] " -NoNewline -ForegroundColor $subtextColor
            Write-Host $prefix -ForegroundColor $color
            
            # Nachrichtentext (alle Zeilen)
            foreach ($line in $lines) {
                Write-Host "  $line" -ForegroundColor $textColor
            }
        }
    }
    
    Write-Host "`n═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    return $lastTimestamp
}

function Send-ChatMessage {
    param([string]$ChatId, [string]$Text)
    
    $maxLength = 900  # Sicherheitspuffer (echtes Limit ~1000)
    
    # Prüfen ob Text zu lang ist
    if ($Text.Length -le $maxLength) {
        # Normal senden (kurze Nachricht)
        return Send-SingleMessage -ChatId $ChatId -Text $Text
    }
    
    # Text aufteilen
    Write-Host "`n⚠️  Nachricht zu lang ($($Text.Length) Zeichen). Teile in mehrere Nachrichten..." -ForegroundColor $statusColor
    
    $parts = Split-LongMessage -Text $Text -MaxLength $maxLength
    
    Write-Host "📤 Sende $($parts.Count) Teilnachrichten..." -ForegroundColor $statusColor
    
    $success = $true
    for ($i = 0; $i -lt $parts.Count; $i++) {
        $part = $parts[$i]
        
        Write-Host "  [$($i+1)/$($parts.Count)] Sende Teil..." -NoNewline -ForegroundColor $statusColor
        
        if (Send-SingleMessage -ChatId $ChatId -Text $part) {
            Write-Host " ✅" -ForegroundColor $successColor
            
            # Kurze Pause zwischen Nachrichten (Rate Limit beachten)
            if ($i -lt $parts.Count - 1) {
                Start-Sleep -Milliseconds 500
            }
        } else {
            Write-Host " ❌" -ForegroundColor $errorColor
            $success = $false
            break
        }
    }
    
    return $success
}

function Send-SingleMessage {
    <#
    .SYNOPSIS
    Sendet eine einzelne Nachricht (intern)
    #>
    param([string]$ChatId, [string]$Text)
    
    $sendBody = @{
        convoId = $ChatId
        message = @{
            text = $Text
        }
    } | ConvertTo-Json -Depth 3

    try {
        return Invoke-WithSessionRefresh {
            # UTF-8 Encoding explizit setzen!
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($sendBody)
            
            Invoke-RestMethod -Uri "$ChatUrl/chat.bsky.convo.sendMessage" `
                -Method POST `
                -ContentType "application/json; charset=utf-8" `
                -Headers @{ Authorization = "Bearer $script:AccessToken" } `
                -Body $bodyBytes
            
            return $true
        }
    } catch {
        Write-Host "❌ Fehler: $($_.Exception.Message)" -ForegroundColor $errorColor
        return $false
    }
}

function Split-LongMessage {
    <#
    .SYNOPSIS
    Teilt lange Nachrichten intelligent an Zeilenumbrüchen oder Wortgrenzen
    #>
    param(
        [string]$Text,
        [int]$MaxLength = 900
    )
    
    $parts = @()
    $remaining = $Text
    
    while ($remaining.Length -gt 0) {
        if ($remaining.Length -le $MaxLength) {
            # Rest passt komplett
            $parts += $remaining
            break
        }
        
        # Chunk extrahieren
        $chunk = $remaining.Substring(0, $MaxLength)
        
        # Versuche an Zeilenumbruch zu trennen
        $lastNewline = $chunk.LastIndexOf("`n")
        
        if ($lastNewline -gt ($MaxLength * 0.5)) {
            # Newline gefunden (nicht zu nah am Anfang)
            $splitPos = $lastNewline + 1
        } else {
            # Versuche an Leerzeichen zu trennen
            $lastSpace = $chunk.LastIndexOf(" ")
            
            if ($lastSpace -gt ($MaxLength * 0.5)) {
                # Leerzeichen gefunden
                $splitPos = $lastSpace + 1
            } else {
                # Notfall: Hart schneiden (mitten im Wort)
                $splitPos = $MaxLength - 3  # Platz für "..."
            }
        }
        
        # Teil extrahieren
        $part = $remaining.Substring(0, $splitPos).TrimEnd()
        
        # "..." anhängen wenn nicht letzter Teil
        $parts += $part + "..."
        
        # Rest aktualisieren
        $remaining = $remaining.Substring($splitPos).TrimStart()
    }
    
    return $parts
}

function Read-MultilineInput {
    param([string]$Prompt = "Nachricht eingeben (Ende mit '##' in neuer Zeile, Abbruch mit 'q')")
    
    Write-Host "`n$Prompt" -ForegroundColor $titleColor
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $titleColor
    
    $lines = @()
    
    while ($true) {
        $line = Read-Host
        
        if ($line -eq "##") {
            break
        }
        
        if ($line -eq "q") {
            return $null
        }
        
        $lines += $line
    }
    
    return ($lines -join "`n")
}
$lastTimestamp = $null
function Set-TerminalTitle {
    param([string]$Title)
    
    # Für Windows Terminal und VS Code Terminal
    $host.UI.RawUI.WindowTitle = $Title
    
    # Alternative mit ANSI Escape-Sequenz (funktioniert in den meisten Terminals)
    Write-Host "`e]0;$Title`a" -NoNewline
}
function Show-ChatView {
    param($Chat)
    $lastNotificationCheck = Get-Date
    $notificationInterval = 10  # Sekunden
    try {
        Save-LastChat -ChatId $Chat.id -ChatType "dm"
    }
    catch {
    }

    $chatId = $Chat.id
    $partner = $Chat.members | Where-Object { $_.did -ne $script:MyDid }
    $partnerName = if ($partner.displayName) { $partner.displayName } else { $partner.handle -replace '\.bsky\.social$', '' }
    Set-TerminalTitle "Bluesky Chat - $partnerName"

    $messages = Get-ChatMessages -ChatId $chatId -Limit 50
    if ($null -eq $lastTimestamp ) {
        $lastTimestamp = Show-ChatMessages -Messages $messages -PartnerName $partnerName
    }
    $newestTimestamp = $null
    if ($messages -and $messages.Count -gt 0) {
        $lastMsg = $messages[-1]  # Letztes Element im Array
        
        if ($lastMsg.sentAt -is [DateTime]) {
            $newestTimestamp = $lastMsg.sentAt
        }
        else {
            $newestTimestamp = [DateTime]::Parse($lastMsg.sentAt)
        }
    }
    if ($null -ne $newestTimestamp -and $lastTimestamp -lt $newestTimestamp) {
        $lastTimestamp = Show-ChatMessages -Messages $messages -PartnerName $partnerName
    }
    Write-Host "`n[1] Nachricht senden  [2] Aktualisieren  [3] Zurück zum Hauptmenü" -ForegroundColor Cyan

    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            switch ($key.KeyChar) {
            "1" {
                # Nachricht senden
                $text = Read-MultilineInput
                
                if ($text) {
                    Write-Host "`n📤 Sende Nachricht..." -ForegroundColor $statusColor
                    
                    if (Send-ChatMessage -ChatId $chatId -Text $text) {
                        Write-Host "✅ Nachricht gesendet!" -ForegroundColor $successColor
                        Start-Sleep -Seconds 1
                    }
                }
            }
            "2" {
                # Aktualisieren (passiert automatisch durch Loop)
                Write-Host "`n🔄 Aktualisiere..." -ForegroundColor $statusColor
                $messages = Get-ChatMessages -ChatId $chatId -Limit 50
                $lastTimestamp = Show-ChatMessages -Messages $messages -PartnerName $partnerName
                Set-TerminalTitle "Bluesky Chat - $partnerName"
                Write-Host "`n[1] Nachricht senden  [2] Aktualisieren  [3] Zurück zum Hauptmenü" -ForegroundColor $menuColor
                Start-Sleep -Milliseconds 500
            }
            "3" {
                # Zurück
                return
            }
            default {
                Write-Host "❌ Ungültige Auswahl!" -ForegroundColor $errorColor
                Start-Sleep -Seconds 1
            }
        }
        }
        # Nachrichten anzeigen
       
        if (((Get-Date) - $lastNotificationCheck).TotalSeconds -ge $notificationInterval) {
            # Alle 30 Sekunden aktualisieren
            $lastNotificationCheck = Get-Date
            Write-Host "." -ForegroundColor Cyan -NoNewline
            $messages = Get-ChatMessages -ChatId $chatId -Limit 50
            if ($null -eq $lastTimestamp ) {
                $lastTimestamp = Show-ChatMessages -Messages $messages -PartnerName $partnerName
                Write-Host "`n[1] Nachricht senden  [2] Aktualisieren  [3] Zurück zum Hauptmenü" -ForegroundColor $menuColor
            }
            $newestTimestamp = $null
            if ($messages -and $messages.Count -gt 0) {
                $lastMsg = $messages[-1]  # Letztes Element im Array
                
                if ($lastMsg.sentAt -is [DateTime]) {
                    $newestTimestamp = $lastMsg.sentAt
                }
                else {
                    $newestTimestamp = [DateTime]::Parse($lastMsg.sentAt)
                }
            }
            #write-host "New: $newestTimestamp   Last: $lastTimestamp"
            if ($null -ne $newestTimestamp -and $lastTimestamp -lt $newestTimestamp) {
                $lastTimestamp = Show-ChatMessages -Messages $messages -PartnerName $partnerName
                Set-TerminalTitle "[*] Bluesky Chat - $partnerName"
                Write-Host "`n[1] Nachricht senden  [2] Aktualisieren  [3] Zurück" -ForegroundColor $menuColor
            }
            
            # Optionen
            
            #update-ChannelView -Channel $Channel -GuildName $GuildName
        }
        Start-Sleep -Milliseconds 200
    }
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Set-TerminalTitle "Bluesky Chat - Hauptmenü"
        Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        Write-Host "              🦋 BLUESKY CHAT CLIENT - by Wolli White 🦋" -ForegroundColor $titleColor
        Write-Host "              Eingeloggt als: $script:MyHandle" -ForegroundColor $titleColor
        Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        
        # Chats laden
        $chats = Get-AllChats
        if (-not $chats -or $chats.Count -eq 0) {
            Write-Host "`n❌ Keine Chats verfügbar." -ForegroundColor $errorColor
            Read-Host "`nEnter drücken zum Beenden"
            return
        }
        
        # Chat-Liste anzeigen
        Show-ChatList -Chats $chats
        
        Write-Host "`nGib die Chat-Nummer ein oder 'q' zum Beenden" -ForegroundColor $menuColor
        
        $selection = Read-Host "Auswahl"
        
        if ($selection -eq 'q') {
            Write-Host "`n👋 Tschüss!" -ForegroundColor $statusColor
            return
        }
        
        if ($selection -match '^\d+$' -and [int]$selection -lt $chats.Count) {
            $selectedChat = $chats[[int]$selection]
            Show-ChatView -Chat $selectedChat
        } else {
            Write-Host "`n❌ Ungültige Auswahl!" -ForegroundColor $errorColor
            Start-Sleep -Seconds 1
        }
    }
}

# ================================
# MAIN SCRIPT
# ================================

Clear-Host

Write-Host "╔════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor $titleColor
Write-Host "║             🦋 BLUESKY CHAT CLIENT - by Wolli White 🦋                    ║" -ForegroundColor $titleColor
Write-Host "╚════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor $titleColor
Write-Host ""

# Login
if (-not (Connect-Bluesky)) {
    Write-Host "`n❌ Konnte nicht verbinden. Script wird beendet." -ForegroundColor $errorColor
    Read-Host "Enter drücken zum Beenden"
    exit
}

# Hauptmenü starten
Show-MainMenu

Write-Host "`n👋 Auf Wiedersehen!" -ForegroundColor $statusColor