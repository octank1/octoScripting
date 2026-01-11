<#
.SYNOPSIS
    Wolli's PowerUser Control Center
.DESCRIPTION
    Zentrales Menü für alle Social Media Tools
.NOTES
    File Name      : socialmedia-suite.ps1
    Author         : Oliver C. Tank
    Prerequisite   : PowerShell 7.0+
    Copyright      : 2025 - MIT License
    Version        : 1.0.0
    Created        : 2025-01-15
    Last Modified  : 2025-12-28

.LINK
    https://github.com/octank1/octoScripts/tree/main/SocialMediaController

.EXAMPLE
    .\socialmedia-suite.ps1
    Startet das zentrale Menü für alle Social Media Tools

.COMPONENT
    Benötigt: lib/config-mgr.psm1

.LICENSE
    MIT License
    
    Copyright (c) 2025 Oliver C. Tank
    
    Details siehe .\LICENSE 
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ================================
# CONFIG LADEN
# ================================
Import-Module (Join-Path $PSScriptRoot "lib\config-mgr.psm1") -Force

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

# ================================
# KONFIGURATION
# ================================
$ScriptPath = $config.settings.general.scriptPath
$textColor = $config.settings.general.textColor
$subtextColor = $config.settings.general.subtextColor
$titleColor = $config.settings.general.titleColor
$highlightColor = $config.settings.general.highlightColor
$statusColor = $config.settings.general.statusColor
$errorColor = $config.settings.general.errorColor
$successColor = $config.settings.general.successColor
$menuColor = $config.settings.general.menuColor


# ==== SECRETS LADEN ====

# Für Bluesky-Scripts:
$BlueskyAppPassword = Get-Secret -Key "bluesky.appPassword"
if ([string]::IsNullOrEmpty($BlueskyAppPassword)) {
    Write-Host "`n⚠️  Bluesky App-Password nicht konfiguriert!" -ForegroundColor $errorColor
    Write-Host "📝 Bitte Setup durchführen: Start-ConfigSetup" -ForegroundColor $highlightColor
    Read-Host "Enter drücken zum Beenden"
    exit
}
$BlueskyHandle = $config.settings.bluesky.handle

# Für Discord-Scripts:
$discordToken = Get-Secret -Key "discord.userToken"
if ([string]::IsNullOrEmpty($discordToken)) {
    Write-Host "`n⚠️  Discord Token nicht konfiguriert!" -ForegroundColor $errorColor
    Write-Host "📝 Bitte Setup durchführen oder Token setzen:" -ForegroundColor $highlightColor
    Write-Host "   .\discord-token-update.ps1" -ForegroundColor $highlightColor
    Read-Host "Enter drücken zum Beenden"
    exit
}

$Tools = @{
    # Bluesky Tools
    "bsky-post" = @{
        Name = "Bluesky Post Editor PRO"
        Description = "Post erstellen mit Unicode-Formatierung & Threads"
        Script = "bsky-post-pro.ps1"
        Category = "Bluesky"
        OrderBy = 11
        Icon = "📝"
    }
    "bsky-chat" = @{
        Name = "Bluesky Chat Client"
        Description = "Interaktiver Chat mit Hauptmenü & mehrzeilig"
        Script = "bsky-chat.ps1"
        Category = "Bluesky"
        OrderBy = 12
        Icon = "💬"
    }
    "bsky-monitor" = @{
        Name = "Bluesky Chat Monitor"
        Description = "Live-Überwachung alle 60 Sekunden"
        Script = "bsky-chat-monitor.ps1"
        Category = "Bluesky"
        OrderBy = 13
        Icon = "🔔"
    }
    "bsky-post-export" = @{
        Name = "Bluesky Post Export"
        Description = "Eigene Posts nach Markdown exportieren"
        Script = "bsky-post-export.ps1"
        Category = "Bluesky"
        OrderBy = 14
        Icon = "📥"
    }
    "bsky-chat-export" = @{
        Name = "Bluesky Chat Export"
        Description = "Chats nach Markdown exportieren"
        Script = "bsky-chat-export.ps1"
        Category = "Bluesky"
        OrderBy = 15
        Icon = "📥"
    }
    
    # Discord Tools
    "discord-chat" = @{
        Name = "Discord Chat Client"
        Description = "Interaktiver Chat für DMs & Server (Console)"
        Script = "discord-chat.ps1"
        Category = "Discord"
        OrderBy = 20
        Icon = "💬"
    }
    "discord-export" = @{
        Name = "Discord Chat Export"
        Description = "Chats + Anhänge nach Markdown exportieren"
        Script = "discord-export.ps1"
        Category = "Discord"
        OrderBy = 21
        Icon = "📥"
    }
}

