<#
.SYNOPSIS
    Discord Console Chat Client - User Token Version
.DESCRIPTION
    Interaktiver Discord-Chat für DMs & Server mit User Token
.NOTES
    Benötigt: Discord User Token (aus Browser DevTools)
    ⚠️ Token läuft ab! Muss regelmäßig erneuert werden.
    File Name      : discord-chat.ps1
    Author         : Oliver C. Tank
    Prerequisite   : PowerShell 7.0+
    Copyright      : 2025 - MIT License
    Version        : 1.0.0
    Created        : 2025-01-15
    Last Modified  : 2025-12-28
.EXAMPLE
    .\discord-chat.ps1
.LINK
    https://github.com/octank1/octoScripts/tree/main/SocialMediaController
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
    '*:Encoding'        = 'utf8'
    'Out-File:Encoding' = 'utf8'
}

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

# ==== SECRETS LADEN ====

# Für Discord-Scripts:
$UserToken = Get-Secret -Key "discord.userToken"
if ([string]::IsNullOrEmpty($UserToken)) {
    Write-Host "`n⚠️  Discord Token nicht konfiguriert!" -ForegroundColor Yellow
    Write-Host "📝 Bitte Setup durchführen oder Token setzen:" -ForegroundColor Cyan
    Write-Host "   .\discord-token-update.ps1" -ForegroundColor Gray
    Read-Host "Enter drücken zum Beenden"
    exit
}

# ==== KONFIGURATION ====
$DiscordApiBase = "https://discord.com/api/v10"

# Globale Variablen
$script:CurrentUser = $null
$script:AllGuilds = @()
$script:AllDMs = @()

$textColor = $config.settings.general.textColor
$subtextColor = $config.settings.general.subtextColor
$titleColor = $config.settings.general.titleColor
$highlightColor = $config.settings.general.highlightColor
$statusColor = $config.settings.general.statusColor
$errorColor = $config.settings.general.errorColor
$successColor = $config.settings.general.successColor
$menuColor = $config.settings.general.menuColor

# ================================
# TOKEN ANLEITUNG
# ================================
<#
SO BEKOMMST DU DEINEN USER-TOKEN:

1. Discord im Browser öffnen (Chrome/Edge)
2. F12 drücken (DevTools)
3. Tab "Console" / "Konsole"
4. Folgenden Code eingeben und Enter:

   (webpackChunkdiscord_app.push([[''],{},e=>{m=[];for(let c in e.c)m.push(e.c[c])}]),m).find(m=>m?.exports?.default?.getToken!==void 0).exports.default.getToken()

5. Der angezeigte String ist dein Token
6. Kopieren und oben in Zeile 27 eintragen

⚠️ WICHTIG: Token NIEMALS teilen! Wie ein Passwort!
⚠️ Token läuft nach einiger Zeit ab → dann neu holen
#>



# ================================
# FUNKTIONEN
# ================================

function Get-DiscordHeaders {
    return @{
        "Authorization" = $UserToken  # USER Token (nicht "Bot")
        "Content-Type"  = "application/json"
        "User-Agent"    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    }
}

function Connect-Discord {
    Write-Host "🔑 Verbinde mit Discord..." -ForegroundColor $statusColor
    
    if ([string]::IsNullOrEmpty($UserToken)) {
        Write-Host "❌ User-Token fehlt! Bitte in Zeile 27 eintragen." -ForegroundColor $errorColor
        Write-Host "`n📖 Siehe Anleitung oben im Script (Zeile 33-48)" -ForegroundColor $statusColor
        return $false
    }
    
    try {
        # User Info abrufen
        $script:CurrentUser = Invoke-RestMethod -Uri "$DiscordApiBase/users/@me" `
            -Headers (Get-DiscordHeaders) `
            -Method GET
        
        Write-Host "✅ Verbunden als: $($script:CurrentUser.username)#$($script:CurrentUser.discriminator)" -ForegroundColor $successColor
        Write-Host "   User ID: $($script:CurrentUser.id)" -ForegroundColor $subtextColor
        return $true
    }
    catch {
        Write-Host "❌ Verbindung fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor $errorColor
        Write-Host "   Token abgelaufen? Neuen Token aus Browser holen!" -ForegroundColor $statusColor
        return $false
    }
}

