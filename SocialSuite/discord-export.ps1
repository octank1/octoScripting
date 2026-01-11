<#
.SYNOPSIS
    Discord Chat Export nach Markdown
.DESCRIPTION
    Exportiert Discord-Chats in Markdown-Format für Obsidian/Notion
    Unterstützt Datum-Filter und Channel-Auswahl
.NOTES
    Benötigt: Discord User Token (aus Browser DevTools)
    File Name      : discord-export.ps1
    Author         : Oliver C. Tank
    Prerequisite   : PowerShell 7.0+
    Copyright      : 2025 - MIT License
    Version        : 1.0.0
    Created        : 2025-01-15
    Last Modified  : 2025-12-28
.EXAMPLE
    .\discord-chat-export.ps1
.LINK
    https://github.com/octank1/octoScripts/tree/main/SocialMediaController
.COMPONENT
    Benötigt: lib/config-mgr.psm1
.LICENSE
    MIT License
    
    Copyright (c) 2025 Oliver C. Tank
    
    Details siehe .\LICENSE 
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
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

# ==== SECRETS LADEN ====

# Für Discord-Scripts:
$DiscordToken = Get-Secret -Key "discord.userToken"
if ([string]::IsNullOrEmpty($DiscordToken)) {
    Write-Host "`n⚠️  Discord Token nicht konfiguriert!" -ForegroundColor Yellow
    Write-Host "📝 Bitte Setup durchführen oder Token setzen:" -ForegroundColor Cyan
    Write-Host "   .\discord-token-update.ps1" -ForegroundColor Gray
    Read-Host "Enter drücken zum Beenden"
    exit
}

# ================================
# KONFIGURATION
# ================================
$DiscordApiBase = "https://discord.com/api/v10"

#$textColor = $config.settings.general.textColor
$subtextColor = $config.settings.general.subtextColor
$titleColor = $config.settings.general.titleColor
$highlightColor = $config.settings.general.highlightColor
$statusColor = $config.settings.general.statusColor
$errorColor = $config.settings.general.errorColor
$successColor = $config.settings.general.successColor
$menuColor = $config.settings.general.menuColor