# Persistenz-Datei für letzte Auswahl
$LastChatFile = Join-Path $PSScriptRoot "last-chat.json"
# Notification-System
$script:LastCheckTime = Get-Date
$script:UnreadCounts = @{}

function Get-BlueskyNotifications {
    <#
    .SYNOPSIS
    Prüft auf neue Bluesky-Nachrichten
    #>
    try {
        
        # Bluesky Login (schnell & silent)
        $loginBody = @{
            identifier = $BlueskyHandle
            password = $BlueskyAppPassword
        } | ConvertTo-Json
        
        $session = Invoke-RestMethod -Uri "https://bsky.social/xrpc/com.atproto.server.createSession" `
            -Method POST -ContentType "application/json" -Body $loginBody -TimeoutSec 5
        
        # Chats mit Unread zählen
        $convos = Invoke-RestMethod -Uri "https://api.bsky.chat/xrpc/chat.bsky.convo.listConvos?limit=50" `
            -Headers @{ Authorization = "Bearer $($session.accessJwt)" } `
            -ContentType "application/json" -TimeoutSec 5
        
        $unreadTotal = ($convos.convos | Where-Object { $_.unreadCount -gt 0 } | Measure-Object -Property unreadCount -Sum).Sum
        
        return @{
            Success = $true
            Unread = $unreadTotal
            Chats = ($convos.convos | Where-Object { $_.unreadCount -gt 0 }).Count
        }
    } catch {
        return @{
            Success = $false
            Unread = 0
            Chats = 0
        }
    }
}

function Get-DiscordNotifications {
    <#
    .SYNOPSIS
    Prüft auf neue Discord-Nachrichten
    #>
    
    try {
        
        # Discord API Headers
        $headers = @{
            "Authorization" = $discordToken
            "Content-Type" = "application/json"
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        
        # Guilds (Server) abrufen
        $guilds = Invoke-RestMethod -Uri "https://discord.com/api/v10/users/@me/guilds" `
            -Headers $headers -Method GET -TimeoutSec 5
        
        # DMs abrufen
        $dms = Invoke-RestMethod -Uri "https://discord.com/api/v10/users/@me/channels" `
            -Headers $headers -Method GET -TimeoutSec 5
        
        # Ungelesene Nachrichten zählen
        $unreadDMs = 0
        $unreadDMCount = 0
        
        foreach ($dm in $dms) {
            # Last Message ID prüfen
            if ($dm.last_message_id) {
                try {
                    # Read State abrufen (komplexer, vereinfacht: Channels mit neuen Messages zählen)
                    # Discord speichert Read States, aber das ist komplex
                    # Vereinfachung: Channels mit recent activity
                    $messages = Invoke-RestMethod -Uri "https://discord.com/api/v10/channels/$($dm.id)/messages?limit=1" `
                        -Headers $headers -Method GET -TimeoutSec 3
                    
                    if ($messages -and $messages.Count -gt 0) {
                        $lastMsg = $messages[0]
                        # Wenn Nachricht von heute und nicht von uns
                        $msgTime = [DateTime]::Parse($lastMsg.timestamp)
                        if ($msgTime -gt (Get-Date).AddHours(-24) -and $lastMsg.author.id -ne (Invoke-RestMethod -Uri "https://discord.com/api/v10/users/@me" -Headers $headers -TimeoutSec 3).id) {
                            $unreadDMs++
                            $unreadDMCount++
                        }
                    }
                } catch {
                    # Fehler ignorieren (Rate Limit etc.)
                }
            }
        }
        
        return @{
            Success = $true
            Unread = $unreadDMs
            Chats = $unreadDMCount
            Guilds = $guilds.Count
        }
        
    } catch {
        return @{
            Success = $false
            Unread = 0
            Chats = 0
            Error = $_.Exception.Message
        }
    }
}