function Get-AllGuilds {
    try {
        $guilds = Invoke-RestMethod -Uri "$DiscordApiBase/users/@me/guilds" `
            -Headers (Get-DiscordHeaders) `
            -Method GET
        
        $script:AllGuilds = $guilds
        return $guilds
    }
    catch {
        Write-Host "⚠️ Fehler beim Laden der Server: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Get-GuildChannels {
    param([string]$GuildId)
    
    try {
        $channels = Invoke-RestMethod -Uri "$DiscordApiBase/guilds/$GuildId/channels" `
            -Headers (Get-DiscordHeaders) `
            -Method GET
        
        # Nur Text-Channels (Type 0 = Text, 5 = Announcement)
        return $channels | Where-Object { $_.type -in @(0, 5) } | Sort-Object position
    }
    catch {
        Write-Host "⚠️ Fehler beim Laden der Channels: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Get-DMChannels {
    try {
        $dms = Invoke-RestMethod -Uri "$DiscordApiBase/users/@me/channels" `
            -Headers (Get-DiscordHeaders) `
            -Method GET
        
        $script:AllDMs = $dms
        return $dms
    }
    catch {
        Write-Host "⚠️ Fehler beim Laden der DMs: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Get-ChannelMessages {
    param([string]$ChannelId, [int]$Limit = 50)
    
    try {
        $url = "$DiscordApiBase/channels/$ChannelId/messages?limit=$Limit"
        
        $messages = Invoke-RestMethod -Uri $url `
            -Headers (Get-DiscordHeaders) `
            -Method GET
        
        # Chronologisch sortieren (älteste zuerst)
        return $messages | Sort-Object timestamp
    }
    catch {
        Write-Host "⚠️ Fehler beim Laden der Nachrichten: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Send-DiscordMessage {
    param(
        [string]$ChannelId,
        [string]$Content,
        [string]$AttachmentPath = $null
    )
    
    try {
        if ($AttachmentPath -and (Test-Path $AttachmentPath)) {
            # Mit Anhang
            Send-DiscordMessageWithAttachment -ChannelId $ChannelId -Content $Content -FilePath $AttachmentPath
        }
        else {
            # Nur Text
            $body = @{
                content = $Content
            } | ConvertTo-Json
            
            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            
            Invoke-RestMethod -Uri "$DiscordApiBase/channels/$ChannelId/messages" `
                -Method POST `
                -Headers (Get-DiscordHeaders) `
                -Body $bodyBytes
            Set-TerminalTitle "Discord Chat - $channelName"
            return $true
        }
    }
    catch {
        Write-Host "❌ Fehler beim Senden: $($_.Exception.Message)" -ForegroundColor $errorColor
        return $false
    }
}

function Send-DiscordMessageWithAttachment {
    param(
        [string]$ChannelId,
        [string]$Content,
        [string]$FilePath
    )
    
    try {
        # Multipart/form-data für Datei-Upload
        $boundary = [System.Guid]::NewGuid().ToString()
        
        $fileName = [System.IO.Path]::GetFileName($FilePath)
        $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
        
        # Multipart Body erstellen
        $bodyLines = @(
            "--$boundary",
            "Content-Disposition: form-data; name=`"content`"",
            "",
            $Content,
            "--$boundary",
            "Content-Disposition: form-data; name=`"file`"; filename=`"$fileName`"",
            "Content-Type: application/octet-stream",
            ""
        )
        
        $bodyString = $bodyLines -join "`r`n"
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyString + "`r`n")
        
        # File bytes hinzufügen
        $endBytes = [System.Text.Encoding]::UTF8.GetBytes("`r`n--$boundary--`r`n")
        
        $fullBody = New-Object byte[] ($bodyBytes.Length + $fileBytes.Length + $endBytes.Length)
        [Array]::Copy($bodyBytes, 0, $fullBody, 0, $bodyBytes.Length)
        [Array]::Copy($fileBytes, 0, $fullBody, $bodyBytes.Length, $fileBytes.Length)
        [Array]::Copy($endBytes, 0, $fullBody, $bodyBytes.Length + $fileBytes.Length, $endBytes.Length)
        
        $headers = @{
            "Authorization" = "Bot $BotToken"
            "Content-Type"  = "multipart/form-data; boundary=$boundary"
        }
        
        Invoke-RestMethod -Uri "$DiscordApiBase/channels/$ChannelId/messages" `
            -Method POST `
            -Headers $headers `
            -Body $fullBody
        
        return $true
    }
    catch {
        Write-Host "❌ Fehler beim Datei-Upload: $($_.Exception.Message)" -ForegroundColor $errorColor
        return $false
    }
}

function Show-Messages {
    param($Messages, $ChannelName)
    $lastTimestamp = $null

    Clear-Host 
    Write-Host "`n═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    Write-Host " 💬 Channel: #$ChannelName" -ForegroundColor $titleColor
    Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    
    if (-not $Messages -or $Messages.Count -eq 0) {
        Write-Host "`nℹ️  Keine Nachrichten in diesem Channel." -ForegroundColor $statusColor
    }
    else {
        foreach ($msg in $Messages) {
            $author = if ($msg.author.global_name) {
                $msg.author.global_name
            }
            else {
                "$($msg.author.username)#$($msg.author.discriminator)"
            }
            
            if ($msg.timestamp -is [DateTime]) {
                $timestamp_dt = $msg.timestamp
                $timestamp = $msg.timestamp.ToString("dd.MM. HH:mm")
            }
            else {
                $timestamp_dt = [DateTime]::Parse($msg.timestamp)
                $timestamp = [DateTime]::Parse($msg.timestamp).ToString("dd.MM. HH:mm")
            }
            if ($null -eq $lastTimestamp -or $lastTimestamp -lt $timestamp_dt) {
                $lastTimestamp = $timestamp_dt
            }
            
            $isBot = $msg.author.bot -eq $true
            $prefix = if ($isBot) { "🤖 $author" } else { "👤 $author" }
            $color = if ($isBot) { $statusColor } else { $highlightColor }
            
            # Nachricht anzeigen
            Write-Host "`n[$timestamp] " -NoNewline -ForegroundColor $subtextColor
            Write-Host $prefix -ForegroundColor $color
            
            if ($msg.content) {
                $lines = $msg.content -split "`n"
                foreach ($line in $lines) {
                    Write-Host "  $line" -ForegroundColor $textColor
                }
            }
            
            # Anhänge
            if ($msg.attachments -and $msg.attachments.Count -gt 0) {
                Write-Host "  📎 Anhänge:" -ForegroundColor $subtextColor
                foreach ($att in $msg.attachments) {
                    Write-Host "    - $($att.filename) ($([Math]::Round($att.size/1024, 2)) KB)" -ForegroundColor $subtextColor
                    Write-Host "      $($att.url)" -ForegroundColor $subtextColor
                }
            }
            
            # Embeds
            if ($msg.embeds -and $msg.embeds.Count -gt 0) {
                Write-Host "  🔗 Embed: $($msg.embeds[0].title)" -ForegroundColor $subtextColor
            }
            
            # Reactions
            if ($msg.reactions -and $msg.reactions.Count -gt 0) {
                $reactions = ($msg.reactions | ForEach-Object { "$($_.emoji.name) x$($_.count)" }) -join ", "
                Write-Host "  👍 $reactions" -ForegroundColor $statusColor
            }
        }
    }
    
    Write-Host "`n═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
    return $lastTimestamp
}

function Read-MultilineInput {
    param([string]$Prompt = "Nachricht eingeben (Ende mit '##', Anhang mit '@datei.jpg', Abbruch mit 'q')")
    
    Write-Host "`n$Prompt" -ForegroundColor $highlightColor
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $highlightColor
    
    $lines = @()
    $attachment = $null
    
    while ($true) {
        $line = Read-Host
        
        if ($line -eq "##") {
            break
        }
        
        if ($line -eq "q") {
            return $null, $null
        }
        
        # Anhang erkennen (@datei.jpg)
        if ($line -match '^@(.+)$') {
            $filePath = $matches[1]
            if (Test-Path $filePath) {
                $attachment = $filePath
                Write-Host "✅ Anhang hinzugefügt: $filePath" -ForegroundColor $successColor
                continue
            }
            else {
                Write-Host "⚠️ Datei nicht gefunden: $filePath" -ForegroundColor $errorColor
                continue
            }
        }
        
        $lines += $line
    }
    
    $content = ($lines -join "`n").Trim()
    return $content, $attachment
}
$lastTimestamp = $null

function update-ChannelView {
    param($Channel, $GuildName)
    
    $channelId = $Channel.id
    $channelName = $Channel.name

    # Clear-Host       
    # Nachrichten laden
    $messages = Get-ChannelMessages -ChannelId $channelId -Limit 30
    if ($null -eq $lastTimestamp ) {
        $lastTimestamp = Show-Messages -Messages $messages -ChannelName "$GuildName / $channelName"    
    }
    $newestTimestamp = $null
    if ($messages -and $messages.Count -gt 0) {
        $lastMsg = $messages[-1]  # Letztes Element im Array
        
        if ($lastMsg.timestamp -is [DateTime]) {
            $newestTimestamp = $lastMsg.timestamp
        }
        else {
            $newestTimestamp = [DateTime]::Parse($lastMsg.timestamp)
        }
    }
    if ($null -ne $newestTimestamp -and $lastTimestamp -lt $newestTimestamp) {
        $lastTimestamp = Show-Messages -Messages $messages -ChannelName "$GuildName / $channelName"
    }
    
    # Optionen
    Write-Host "`n[1] Nachricht senden  [2] Aktualisieren  [3] Zurück" -ForegroundColor $menuColor
    return $lastTimestamp
  
   
}
function Set-TerminalTitle {
    param([string]$Title)
    
    # Für Windows Terminal und VS Code Terminal
    $host.UI.RawUI.WindowTitle = $Title
    
    # Alternative mit ANSI Escape-Sequenz (funktioniert in den meisten Terminals)
    Write-Host "`e]0;$Title`a" -NoNewline
}
function Show-ChannelView {
    param($Channel, $GuildName)
    
    $channelId = $Channel.id
    $channelName = $Channel.name
    $lastNotificationCheck = Get-Date
    $notificationInterval = 10  # Sekunden
    $lastTimestamp = update-ChannelView -Channel $Channel -GuildName $GuildName
    Set-TerminalTitle "Discord Chat - $channelName"
    while ($true) {
        # Auf Tastatur-Eingabe prüfen (non-blocking)
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            switch ($key.KeyChar) {
                "1" {
                    # Nachricht senden
                    $content, $attachment = Read-MultilineInput
                
                    if ($content -or $attachment) {
                        Write-Host "`n📤 Sende Nachricht..." -ForegroundColor $statusColor
                    
                        if (Send-DiscordMessage -ChannelId $channelId -Content $content -AttachmentPath $attachment) {
                            Write-Host "✅ Nachricht gesendet!" -ForegroundColor $successColor
                            Start-Sleep -Seconds 1
                        }
                    }
                }
                "2" {
                    # Aktualisieren
                    Write-Host "`n🔄 Aktualisiere..." -ForegroundColor $statusColor
                    $messages = Get-ChannelMessages -ChannelId $channelId -Limit 30
                    $lastTimestamp = Show-Messages -Messages $messages -ChannelName "$GuildName / $channelName"    
                    Write-Host "`n[1] Nachricht senden  [2] Aktualisieren  [3] Zurück" -ForegroundColor $menuColor
                    Set-TerminalTitle "Discord Chat - $channelName"
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
        
        if (((Get-Date) - $lastNotificationCheck).TotalSeconds -ge $notificationInterval) {
            # Alle 30 Sekunden aktualisieren
            $lastNotificationCheck = Get-Date
            Write-Host "." -ForegroundColor $statusColor -NoNewline
            $messages = Get-ChannelMessages -ChannelId $channelId -Limit 30
            if ($null -eq $lastTimestamp ) {
                $lastTimestamp = Show-Messages -Messages $messages -ChannelName "$GuildName / $channelName"    
                Write-Host "`n[1] Nachricht senden  [2] Aktualisieren  [3] Zurück" -ForegroundColor $menuColor
            }
            $newestTimestamp = $null
            if ($messages -and $messages.Count -gt 0) {
                $lastMsg = $messages[-1]  # Letztes Element im Array
                
                if ($lastMsg.timestamp -is [DateTime]) {
                    $newestTimestamp = $lastMsg.timestamp
                }
                else {
                    $newestTimestamp = [DateTime]::Parse($lastMsg.timestamp)
                }
            }
            
            #write-host "New: $newestTimestamp   Last: $lastTimestamp"
            if ($null -ne $newestTimestamp -and $lastTimestamp -lt $newestTimestamp) {
                $lastTimestamp = Show-Messages -Messages $messages -ChannelName "$GuildName / $channelName"
                Set-TerminalTitle "[*] Discord Chat - $channelName"
                Write-Host "`n[1] Nachricht senden  [2] Aktualisieren  [3] Zurück" -ForegroundColor $menuColor
            }
            
            # Optionen
            
            #update-ChannelView -Channel $Channel -GuildName $GuildName
        }
        Start-Sleep -Milliseconds 200
    }
}
function Show-GuildList {
    while ($true) {
        Clear-Host
        
        Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        Write-Host " 🏰 Server" -ForegroundColor $titleColor
        Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        
        Write-Host "`n📥 Lade Server..." -ForegroundColor $statusColor
        $guilds = Get-AllGuilds
        
        if (-not $guilds -or $guilds.Count -eq 0) {
            Write-Host "`n⚠️ Keine Server gefunden!" -ForegroundColor $errorColor
            Read-Host "`nEnter drücken zum Zurückkehren"
            return
        }
        
        Write-Host "`n═══ Deine Server ═══`n" -ForegroundColor $titleColor
        
        for ($i = 0; $i -lt $guilds.Count; $i++) {
            $guild = $guilds[$i]
            Write-Host "  [$i] " -NoNewline -ForegroundColor $subtextColor
            Write-Host "🏰 $($guild.name)" -ForegroundColor $highlightColor
        }
        
        Write-Host "`n═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        Write-Host "`nServer-Nummer oder 'q' für zurück: " -NoNewline -ForegroundColor $menuColor
        $selection = Read-Host
        
        if ($selection -eq 'q') {
            return
        }
        
        if ($selection -match '^\d+$' -and [int]$selection -lt $guilds.Count) {
            $selectedGuild = $guilds[[int]$selection]
            Show-GuildChannels -Guild $selectedGuild
        }
        else {
            Write-Host "`n❌ Ungültige Auswahl!" -ForegroundColor $errorColor
            Start-Sleep -Seconds 1
        }
    }
}
function Show-GuildChannels {
    param($Guild)
    
    while ($true) {
        Clear-Host
        
        Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        Write-Host " 🏰 Server: $($Guild.name)" -ForegroundColor $titleColor
        Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        
        Write-Host "`n📥 Lade Channels..." -ForegroundColor $statusColor
        $channels = Get-GuildChannels -GuildId $Guild.id
        
        if (-not $channels -or $channels.Count -eq 0) {
            Write-Host "❌ Keine Channels gefunden!" -ForegroundColor $errorColor
            Read-Host "`nEnter drücken zum Zurückkehren"
            return
        }
        
        Write-Host "`n═══ Text Channels ═══`n" -ForegroundColor $highlightColor
        
        for ($i = 0; $i -lt $channels.Count; $i++) {
            $ch = $channels[$i]
            Write-Host "  [$i] #$($ch.name)" -ForegroundColor $subtextColor
            if ($ch.topic) {
                Write-Host "      $($ch.topic.Substring(0, [Math]::Min(60, $ch.topic.Length)))" -ForegroundColor $textColor
            }
        }
        
        Write-Host "`n═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        Write-Host "`nChannel-Nummer oder 'q' für zurück: " -NoNewline -ForegroundColor $menuColor
        $selection = Read-Host
        
        if ($selection -eq 'q') {
            return
        }
        
        if ($selection -match '^\d+$' -and [int]$selection -lt $channels.Count) {
            $selectedChannel = $channels[[int]$selection]
            Show-ChannelView -Channel $selectedChannel -GuildName $Guild.name
        }
        else {
            Write-Host "`n❌ Ungültige Auswahl!" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
function Show-DMList {
    while ($true) {
        Clear-Host
        
        Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        Write-Host " 💬 Direktnachrichten" -ForegroundColor $titleColor
        Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        
        Write-Host "`n📥 Lade DMs..." -ForegroundColor $statusColor
        $dms = Get-DMChannels
        
        if (-not $dms -or $dms.Count -eq 0) {
            Write-Host "`n⚠️ Keine DMs gefunden!" -ForegroundColor $warningColor
            Read-Host "`nEnter drücken zum Zurückkehren"
            return
        }
        
        Write-Host "`n═══ Deine DMs ═══`n" -ForegroundColor $highlightColor
        
        for ($i = 0; $i -lt $dms.Count; $i++) {
            $dm = $dms[$i]
            
            # Partner-Name
            $partner = if ($dm.recipients -and $dm.recipients.Count -gt 0) {
                $recipient = $dm.recipients[0]
                if ($recipient.global_name) {
                    $recipient.global_name
                }
                else {
                    "$($recipient.username)#$($recipient.discriminator)"
                }
            }
            else {
                "Unknown"
            }
            
            Write-Host "  [$i] " -NoNewline -ForegroundColor $subtextColor
            Write-Host "💬 $partner" -ForegroundColor $highlightColor
            
            # Letzte Nachricht
            if ($dm.last_message_id) {
                Write-Host "      Letzter Chat vorhanden" -ForegroundColor $textColor
            }
        }
        
        Write-Host "`n═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        Write-Host "`nDM-Nummer oder 'q' für zurück: " -NoNewline -ForegroundColor $menuColor
        $selection = Read-Host
        
        if ($selection -eq 'q') {
            return
        }
        
        if ($selection -match '^\d+$' -and [int]$selection -lt $dms.Count) {
            $selectedDM = $dms[[int]$selection]
            
            # Partner-Name für Anzeige
            $partner = if ($selectedDM.recipients -and $selectedDM.recipients.Count -gt 0) {
                $recipient = $selectedDM.recipients[0]
                if ($recipient.global_name) {
                    $recipient.global_name
                }
                else {
                    "$($recipient.username)#$($recipient.discriminator)"
                }
            }
            else {
                "Unknown"
            }
            
            # DM als "Channel" behandeln
            $dmChannel = @{
                id   = $selectedDM.id
                name = $partner
            }
            
            Show-ChannelView -Channel $dmChannel -GuildName "DM"
        }
        else {
            Write-Host "`n❌ Ungültige Auswahl!" -ForegroundColor $errorColor
            Start-Sleep -Seconds 1
        }
    }
}

function Show-MainMenu {
    while ($true) {
        Clear-Host
        Set-TerminalTitle "Discord Chat - Hauptmenü"
        Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        Write-Host "              💬 DISCORD CONSOLE CHAT CLIENT - by Wolli White 💬" -ForegroundColor $titleColor
        Write-Host "              Eingeloggt als: $($script:CurrentUser.username)#$($script:CurrentUser.discriminator)" -ForegroundColor $titleColor
        Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
        
        Write-Host "`n📋 Was möchtest du öffnen?" -ForegroundColor $highlightColor
        Write-Host "  [1] 💬 Direktnachrichten (DMs)" -ForegroundColor $textColor
        Write-Host "  [2] 🏰 Server-Channels" -ForegroundColor $textColor
        Write-Host "  [0] ❌ Beenden" -ForegroundColor $menuColor
        
        $mainChoice = Read-Host "`nAuswahl (0-2)"
        
        switch ($mainChoice) {
            "1" {
                # DMs anzeigen
                Show-DMList
            }
            "2" {
                # Server anzeigen
                Show-GuildList
            }
            "0" {
                Write-Host "`n👋 Tschüss!" -ForegroundColor $statusColor
                return
            }
            default {
                Write-Host "`n❌ Ungültige Auswahl!" -ForegroundColor $errorColor
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ================================
# MAIN SCRIPT
# ================================

Clear-Host

Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
Write-Host "              💬 DISCORD CONSOLE CHAT CLIENT - by Wolli White 💬" -ForegroundColor $titleColor
Write-Host "═══════════════════════════════════════════════════════════════════════════════════════" -ForegroundColor $titleColor
Write-Host ""

# Verbinden
if (-not (Connect-Discord)) {
    Write-Host "`n❌ Konnte nicht verbinden." -ForegroundColor $errorColor
    Write-Host "`n📖 Token-Anleitung: siehe Zeile 33-48 im Script" -ForegroundColor $subtextColor
    Read-Host "`nEnter drücken zum Beenden"
    exit
}

# Hauptmenü starten
Show-MainMenu

Write-Host "`n👋 Auf Wiedersehen!" -ForegroundColor $statusColor