# Export-Einstellungen
$ExportPath = $config.settings.discord.outputPath
if (-not (Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath | Out-Null
}

# ================================
# FUNKTIONEN
# ================================

function Get-DiscordHeaders {
    return @{
        "Authorization" = $DiscordToken
        "Content-Type" = "application/json"
        "User-Agent" = "DiscordBot (PowerShell, 1.0)"
    }
}

function Get-UserGuilds {
    <#
    .SYNOPSIS
    Lädt alle Server (Guilds) des Users
    #>
    try {
        $guilds = Invoke-RestMethod -Uri "$DiscordApiBase/users/@me/guilds" `
            -Headers (Get-DiscordHeaders) `
            -Method GET
        
        return $guilds
    } catch {
        Write-Host "❌ Fehler beim Laden der Server: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Get-GuildChannels {
    param([string]$GuildId)
    
    try {
        $channels = Invoke-RestMethod -Uri "$DiscordApiBase/guilds/$GuildId/channels" `
            -Headers (Get-DiscordHeaders) `
            -Method GET
        
        # Nur Text-Channels
        return $channels | Where-Object { $_.type -in @(0, 5, 11, 12) }  # Text, Announcement, Thread, Forum
    } catch {
        Write-Host "❌ Fehler beim Laden der Channels: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Get-DMChannels {
    <#
    .SYNOPSIS
    Lädt alle DM (Direct Message) Channels
    #>
    try {
        $dms = Invoke-RestMethod -Uri "$DiscordApiBase/users/@me/channels" `
            -Headers (Get-DiscordHeaders) `
            -Method GET
        
        return $dms
    } catch {
        Write-Host "❌ Fehler beim Laden der DMs: $($_.Exception.Message)" -ForegroundColor $errorColor
        return @()
    }
}

function Get-ChannelMessages {
    param(
        [string]$ChannelId,
        [datetime]$After = (Get-Date).AddYears(-10),
        [int]$Limit = 10000
    )
    
    Write-Host "📥 Lade Nachrichten..." -ForegroundColor $statusColor
    
    $allMessages = @()
    $beforeId = $null
    $batchCount = 0
    
    # Discord Snowflake ID für Datum-Filter
    #$afterSnowflake = ([Math]::Floor(($After.ToUniversalTime() - [DateTime]::new(2015, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalMilliseconds) -shl 22)
    
    while ($allMessages.Count -lt $Limit) {
        $batchCount++
        
        # API-Aufruf (max 100 pro Request)
        $url = "$DiscordApiBase/channels/$ChannelId/messages?limit=100"
        if ($beforeId) {
            $url += "&before=$beforeId"
        }
        
        try {
            Write-Host "  Batch #$batchCount (Gesamt: $($allMessages.Count))..." -ForegroundColor $statusColor
            
            $messages = Invoke-RestMethod -Uri $url `
                -Headers (Get-DiscordHeaders) `
                -Method GET
            
            if (-not $messages -or $messages.Count -eq 0) {
                Write-Host "  ✓ Keine weiteren Nachrichten" -ForegroundColor $statusColor
                break
            }
            
            # Nach Datum filtern
            $filteredMessages = $messages | Where-Object {
                try {
                    $msgDate = [DateTime]::Parse($_.timestamp)
                    $msgDate -ge $After
                } catch {
                    $true  # Bei Fehler: Nachricht behalten
                }
            }
            
            if ($filteredMessages.Count -eq 0) {
                Write-Host "  ✓ Datum-Grenze erreicht" -ForegroundColor $statusColor
                break
            }
            
            $allMessages += $filteredMessages
            
            # Nächste ID für Pagination
            $beforeId = $messages[-1].id
            
            # Rate Limit vermeiden (50 Requests pro Sekunde)
            Start-Sleep -Milliseconds 100
            
        } catch {
            Write-Host "  ⚠️ Fehler: $($_.Exception.Message)" -ForegroundColor $errorColor
            break
        }
    }
    
    # Chronologisch sortieren (älteste zuerst)
    $sorted = $allMessages | Sort-Object timestamp
    
    Write-Host "✅ $($sorted.Count) Nachrichten geladen" -ForegroundColor $successColor
    return $sorted
}

function Convert-DiscordMessageToMarkdown {
    param(
        $Message, 
        $AuthorCache = @{},
        $AttachmentFolder = "_Attachments"
    )
    
    $timestamp = try { 
        if ($Message.timestamp -is [DateTime]) {
            $Message.timestamp.ToString("dd.MM.yyyy HH:mm:ss")
        } else {
            [DateTime]::Parse($Message.timestamp).ToString("dd.MM.yyyy HH:mm:ss") 
        }
    } catch { 
        "unknown" 
    }
    
    $author = if ($Message.author.global_name) {
        $Message.author.global_name
    } elseif ($Message.author.username) {
        $Message.author.username
    } else {
        "Unknown"
    }
    
    # Markdown-Ausgabe
    $md = "### 💬 $author`n"
    $md += "**Datum:** $timestamp`n`n"
    
    # Message Type prüfen
    # Type 0 = Normal, Type 3 = Call, Type 19 = Reply, etc.
    if ($Message.type -eq 3) {
        # Call-Nachricht
        $md += "📞 **Anruf gestartet**`n"
        
        # Anruf-Dauer wenn vorhanden
        if ($Message.call -and $Message.call.ended_timestamp) {
            if ($Message.timestamp -is [DateTime]) {
                $startTime = $Message.timestamp
                $endTime = $Message.call.ended_timestamp
            } else {
                $startTime = [DateTime]::Parse($Message.timestamp)
                $endTime = [DateTime]::Parse($Message.call.ended_timestamp)
            }
            $duration = $endTime - $startTime
            $md += "⏱️ Dauer: $($duration.ToString('hh\:mm\:ss'))`n"
        }
        
        # Teilnehmer
        if ($Message.call -and $Message.call.participants -and $Message.call.participants.Count -gt 0) {
            $participants = $Message.call.participants -join ", "
            $md += "👥 Teilnehmer: $participants`n"
        }
    } else {
        # Normaler Nachrichtentext
        $content = $Message.content -replace "<", "\<" -replace ">", "\>"
        
        if ($content) {
            # Discord-Mentions konvertieren
            # <@123456789> → @Username
            # <#123456789> → #channel
            # Discord-Markdown bleibt weitgehend gleich
            
            $md += "$content`n"
        }
    }
    
    # Anhänge
    if ($Message.attachments -and $Message.attachments.Count -gt 0) {
        $md += "`n**📎 Anhänge:**`n"
        foreach ($attachment in $Message.attachments) {
            $filename = $attachment.filename
            #$url = $attachment.url
            $contentType = $attachment.content_type
            
            # Lokaler Pfad für heruntergeladene Datei
            $localPath = "$AttachmentFolder/$filename"
            
            # Prüfen ob es ein Bild ist
            $isImage = $contentType -match '^image/'
            
            if ($isImage) {
                # Bild: Obsidian-Syntax ![[pfad]]
                $md += "![$filename]($localPath)`n"
            } else {
                # Andere Datei: Normaler Link
                $md += "- [$filename]($localPath)`n"
            }
            
            # Metadaten
            if ($attachment.size) {
                $sizeKB = [Math]::Round($attachment.size / 1024, 2)
                $md += "  *(Größe: $sizeKB KB)*`n"
            }
        }
    }
    
    # Embeds
    if ($Message.embeds -and $Message.embeds.Count -gt 0) {
        $md += "`n**🔗 Embeds:**`n"
        foreach ($embed in $Message.embeds) {
            if ($embed.title) {
                $md += "- **$($embed.title)**"
                if ($embed.url) {
                    $md += " - $($embed.url)"
                }
                $md += "`n"
            }
            if ($embed.description) {
                $md += "  $($embed.description)`n"
            }
            
            # Embed-Bilder
            if ($embed.image -and $embed.image.url) {
                $md += "  ![Embed Image|350]($($embed.image.url))`n"
            }
            
            # Embed-Thumbnail
            if ($embed.thumbnail -and $embed.thumbnail.url) {
                $md += "  ![Thumbnail|250]($($embed.thumbnail.url))`n"
            }
        }
    }
    
    # Reactions
    if ($Message.reactions -and $Message.reactions.Count -gt 0) {
        $reactionStr = ($Message.reactions | ForEach-Object {
            "$($_.emoji.name) x$($_.count)"
        }) -join ", "
        $md += "`n**👍 Reactions:** $reactionStr`n"
    }
    
    # Sticker
    if ($Message.sticker_items -and $Message.sticker_items.Count -gt 0) {
        $md += "`n**🎨 Sticker:**`n"
        foreach ($sticker in $Message.sticker_items) {
            $md += "- $($sticker.name)`n"
        }
    }
    
    $md += "`n---`n`n"
    
    return $md
}

function Get-Attachment {
    param(
        [string]$Url,
        [string]$Filename,
        [string]$TargetFolder
    )
    
    try {
        # Sicheren Dateinamen erstellen
        $safeFilename = $Filename -replace '[\\/:*?"<>|]', '_'
        $targetPath = Join-Path $TargetFolder $safeFilename
        
        # Prüfen ob Datei schon existiert
        if (Test-Path $targetPath) {
            Write-Verbose "Datei existiert bereits: $safeFilename"
            return $true
        }
        
        # Download mit Progress
        Write-Host "  📥 Lade: $safeFilename" -ForegroundColor $statusColor
        
        Invoke-WebRequest -Uri $Url -OutFile $targetPath -UseBasicParsing
        
        return $true
    } catch {
        Write-Host "  ⚠️ Fehler beim Download von $Filename`: $($_.Exception.Message)" -ForegroundColor $errorColor
        return $false
    }
}

function Export-DiscordChannel {
    param(
        [string]$ChannelId,
        [string]$ChannelName,
        [datetime]$After = (Get-Date).AddYears(-10),
        [switch]$DownloadAttachments
    )
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $titleColor
    Write-Host "║              📤 DISCORD CHANNEL EXPORT                        ║" -ForegroundColor $titleColor
    Write-Host "╠════════════════════════════════════════════════════════════════╣" -ForegroundColor $titleColor
    Write-Host "║ Channel: $($ChannelName.PadRight(54)) ║" -ForegroundColor $titleColor
    Write-Host "║ Ab Datum: $($After.ToString('dd.MM.yyyy').PadRight(52)) ║" -ForegroundColor $titleColor
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $titleColor
    
    # Nachrichten laden
    $messages = Get-ChannelMessages -ChannelId $ChannelId -After $After
    
    if (-not $messages -or $messages.Count -eq 0) {
        Write-Host "❌ Keine Nachrichten gefunden!" -ForegroundColor $errorColor
        return
    }
    
    # Dateinamen und Ordner vorbereiten
    $safeChannelName = $ChannelName -replace '[\\/:*?"<>|]', '_'
    $dateStr = $After.ToString('yyyy-MM-dd')
    $filename = "Discord_${safeChannelName}_ab_${dateStr}.md"
    $filepath = Join-Path $ExportPath $filename
    
    # Attachment-Ordner erstellen
    $attachmentFolder = "_Attachments"
    $attachmentPath = Join-Path $ExportPath $attachmentFolder
    if ($DownloadAttachments -and -not (Test-Path $attachmentPath)) {
        New-Item -ItemType Directory -Path $attachmentPath | Out-Null
    }
    
    # Attachments zählen
     $totalAttachments = 0
    foreach ($msg in $messages) {
        if ($msg.attachments -and $msg.attachments.Count -gt 0) {
            $totalAttachments += $msg.attachments.Count
        }
    }
    
    if ($DownloadAttachments -and $totalAttachments -gt 0) {
        Write-Host "`n📎 Lade $totalAttachments Anhänge herunter..." -ForegroundColor $statusColor
        
        $downloadedCount = 0
        foreach ($msg in $messages) {
            if ($msg.attachments -and $msg.attachments.Count -gt 0) {
                foreach ($attachment in $msg.attachments) {
                    if (Get-Attachment -Url $attachment.url -Filename $attachment.filename -TargetFolder $attachmentPath) {
                        $downloadedCount++
                    }
                    
                    # Rate Limit beachten
                    Start-Sleep -Milliseconds 200
                }
            }
        }
        
        Write-Host "✅ $downloadedCount von $totalAttachments Anhängen heruntergeladen" -ForegroundColor $successColor
    }
    
    # Markdown generieren
    Write-Host "`n📝 Generiere Markdown..." -ForegroundColor $statusColor
    
    $markdown = "# Discord Export: $ChannelName`n`n"
    $markdown += "**Exportiert am:** $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')`n"
    $markdown += "**Zeitraum:** ab $($After.ToString('dd.MM.yyyy'))`n"
    $markdown += "**Anzahl Nachrichten:** $($messages.Count)`n"
    if ($totalAttachments -gt 0) {
        $markdown += "**Anhänge:** $totalAttachments`n"
    }
    $markdown += "`n---`n`n"
    
    foreach ($msg in $messages) {
        $markdown += Convert-DiscordMessageToMarkdown -Message $msg -AttachmentFolder $attachmentFolder
    }
    
    # Datei speichern
    $markdown | Out-File -FilePath $filepath -Encoding UTF8
    
    Write-Host "`n✅ Export erfolgreich!" -ForegroundColor $successColor
    Write-Host "📁 Gespeichert: $filepath" -ForegroundColor $subtextColor
    Write-Host "📊 $($messages.Count) Nachrichten exportiert" -ForegroundColor $subtextColor
    if ($totalAttachments -gt 0) {
        Write-Host "📎 $totalAttachments Anhänge in: $attachmentPath" -ForegroundColor $statusColor
    }
}

# ================================
# MAIN SCRIPT
# ================================

Clear-Host
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $titleColor
Write-Host "║          💬 DISCORD CHAT EXPORT - by Wolli White 💬           ║" -ForegroundColor $titleColor
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $titleColor
Write-Host ""

# Token-Check
if ([string]::IsNullOrEmpty($DiscordToken)) {
    Write-Host "❌ FEHLER: Discord Token fehlt!" -ForegroundColor $errorColor
    Write-Host ""
    Write-Host "📖 SO BEKOMMST DU DEINEN TOKEN:" -ForegroundColor $subtextColor
    Write-Host "1. Öffne Discord im Browser (chrome/edge)" -ForegroundColor $subtextColor
    Write-Host "2. Drücke F12 (DevTools)" -ForegroundColor $subtextColor
    Write-Host "3. Gehe zum Tab 'Network' / 'Netzwerk'" -ForegroundColor $subtextColor
    Write-Host "4. Lade Discord neu (F5)" -ForegroundColor $subtextColor
    Write-Host "5. Suche nach 'messages' Request" -ForegroundColor $subtextColor
    Write-Host "6. Unter 'Headers' → 'Authorization' findest du den Token" -ForegroundColor $subtextColor
    Write-Host "7. Kopiere den Token und trage ihn in Zeile 23 ein!" -ForegroundColor $subtextColor
    Write-Host ""
    Write-Host "⚠️  WICHTIG: Token NIEMALS teilen! Wie ein Passwort behandeln!" -ForegroundColor $highlightColor
    Write-Host ""
    Read-Host "Enter drücken zum Beenden"
    exit
}

# Auswahl: Server oder DM
Write-Host "📋 Was möchtest du exportieren?" -ForegroundColor $menuColor
Write-Host "  [1] DM (Direct Message)" -ForegroundColor $menuColor
Write-Host "  [2] Server-Channel" -ForegroundColor $menuColor
Write-Host ""
$choice = Read-Host "Auswahl (1/2)"

if ($choice -eq "1") {
    # DM Export
    Write-Host "`n📥 Lade DM-Liste..." -ForegroundColor $statusColor
    $dms = Get-DMChannels
    
    if (-not $dms -or $dms.Count -eq 0) {
        Write-Host "❌ Keine DMs gefunden!" -ForegroundColor $errorColor
        Read-Host "Enter drücken zum Beenden"
        exit
    }
    
    Write-Host "`n📋 Verfügbare DMs:" -ForegroundColor $highlightColor
    for ($i = 0; $i -lt $dms.Count; $i++) {
        $dm = $dms[$i]
        $name = if ($dm.recipients -and $dm.recipients.Count -gt 0) {
            ($dm.recipients | ForEach-Object { 
                if ($_.global_name) { $_.global_name } else { $_.username }
            }) -join ", "
        } else {
            "Unknown"
        }
        Write-Host "  [$($i+1)] $name" -ForegroundColor $menuColor
    }
    
    Write-Host ""
    $selection = Read-Host "Welchen DM exportieren? (Nummer)"
    
    try {
        $selectedDM = $dms[[int]$selection - 1]
        $dmName = if ($selectedDM.recipients -and $selectedDM.recipients.Count -gt 0) {
            ($selectedDM.recipients | ForEach-Object { 
                if ($_.global_name) { $_.global_name } else { $_.username }
            }) -join ", "
        } else {
            "Unknown"
        }
    } catch {
        Write-Host "❌ Ungültige Auswahl!" -ForegroundColor $errorColor
        Read-Host "Enter drücken zum Beenden"
        exit
    }
    
    $channelId = $selectedDM.id
    $channelName = "DM_$dmName"
    
} else {
    # Server-Channel Export
    Write-Host "`n📥 Lade Server-Liste..." -ForegroundColor $statusColor
    $guilds = Get-UserGuilds
    
    if (-not $guilds -or $guilds.Count -eq 0) {
        Write-Host "❌ Keine Server gefunden!" -ForegroundColor $errorColor
        Read-Host "Enter drücken zum Beenden"
        exit
    }
    
    Write-Host "`n📋 Verfügbare Server:" -ForegroundColor $highlightColor
    for ($i = 0; $i -lt $guilds.Count; $i++) {
        Write-Host "  [$($i+1)] $($guilds[$i].name)" -ForegroundColor $menuColor
    }
    
    Write-Host ""
    $guildSelection = Read-Host "Welchen Server? (Nummer)"
    
    try {
        $selectedGuild = $guilds[[int]$guildSelection - 1]
    } catch {
        Write-Host "❌ Ungültige Auswahl!" -ForegroundColor $errorColor
        Read-Host "Enter drücken zum Beenden"
        exit
    }
    
    # Channels laden
    Write-Host "`n📥 Lade Channels von '$($selectedGuild.name)'..." -ForegroundColor $statusColor
    $channels = Get-GuildChannels -GuildId $selectedGuild.id
    
    if (-not $channels -or $channels.Count -eq 0) {
        Write-Host "❌ Keine Text-Channels gefunden!" -ForegroundColor $errorColor
        Read-Host "Enter drücken zum Beenden"
        exit
    }
    
    Write-Host "`n📋 Verfügbare Channels:" -ForegroundColor $highlightColor
    for ($i = 0; $i -lt $channels.Count; $i++) {
        Write-Host "  [$($i+1)] #$($channels[$i].name)" -ForegroundColor $menuColor
    }
    
    Write-Host ""
    $channelSelection = Read-Host "Welchen Channel exportieren? (Nummer)"
    
    try {
        $selectedChannel = $channels[[int]$channelSelection - 1]
    } catch {
        Write-Host "❌ Ungültige Auswahl!" -ForegroundColor $errorColor
        Read-Host "Enter drücken zum Beenden"
        exit
    }
    
    $channelId = $selectedChannel.id
    $channelName = "$($selectedGuild.name)_$($selectedChannel.name)"
}

# Datum-Filter
Write-Host "`n📅 Ab welchem Datum exportieren?" -ForegroundColor $highlightColor
Write-Host "  Beispiel: 01.12.2024 oder leer für alle Nachrichten" -ForegroundColor $subtextColor
$dateInput = Read-Host "Datum (dd.MM.yyyy)"

if ([string]::IsNullOrWhiteSpace($dateInput)) {
    $afterDate = (Get-Date).AddYears(-10)
} else {
    try {
        $afterDate = [DateTime]::ParseExact($dateInput, "dd.MM.yyyy", $null)
    } catch {
        Write-Host "⚠️ Ungültiges Datum, verwende: Alle Nachrichten" -ForegroundColor $warningColor
        $afterDate = (Get-Date).AddYears(-10)
    }
}

# Export starten
Write-Host "`n📎 Anhänge herunterladen?" -ForegroundColor $highlightColor
Write-Host "  [1] Ja (empfohlen)" -ForegroundColor $menuColor
Write-Host "  [2] Nein (nur Links)" -ForegroundColor $menuColor
$dlChoice = Read-Host "Auswahl (1/2)"

$downloadAttachments = ($dlChoice -ne "2")

Export-DiscordChannel -ChannelId $channelId -ChannelName $channelName -After $afterDate -DownloadAttachments:$downloadAttachments

Write-Host "`n👋 Fertig!" -ForegroundColor $subtextColor
Read-Host "Enter drücken zum Beenden"