function Show-NotificationBar {
    param($BlueskyNotif, $DiscordNotif)
    
    # Cursor-Position merken
    $savedLeft = [Console]::CursorLeft
    $savedTop = [Console]::CursorTop
    
    # Zurück zum Anfang der Zeile (falls Update während Eingabe)
    if ($script:NotificationBarLine) {
        [Console]::SetCursorPosition(0, $script:NotificationBarLine)
    } else {
        [Console]::SetCursorPosition(0, 5)
    }
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor $menuColor
    
    # Bluesky Zeile
    Write-Host "║ " -NoNewline -ForegroundColor $menuColor
    
    if ($BlueskyNotif -and $BlueskyNotif.Success) {
        if ($BlueskyNotif.Unread -gt 0) {
            Write-Host "🦋 Bluesky: " -NoNewline -ForegroundColor $highlightColor
            $msgbsk = "$($BlueskyNotif.Unread) neue in $($BlueskyNotif.Chats) Chats 🔴"
            Write-Host $msgbsk -NoNewline -ForegroundColor Yellow
            $textLength = 11 + $msgbsk.Length
        } else {
            Write-Host "🦋 Bluesky: Keine neuen Nachrichten ✅" -NoNewline -ForegroundColor Green
            $textLength = 41
        }
    } else {
        Write-Host "🦋 Bluesky: Offline" -NoNewline -ForegroundColor Gray
        $textLength = 20
    }
    
    $spaces = [Math]::Max(1, 86 - $textLength)
    Write-Host (" " * $spaces) -NoNewline
    Write-Host "║" -ForegroundColor $menuColor
    
    # Discord Zeile
    Write-Host "║ " -NoNewline -ForegroundColor $menuColor
    
    if ($DiscordNotif -and $DiscordNotif.Success) {
        if ($DiscordNotif.Unread -gt 0) {
            Write-Host "💬 Discord: " -NoNewline -ForegroundColor $highlightColor
            $msg = "$($DiscordNotif.Unread) neue in $($DiscordNotif.Chats) DMs 🔴"
            Write-Host $msg -NoNewline -ForegroundColor $errorColor
            $textLength = 15 + $msg.Length
        } else {
            Write-Host "💬 Discord: Keine neuen Nachrichten ✅" -NoNewline -ForegroundColor $successColor
            $textLength = 41
        }
    } else {
        if ($DiscordNotif -and $DiscordNotif.Error) {
            Write-Host "💬 Discord: " -NoNewline -ForegroundColor $statusColor
            Write-Host "$($DiscordNotif.Error)" -NoNewline -ForegroundColor $statusColor
            $textLength = 13 + $DiscordNotif.Error.Length
        } else {
            Write-Host "💬 Discord: Offline" -NoNewline -ForegroundColor $statusColor
            $textLength = 21
        }
    }
    
    $spaces = [Math]::Max(1, 86 - $textLength)
    Write-Host (" " * $spaces) -NoNewline
    Write-Host "║" -ForegroundColor $menuColor
    
    Write-Host "╚════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor $menuColor
    
    # Cursor zurücksetzen (falls Update während Eingabe)
    if ($script:NotificationBarLine -and $savedTop -gt 0) {
        [Console]::SetCursorPosition($savedLeft, $savedTop)
    }
}

function Save-LastChat {
    param($ChatId, $ChatType)
    
    $data = @{
        ChatId = $ChatId
        ChatType = $ChatType  # "dm" oder "server"
        Timestamp = Get-Date -Format "o"
    } | ConvertTo-Json
    
    $data | Out-File -FilePath $LastChatFile -Encoding UTF8
}

function Get-LastChat {
    if (Test-Path $LastChatFile) {
        try {
            $data = Get-Content $LastChatFile -Raw | ConvertFrom-Json
            return $data
        } catch {
            return $null
        }
    }
    return $null
}

