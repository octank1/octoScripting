<#
.SYNOPSIS
    Bluesky Chat Monitor - Live Chat Überwachung
.DESCRIPTION
    Überwacht alle Bluesky Chats im 60-Sekunden-Takt und zeigt neue Nachrichten an.
    Ermöglicht direktes Antworten.
.NOTES
    File Name      : bsky-chat-monitor.ps1
    Author         : Oliver C. Tank
    Prerequisite   : PowerShell 7.0+
    Copyright      : 2025 - MIT License
    Version        : 1.0.0
    Created        : 2025-01-15
    Last Modified  : 2025-12-28
.LINK
    https://github.com/octank1/octoScripts/tree/main/SocialMediaController
.EXAMPLE
    .\bsky-chat-monitor.ps1
.COMPONENT
    Benötigt: lib/config-mgr.psm1
.LICENSE
    MIT License
    
    Copyright (c) 2025 Oliver C. Tank
    
    Details siehe .\LICENSE 
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Sekunden zwischen den Checks nach neuen Nachrichten. Standard: 60")]
    [int]$CheckInterval = 60,  # Sekunden zwischen Checks
    
    [Parameter(Mandatory=$false, HelpMessage="Zeigt Zeitstempel bei neuen Nachrichten an.")]
    [switch]$ShowTimestamp
)


# ================================
# CONFIG LADEN
# ================================
Import-Module (Join-Path $PSScriptRoot "lib\config-mgr.psm1") -Force

# Config initialisieren
if (-not (Initialize-Config)) {
    Write-Host "`n⚠️  Bitte config.json anpassen und Script neu starten!" -ForegroundColor $errorColor
    Read-Host "Enter drücken zum Beenden"
    exit
}

# Einstellungen laden
$config = Get-Config

if (-not $config) {
    Write-Host "❌ Konfiguration konnte nicht geladen werden!" -ForegroundColor $errorColor
    Read-Host "Enter drücken zum Beenden"
    exit
}

# ==== SECRETS LADEN ====

# Für Bluesky-Scripts:
$Password = Get-Secret -Key "bluesky.appPassword"
if ([string]::IsNullOrEmpty($Password)) {
    Write-Host "`n⚠️  Bluesky App-Password nicht konfiguriert!" -ForegroundColor $errorColor
    Write-Host "📝 Bitte Setup durchführen: Start-ConfigSetup" -ForegroundColor $highlightColor
    Read-Host "Enter drücken zum Beenden"
    exit
}
$Username = $config.settings.bluesky.handle

# ==== KONFIGURATION ====
$BaseUrl  = "https://bsky.social/xrpc"
$ChatUrl  = "https://api.bsky.chat/xrpc"

$textColor = $config.settings.general.textColor
$subtextColor = $config.settings.general.subtextColor
$titleColor = $config.settings.general.titleColor
$highlightColor = $config.settings.general.highlightColor
$statusColor = $config.settings.general.statusColor
$errorColor = $config.settings.general.errorColor
$successColor = $config.settings.general.successColor
$menuColor = $config.settings.general.menuColor


# Globale Variablen für Session und Tracking
$script:AccessToken = $null
$script:MyDid = $null
$script:MyHandle = $null
$script:LastMessageTimestamps = @{}  # ChatID -> letzter Timestamp
$script:ChatPartners = @{}  # ChatID -> Partner-Info

# ==== FUNKTIONEN ====

function Connect-Bluesky {
    Write-Host "🔑 Verbinde mit Bluesky..." -ForegroundColor $statusColor
    
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
        
        Write-Host "✅ Verbunden als: $script:MyHandle" -ForegroundColor $successColor
        return $true
    } catch {
        Write-Host "❌ Verbindung fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor $errorColor
        return $false
    }
}