function Get-AllChats {
    <#
    .SYNOPSIS
    Lädt alle Bluesky-Chats für "Letzten Chat wiederherstellen"
    #>
    
    # Bluesky Credentials aus Script lesen
    $blueskyPostScript = Join-Path $ScriptPath "bsky-post-pro.ps1"
    
    if (-not (Test-Path $blueskyPostScript)) {
        Write-Host "⚠️ bsky-post-pro.ps1 nicht gefunden!" -ForegroundColor $errorColor
        return @()
    }
    
    try {
        # Handle & Password extrahieren
        $scriptContent = Get-Content $blueskyPostScript -Raw
        
        if ($scriptContent -match '\$BlueskyHandle\s*=\s*"([^"]+)"') {
            $blueskyHandle = $matches[1]
        } else {
            return @()
        }
        
        if ($scriptContent -match '\$BlueskyAppPassword\s*=\s*"([^"]+)"') {
            $blueskyPassword = $matches[1]
        } else {
            return @()
        }
        
        # Login
        $loginBody = @{
            identifier = $blueskyHandle
            password = $blueskyPassword
        } | ConvertTo-Json
        
        $session = Invoke-RestMethod -Uri "https://bsky.social/xrpc/com.atproto.server.createSession" `
            -Method POST -ContentType "application/json" -Body $loginBody -TimeoutSec 5
        
        # Chats laden
        $convos = Invoke-RestMethod -Uri "https://api.bsky.chat/xrpc/chat.bsky.convo.listConvos?limit=50" `
            -Headers @{ Authorization = "Bearer $($session.accessJwt)" } `
            -ContentType "application/json" -TimeoutSec 5
        
        return $convos.convos
        
    } catch {
        Write-Host "⚠️ Fehler beim Laden der Chats: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Show-ChatView {
    <#
    .SYNOPSIS
    Öffnet Bluesky Chat Client mit vorausgewähltem Chat
    #>
    param($Chat)
    
    # Chat-ID speichern
    Save-LastChat -ChatId $Chat.id -ChatType "bluesky"
    
    # Bluesky Chat Client starten
    $chatScript = Join-Path $ScriptPath "bsky-chat.ps1"
    
    if (Test-Path $chatScript) {
        Write-Host "🚀 Öffne Chat..." -ForegroundColor $successColor
        
        # TODO: Chat-ID als Parameter übergeben (erfordert Anpassung in bsky-chat.ps1)
        # Aktuell: Öffnet nur das Chat-Client-Tool
        & $chatScript
    } else {
        Write-Host "❌ bsky-chat.ps1 nicht gefunden!" -ForegroundColor $errorColor
        Start-Sleep -Seconds 2
    }
}

# ================================
# FUNKTIONEN
# ================================

function Show-Header {
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor $titleColor
    Write-Host "║                                                                                    ║" -ForegroundColor $titleColor
    Write-Host "║                         🦋 WOLLI WHITES SOCIALMEDIA SUITE 🦋                       ║" -ForegroundColor $titleColor
    Write-Host "║                                                                                    ║" -ForegroundColor $titleColor
    Write-Host "╚════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor $titleColor
    Write-Host ""
}

function Show-MainMenu {
    Show-Header
    
    # Live-Notifications prüfen (nur alle 30 Sekunden)
    $timeSinceCheck = (Get-Date) - $script:LastCheckTime
    if ($timeSinceCheck.TotalSeconds -gt 30 -or $script:UnreadCounts.Count -eq 0) {
        Write-Host "🔄 Prüfe Benachrichtigungen..." -ForegroundColor $statusColor
        
        $bskyNotif = Get-BlueskyNotifications
        $discordNotif = Get-DiscordNotifications
        
        $script:LastCheckTime = Get-Date
        $script:UnreadCounts = @{
            Bluesky = $bskyNotif
            Discord = $discordNotif
        }
    }
    
    # Notification Bar anzeigen (nur wenn erfolgreich geladen)
    if ($script:UnreadCounts.Count -gt 0 -and $script:UnreadCounts.Bluesky) {
        Show-NotificationBar -BlueskyNotif $script:UnreadCounts.Bluesky -DiscordNotif $script:UnreadCounts.Discord
    }
    $toolObjects = $Tools.Values | ForEach-Object {
        [PSCustomObject]$_
    }
    # Kategorien gruppieren (Tools vorher nach OrderBy sortieren!)
    $categories = $toolObjects | Sort-Object OrderBy | Group-Object -Property Category
    
    # Kategorien in gewünschter Reihenfolge (Bluesky zuerst)
    $categoryOrder = @("Bluesky", "Discord")
    $categories = $categories | Sort-Object { $categoryOrder.IndexOf($_.Name) }
    
    $menuIndex = 1
    $menuMap = @{}
    
    foreach ($category in $categories) {
        # Unread-Badge für Kategorie (mit NULL-Check!)
        $badge = ""
        if ($category.Name -eq "Bluesky" -and 
            $script:UnreadCounts.Bluesky -and 
            $script:UnreadCounts.Bluesky.Unread -gt 0) {
            $badge = " 🔴 $($script:UnreadCounts.Bluesky.Unread)"
        }
        elseif ($category.Name -eq "Discord" -and 
            $script:UnreadCounts.Discord -and 
            $script:UnreadCounts.Discord.Unread -gt 0) {
            $badge = " 🔴 $($script:UnreadCounts.Discord.Unread)"
        }
        # Write-Host ""
        # Write-Host ""
        # Write-Host ""
        Write-Host ""
        Write-Host "═══ $($category.Name) Tools$badge ═══" -ForegroundColor $menuColor
        Write-Host ""
        
        foreach ($tool in ($category.Group | Sort-Object OrderBy)) {
            $status = if (Test-Path (Join-Path $ScriptPath $tool.Script)) {
                "✅"
            } else {
                "❌"
            }
            
            # Spezielle Badges für Chat-Tools (mit NULL-Check!)
            $toolBadge = ""
            if ($tool.Script -eq "bsky-chat.ps1" -and 
                $script:UnreadCounts.Bluesky -and 
                $script:UnreadCounts.Bluesky.Unread -gt 0) {
                $toolBadge = " 🔴"
            }
            elseif ($tool.Script -eq "discord-chat.ps1" -and 
                $script:UnreadCounts.Discord -and 
                $script:UnreadCounts.Discord.Unread -gt 0) {
                $toolBadge = " 🔴"
            }
            
            Write-Host "  [$menuIndex] $status " -NoNewline -ForegroundColor $menuColor
            Write-Host "$($tool.Icon) $($tool.Name)$toolBadge" -ForegroundColor $highlightColor
            Write-Host "      $($tool.Description)" -ForegroundColor $menuColor
            Write-Host ""
            
            $menuMap[$menuIndex] = $tool
            $menuIndex++
        }
    }
      # Letzte Auswahl laden
    $lastChat = Get-LastChat
    
    if ($lastChat) {
        Write-Host "`n💭 Letzter Chat: " -NoNewline -ForegroundColor $highlightColor
        Write-Host "vom $($lastChat.Timestamp)" -ForegroundColor $subtextColor
        Write-Host "   Drücke [ENTER] um fortzufahren oder [n] um neu zu wählen..." -ForegroundColor $menuColor
        
        $quickChoice = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($quickChoice)) {
            # Direkt zum letzten Chat springen
            Write-Host "`n🚀 Öffne letzten Chat..." -ForegroundColor $statusColor
            
            $chats = Get-AllChats
            $selectedChat = $chats | Where-Object { $_.id -eq $lastChat.ChatId }
            
            if ($selectedChat) {
                Show-ChatView -Chat $selectedChat
                return  # Zurück zum Hauptmenü
            }
        }
    }

    Write-Host "═══════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    Write-Host ""
    Write-Host "  [0] Beenden" -ForegroundColor $menuColor
    Write-Host ""

    return $menuMap
}

function Start-Tool {
    param($Tool)
    
    $scriptPath = Join-Path $ScriptPath $Tool.Script
    
    if (-not (Test-Path $scriptPath)) {
        Write-Host "`n❌ Script nicht gefunden: $scriptPath" -ForegroundColor $errorColor
        Write-Host "   Bitte Pfad in Zeile 14 anpassen!" -ForegroundColor $warningColor
        Start-Sleep -Seconds 3
        return
    }
    
    Write-Host "`n🚀 Starte: $($Tool.Name)" -ForegroundColor $statusColor
    Write-Host "═══════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    Write-Host ""
    
    try {
        # Script ausführen
        & $scriptPath
    } catch {
        Write-Host "`n❌ Fehler beim Ausführen: $($_.Exception.Message)" -ForegroundColor $errorColor
    }
    
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    Read-Host "`nMit <Enter> zurück zum Menü"
}

function Show-AboutDialog {
    Show-Header
    
    Write-Host "╔════════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor $subtextColor
    Write-Host "║                              📖 ÜBER DIESES TOOL                                   ║" -ForegroundColor $subtextColor
    Write-Host "╠════════════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor $subtextColor
    Write-Host "║                                                                                    ║" -ForegroundColor $subtextColor
    Write-Host "║  🎯 Wolli's PowerUser Arsenal                                                      ║" -ForegroundColor $subtextColor
    Write-Host "║                                                                                    ║" -ForegroundColor $subtextColor
    Write-Host "║  Deine Tools:                                                                      ║" -ForegroundColor $subtextColor
    Write-Host "║  • 5x Bluesky Tools (Post, Chat, Monitor, Post-Export, Chat-Export                 ║" -ForegroundColor $subtextColor
    Write-Host "║  • 2x Discord Tools (Chat, Export)                                                 ║" -ForegroundColor $subtextColor
    Write-Host "║                                                                                    ║" -ForegroundColor $subtextColor
    Write-Host "║  Features:                                                                         ║" -ForegroundColor $subtextColor
    Write-Host "║  ✅ Unicode-Formatierung (𝗙𝗲𝘁𝘁, 𝘒𝘶𝘳𝘀𝘪𝘷, 𝙲𝚘𝚍𝚎)                                      ║" -ForegroundColor $subtextColor
    Write-Host "║  ✅ Thread-Support für lange Posts                                                 ║" -ForegroundColor $subtextColor
    Write-Host "║  ✅ Live Chat-Monitoring                                                           ║" -ForegroundColor $subtextColor
    Write-Host "║  ✅ Markdown-Export für Obsidian                                                   ║" -ForegroundColor $subtextColor
    Write-Host "║  ✅ Attachment-Download mit Bildanzeige                                            ║" -ForegroundColor $subtextColor
    Write-Host "║  ✅ UTF-8 Support für Umlaute                                                      ║" -ForegroundColor $subtextColor
    Write-Host "║  ✅ Session-Refresh & Auto-Recovery                                                ║" -ForegroundColor $subtextColor
    Write-Host "║  ✅ Live-Updates & Notification-Bar                                                ║" -ForegroundColor $subtextColor
    Write-Host "║                                                                                    ║" -ForegroundColor $subtextColor
    Write-Host "║  Created by: Wolli White 🍪                                                        ║" -ForegroundColor $subtextColor
    Write-Host "║  Powered by: GitHub Copilot (Claude Sonnet 4.5) 🤖                                 ║" -ForegroundColor $subtextColor
    Write-Host "║  Version: 1.0 - Dezember 2025 🎄                                                   ║" -ForegroundColor $subtextColor
    Write-Host "║                                                                                    ║" -ForegroundColor $subtextColor
    Write-Host "╚════════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor $subtextColor
    
    Write-Host ""
    Read-Host "Mit <Enter> zurück zum Hauptmenü"
}