function Get-AllChats {
    try {
        $convos = Invoke-RestMethod -Uri "$ChatUrl/chat.bsky.convo.listConvos?limit=50" `
            -Headers @{ Authorization = "Bearer $script:AccessToken" } `
            -ContentType "application/json"
        
        return $convos.convos
    } catch {
        Write-Host "⚠️ Fehler beim Laden der Chats: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Get-NewMessages {
    param([string]$ChatId, [string]$SinceTimestamp)
    
    try {
        $url = "$ChatUrl/chat.bsky.convo.getMessages?convoId=$ChatId&limit=50"
        
        $response = Invoke-RestMethod -Uri $url `
            -Headers @{ Authorization = "Bearer $script:AccessToken" } `
            -ContentType "application/json"
        
        if (-not $response.messages) {
            return @()
        }
        
        # Nur neue Nachrichten seit letztem Check
        if ($SinceTimestamp) {
            $newMessages = $response.messages | Where-Object {
                try {
                    if ($_.sentAt -is [DateTime]) {
                        $msgTime = $_.sentAt
                        $lastTime = $SinceTimestamp
                    } else {
                        $msgTime = [DateTime]::Parse($_.sentAt)
                        $lastTime = [DateTime]::Parse($SinceTimestamp)
                    }
                    $msgTime -gt $lastTime
                } catch {
                    $false
                }
            }
        } else {
            # Beim ersten Check: nur die letzte Nachricht als Referenz
            $newMessages = @()
        }
        
        return $newMessages
    } catch {
        Write-Verbose "Fehler beim Laden von Nachrichten für Chat $ChatId"
        return @()
    }
}

function Send-ChatMessage {
    param(
        [string]$ChatId,
        [string]$Text
    )
    
    $sendBody = @{
        convoId = $ChatId
        message = @{
            text = $Text
        }
    } | ConvertTo-Json -Depth 3

    try {
        Invoke-RestMethod -Uri "$ChatUrl/chat.bsky.convo.sendMessage" `
            -Method POST `
            -ContentType "application/json" `
            -Headers @{ Authorization = "Bearer $script:AccessToken" } `
            -Body $sendBody
        
        return $true
    } catch {
        Write-Host "❌ Fehler beim Senden: $($_.Exception.Message)" -ForegroundColor $errorColor
        return $false
    }
}

function Show-NewMessage {
    param($Message, $ChatPartner, $ChatId)
    
    $time = try {
        if ($Message.sentAt -is [DateTime]) {
                $Message.sentAt.ToString("dd.MM. HH:mm:ss")
        } else {
            [DateTime]::Parse($Message.sentAt).ToString("dd.MM. HH:mm:ss") 
        }
    } catch { 
        "unknown" 
    }
    
    $isMe = $Message.sender.did -eq $script:MyDid
    
    if (-not $isMe) {
        # Nur eingehende Nachrichten anzeigen
        Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $highlightColor
        Write-Host "║ 📨 NEUE NACHRICHT" -NoNewline -ForegroundColor $highlightColor
        Write-Host (" " * 46) -NoNewline
        Write-Host "║" -ForegroundColor $highlightColor
        Write-Host "╠════════════════════════════════════════════════════════════════╣" -ForegroundColor $highlightColor
        Write-Host "║ Von: " -NoNewline -ForegroundColor $highlightColor
        Write-Host "$ChatPartner" -NoNewline -ForegroundColor Yellow
        Write-Host (" " * (58 - $ChatPartner.Length)) -NoNewline
        Write-Host "║" -ForegroundColor $highlightColor
        Write-Host "║ Zeit: $time" -NoNewline -ForegroundColor $highlightColor
        Write-Host (" " * (57 - $time.Length)) -NoNewline
        Write-Host "║" -ForegroundColor $highlightColor
        Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $highlightColor
        
        # Nachricht mit Zeilenumbruch-Support
        $lines = $Message.text -split "`n"
        foreach ($line in $lines) {
            $paddedLine = $line
            Write-Host "  $paddedLine" -ForegroundColor $textColor
        }
        
        # Antwort-Prompt
        Write-Host "`n💬 Antworten? (Enter = Nein, Text eingeben = Ja)" -ForegroundColor $menuColor
        $reply = Read-Host "Antwort"
        
        if (-not [string]::IsNullOrWhiteSpace($reply)) {
            if (Send-ChatMessage -ChatId $ChatId -Text $reply) {
                Write-Host "✅ Antwort gesendet!" -ForegroundColor $successColor
            }
        }
        
        [Console]::Beep(800, 200)  # Akustisches Signal
    }
}

function Initialize-ChatTracking {
    param($Chats)
    
    Write-Host "`n📊 Initialisiere Chat-Tracking für $($Chats.Count) Chats..." -ForegroundColor $statusColor
    
    foreach ($chat in $Chats) {
        $chatId = $chat.id
        
        # Partner-Info speichern
        $partner = $chat.members | Where-Object { $_.did -ne $script:MyDid }
        $partnerName = if ($partner.displayName) { $partner.displayName } else { 
            $partner.handle -replace '\.bsky\.social$', '' 
        }
        $script:ChatPartners[$chatId] = $partnerName
        
        # Letzten Timestamp speichern
        if ($chat.lastMessage -and $chat.lastMessage.sentAt) {
            $script:LastMessageTimestamps[$chatId] = $chat.lastMessage.sentAt
        } else {
            $script:LastMessageTimestamps[$chatId] = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        
        Write-Host "  ✓ $partnerName" -ForegroundColor $textColor
    }
    
    Write-Host "✅ Tracking initialisiert!" -ForegroundColor $successColor
}

function Start-ChatMonitoring {
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $titleColor
    Write-Host "║           🔔 BLUESKY CHAT MONITOR GESTARTET 🔔                 ║" -ForegroundColor $titleColor
    Write-Host "╠════════════════════════════════════════════════════════════════╣" -ForegroundColor $titleColor
    Write-Host "║ Überwachungsintervall: $CheckInterval Sekunden" -NoNewline -ForegroundColor $titleColor
    Write-Host (" " * (31 - $CheckInterval.ToString().Length)) -NoNewline
    Write-Host "║" -ForegroundColor $titleColor
    Write-Host "║ Drücke STRG+C zum Beenden" -NoNewline -ForegroundColor $titleColor
    Write-Host (" " * 38) -NoNewline
    Write-Host "║" -ForegroundColor $titleColor
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $titleColor
    Write-Host ""
    
    $checkCount = 0
    
    while ($true) {
        $checkCount++
        $timestamp = (Get-Date).ToString("HH:mm:ss")
        
        Write-Host "[$timestamp] 🔍 Check #$checkCount - Suche nach neuen Nachrichten..." -ForegroundColor $statusColor
        
        $chats = Get-AllChats
        
        if (-not $chats) {
            Write-Host "  ⚠️ Keine Chats gefunden oder Fehler" -ForegroundColor $errorColor
        } else {
            $totalNew = 0
            
            foreach ($chat in $chats) {
                # ⭐ NEU: Nur Chats mit ungelesenen Nachrichten verarbeiten
                if ($chat.unreadCount -eq 0) {
                    continue
                }
                $chatId = $chat.id
                $partnerName = $script:ChatPartners[$chatId]
                $lastTimestamp = $script:LastMessageTimestamps[$chatId]
                Write-Host "  📬 $($chat.unreadCount) ungelesene von $partnerName - lade Nachrichten..." -ForegroundColor $statusColor

                $newMessages = Get-NewMessages -ChatId $chatId -SinceTimestamp $lastTimestamp
                
                if ($newMessages -and $newMessages.Count -gt 0) {
                    Write-Host "  📬 $($newMessages.Count) neue Nachricht(en) von $partnerName" -ForegroundColor $successColor
                    
                    # Nachrichten chronologisch anzeigen
                    $sortedMessages = $newMessages | Sort-Object sentAt
                    
                    foreach ($msg in $sortedMessages) {
                        Show-NewMessage -Message $msg -ChatPartner $partnerName -ChatId $chatId
                        
                        # Timestamp aktualisieren
                        $script:LastMessageTimestamps[$chatId] = $msg.sentAt
                    }
                    
                    $totalNew += $newMessages.Count
                }
            }
            
            if ($totalNew -eq 0) {
                Write-Host "  ✓ Keine neuen Nachrichten" -ForegroundColor $successColor
                Write-Host "  📊 $($chats.Count) Chats überwacht, $(($chats | Measure-Object -Property unreadCount -Sum).Sum) ungelesen" -ForegroundColor $statusColor
            } else {
                Write-Host "`n  📊 Insgesamt $totalNew neue Nachricht(en) verarbeitet" -ForegroundColor $successColor
            }
        }
        
        Write-Host "  ⏳ Warte $CheckInterval Sekunden bis zum nächsten Check...`n" -ForegroundColor $subtextColor
        
        # Sleep mit Abbruch-Möglichkeit alle 5 Sekunden
        for ($i = 0; $i -lt $CheckInterval; $i += 5) {
            Start-Sleep -Seconds ([Math]::Min(5, $CheckInterval - $i))
            
            # Benutzer kann mit Space-Taste sofort checken
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'Spacebar') {
                    Write-Host "  ⚡ Manueller Check..." -ForegroundColor $highlightColor
                    break
                }
            }
        }
    }
}

# ==== MAIN SCRIPT ====

# Titel
Clear-Host
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $titleColor
Write-Host "║        🦋 BLUESKY CHAT MONITOR - by Wolli White 🦋             ║" -ForegroundColor $titleColor
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $titleColor
Write-Host ""

# Verbinden
if (-not (Connect-Bluesky)) {
    Write-Host "`n❌ Konnte nicht verbinden. Script wird beendet." -ForegroundColor $errorColor
    Read-Host "Enter drücken zum Beenden"
    exit
}

# Initiale Chats laden
Write-Host ""
$initialChats = Get-AllChats

if (-not $initialChats -or $initialChats.Count -eq 0) {
    Write-Host "❌ Keine Chats gefunden. Script wird beendet." -ForegroundColor $errorColor
    Read-Host "Enter drücken zum Beenden"
    exit
}

# Tracking initialisieren
Initialize-ChatTracking -Chats $initialChats

# Monitoring starten
try {
    Start-ChatMonitoring
} catch {
    Write-Host "`n❌ Fehler: $($_.Exception.Message)" -ForegroundColor $errorColor
} finally {
    Write-Host "`n👋 Chat Monitor beendet." -ForegroundColor $subtextColor
}