# ================================
# MAIN LOOP mit Live-Updates
# ================================

while ($true) {
    $menuMap = Show-MainMenu
    
    # Notification-Bar-Position speichern (nach Header & NotificationBar)
    # Zeile nach dem letzten Show-NotificationBar Aufruf
    $script:NotificationBarLine = 5  # Header ist 5 Zeilen, dann kommt NotificationBar
    
    Write-Host "Wähle ein Tool (0-$($menuMap.Count)) oder '?' für Info: " -NoNewline -ForegroundColor $menuColor
    
    # Non-blocking input mit Live-Updates
    $inputBuffer = ""
    $lastNotificationCheck = Get-Date
    $notificationInterval = 30  # Sekunden
    
    while ($true) {
        # Notification-Update alle 30 Sekunden
        if (((Get-Date) - $lastNotificationCheck).TotalSeconds -ge $notificationInterval) {
            # Notifications aktualisieren
            $bskyNotif = Get-BlueskyNotifications
            $discordNotif = Get-DiscordNotifications
            
            $script:UnreadCounts = @{
                Bluesky = $bskyNotif
                Discord = $discordNotif
            }
            
            # Nur Notification-Bar neu zeichnen (sanft)
            Show-NotificationBar -BlueskyNotif $bskyNotif -DiscordNotif $discordNotif
            
            $lastNotificationCheck = Get-Date
        }
        
        # Auf Tastatur-Eingabe prüfen (non-blocking)
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            
            if ($key.Key -eq 'Enter') {
                Write-Host ""  # Newline
                $choice = $inputBuffer.Trim()
                break  # Zur Verarbeitung
            }
            elseif ($key.Key -eq 'Backspace') {
                if ($inputBuffer.Length -gt 0) {
                    $inputBuffer = $inputBuffer.Substring(0, $inputBuffer.Length - 1)
                    Write-Host "`b `b" -NoNewline
                }
            }
            else {
                $inputBuffer += $key.KeyChar
                Write-Host $key.KeyChar -NoNewline
            }
        }
        
        # Kurze Pause, um CPU zu schonen
        Start-Sleep -Milliseconds 100
    }
    
    if ($choice -eq "0") {
        Write-Host "`n👋 Auf Wiedersehen" -ForegroundColor $subtextColor
        Start-Sleep -Seconds 2
        break
    }
    
    if ($choice -eq "?") {
        Show-AboutDialog
        continue
    }
    
    try {
        $selectedTool = $menuMap[[int]$choice]
        if ($selectedTool) {
            Start-Tool -Tool $selectedTool
        } else {
            Write-Host "`n❌ Ungültige Auswahl!" -ForegroundColor $errorColor
            Start-Sleep -Seconds 1
        }
    } catch {
        Write-Host "`n❌ Ungültige Eingabe!" -ForegroundColor $errorColor
        Start-Sleep -Seconds 1
    }
}