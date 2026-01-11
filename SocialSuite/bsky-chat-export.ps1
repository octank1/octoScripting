<#
.SYNOPSIS
    Exportiert Bluesky Chat-Konversationen als Markdown für Obsidian

.DESCRIPTION
    Script zum Exportieren von Bluesky Chat-Konversationen als Markdown.

.NOTES
    File Name      : bsky-chat-export.ps1
    Author         : Oliver C. Tank
    Prerequisite   : PowerShell 7.0+
    Copyright      : 2025 - MIT License
    Version        : 1.0.0
    Created        : 2025-01-15
    Last Modified  : 2025-12-28

.LINK
    https://github.com/octank1/octoScripts/tree/main/SocialMediaController

.EXAMPLE
    .\bsky-chat-export.ps1
    Exportiert Bluesky Chat-Konversationen als Markdown

.COMPONENT
    Benötigt: lib/config-mgr.psm1

.EXAMPLE
    .\bsky-chat-export.ps1 -FromDate "2024-12-01" -OutputFolder ".\export\chats"
    
.LICENSE
    MIT License
    
    Copyright (c) 2025 Oliver C. Tank
    
    Details siehe .\LICENSE 
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Datum ab dem Chats exportiert werden (z.B. '2025-01-01'). Standard: Ab Monatsanfang")]
    [DateTime]$FromDate = (Get-Date -Day 1 -Hour 0 -Minute 0 -Second 0),  # Erster des Monats, 00:00 Uhr
    
    [Parameter(Mandatory=$false, HelpMessage="Ordner in den die Chats exportiert werden. Standard: .\exports\bluesky-chats")]
    [string]$OutputFolder = "",

    [Parameter(HelpMessage="Zeigt diese Hilfe an")]
    [Alias("h")]
    [switch]$Help
)

if ($Help) {
    Get-Help $PSCommandPath -Detailed
    exit
}

# ================================
# ENCODING SETUP
# ================================
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

# Secrets laden
$blueskyPassword = Get-Secret -Key "bluesky.appPassword"

if ([string]::IsNullOrEmpty($blueskyPassword)) {
    Write-Host "`n⚠️  Bluesky App-Password nicht konfiguriert!" -ForegroundColor Yellow
    Write-Host "📝 Bitte Setup durchführen: Start-ConfigSetup" -ForegroundColor Cyan
    Read-Host "Enter drücken zum Beenden"
    exit
}


# ==== KONFIGURATION ====
$Username = $config.settings.bluesky.handle
$Password = $blueskyPassword
$BaseUrl  = "https://bsky.social/xrpc"
$ChatUrl  = "https://api.bsky.chat/xrpc"

$textColor = $config.settings.general.textColor
$subtextColor = $config.settings.general.subtextColor
$highlightColor = $config.settings.general.highlightColor
$statusColor = $config.settings.general.statusColor
$errorColor = $config.settings.general.errorColor
$successColor = $config.settings.general.successColor
$menuColor = $config.settings.general.menuColor


# Ausgabeordner erstellen (aus Config falls definiert, sonst Parameter)
if ($config.settings.bluesky.outputPath -and -not $PSBoundParameters.ContainsKey('OutputFolder')) {
    $OutputFolder = Join-Path $config.settings.bluesky.outputPath "chats"
}

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
    Write-Host "📁 Ordner erstellt: $OutputFolder" -ForegroundColor $successColor
}

# ==== LOGIN ====
Write-Host "🔑 Melde mich bei Bluesky an..." -ForegroundColor $statusColor
$loginBody = @{
    identifier = $Username
    password   = $Password
} | ConvertTo-Json

try {
    $loginResponse = Invoke-RestMethod -Uri "$BaseUrl/com.atproto.server.createSession" `
        -Method POST -ContentType "application/json" -Body $loginBody
    
    $AccessToken = $loginResponse.accessJwt
    $MyDid = $loginResponse.did
    $MyHandle = $loginResponse.handle
    
    Write-Host "✅ Login erfolgreich als: $MyHandle" -ForegroundColor $successColor
} catch {
    Write-Error "❌ Login fehlgeschlagen: $_"
    exit
}

# ==== CHATS LISTEN ====
Write-Host "`n💬 Lade Chat-Liste..." -ForegroundColor $statusColor
try {
    $convos = Invoke-RestMethod -Uri "$ChatUrl/chat.bsky.convo.listConvos" `
        -Headers @{ Authorization = "Bearer $AccessToken" } `
        -ContentType "application/json"
} catch {
    Write-Error "❌ Konnte Chats nicht abrufen: $_"
    exit
}

if (-not $convos.convos -or $convos.convos.Count -eq 0) {
    Write-Host "ℹ️  Keine Chats gefunden." -ForegroundColor $errorColor
    exit
}

# Zeige Chats
Write-Host "`n📋 Verfügbare Chats:" -ForegroundColor $highlightColor
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $menuColor
Write-Host ("{0,-4} {1,-30} {2}" -f "Nr", "User", "Letzte Nachricht") -ForegroundColor $menuColor
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $menuColor

for ($i = 0; $i -lt $convos.convos.Count; $i++) {
    $chat = $convos.convos[$i]
    
    $memberHandles = $chat.members | Where-Object { $_.did -ne $MyDid } | ForEach-Object { 
        $_.handle -replace '\.bsky\.social$', ''
    }
    $userName = $memberHandles -join ', '
    
    $lastMessage = if ($chat.lastMessage.text) {
        $cleanText = $chat.lastMessage.text -replace '[\r\n]+', ' '
        $cleanText.Substring(0, [Math]::Min(60, $cleanText.Length))
    } else { 
        "(keine Nachricht)" 
    }
    
    $unreadIndicator = if ($chat.unreadCount -gt 0) { " 🔴$($chat.unreadCount)" } else { "" }
    
    Write-Host ("{0,-4} " -f "$i`:") -NoNewline -ForegroundColor $subtextColor
    Write-Host ("{0,-30} " -f $userName) -NoNewline -ForegroundColor $highlightColor
    Write-Host "$lastMessage" -NoNewline -ForegroundColor $textColor
    if ($unreadIndicator) {
        Write-Host $unreadIndicator -ForegroundColor $errorColor
    } else {
        Write-Host ""
    }
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $menuColor

# ==== CHAT AUSWÄHLEN ====
$chatIndex = Read-Host "`nGib die Nummer des Chats ein (oder 'q' zum Beenden, 'all' für alle)"
if ($chatIndex -eq 'q') {
    Write-Host "👋 Tschüss!" -ForegroundColor $subtextColor
    exit
}

$chatsToExport = @()

if ($chatIndex -eq 'all') {
    $chatsToExport = $convos.convos
    Write-Host "📦 Exportiere alle $($chatsToExport.Count) Chats..." -ForegroundColor $statusColor
} elseif ($chatIndex -match '^\d+$' -and [int]$chatIndex -lt $convos.convos.Count) {
    $chatsToExport = @($convos.convos[[int]$chatIndex])
} else {
    Write-Error "❌ Ungültige Auswahl."
    exit
}

# ==== EXPORT FUNKTION ====
function Export-ChatToMarkdown {
    param(
        $Chat,
        $AccessToken,
        $MyDid,
        $MyHandle,
        $FromDate,
        $OutputFolder
    )
    
    $chatId = $Chat.id
    $chatPartner = ($Chat.members | Where-Object { $_.did -ne $MyDid }).handle -replace '\.bsky\.social$', ''
    
    Write-Host "`n💬 Exportiere Chat mit: $chatPartner" -ForegroundColor $statusColor
    
    # Alle Nachrichten abrufen (100 pro Request, iterieren wenn nötig)
    $allMessages = @()
    $cursor = $null
    
    do {
        try {
            $url = "$ChatUrl/chat.bsky.convo.getMessages?convoId=$chatId&limit=100"
            if ($cursor) {
                $url += "&cursor=$cursor"
            }
            
            $response = Invoke-RestMethod -Uri $url `
                -Headers @{ Authorization = "Bearer $AccessToken" } `
                -ContentType "application/json"
            
            $allMessages += $response.messages
            $cursor = $response.cursor
            Write-Host "  📥 $($allMessages.Count) Nachrichten geladen..." -ForegroundColor $statusColor
            
        } catch {
            Write-Warning "Fehler beim Laden: $_"
            break
        }
    } while ($cursor)
    
    # Nach Datum filtern und sortieren
    $filteredMessages = $allMessages | Where-Object {
        try {
            if ($_.sentAt -is [DateTime]) {
                $msgDate = $_.sentAt
            } else {
                $msgDate = [DateTime]::Parse($_.sentAt)
            }
            $msgDate -ge $FromDate
        } catch {
            $false
        }
    } | Sort-Object sentAt
    
    if ($filteredMessages.Count -eq 0) {
        Write-Host "  ℹ️  Keine Nachrichten seit $($FromDate.ToString('dd.MM.yyyy'))" -ForegroundColor $statusColor
        return
    }
    
    # Markdown generieren
    $md = @()
    $md += "# 💬 Chat mit $chatPartner"
    $md += ""
    $md += "**Exportiert am:** $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
    $md += "**Ab Datum:** $($FromDate.ToString('dd.MM.yyyy'))"
    $md += "**Nachrichten:** $($filteredMessages.Count)"
    $md += ""
    $md += "---"
    $md += ""
    
    # Member-Infos für Anzeigenamen vorbereiten
    $memberMap = @{}
    foreach ($member in $Chat.members) {
        $displayName = if ($member.displayName) { $member.displayName } else { $member.handle -replace '\.bsky\.social$', '' }
        $memberMap[$member.did] = $displayName
    }
    $myDisplayName = $memberMap[$MyDid]
    $myDisplayName = "Wolli White"  # Fester Name für mich
    
    $currentDate = $null
    
    foreach ($msg in $filteredMessages) {
        try {
            write-host $msg
            if ($msg.sentAt -is [DateTime]) {
                $msgDate = $msg.sentAt
            } else {
                $msgDate = [DateTime]::Parse($msg.sentAt)
            }
            $msgDateStr = $msgDate.ToString("dd.MM.yyyy")
            $msgTime = $msgDate.ToString("HH:mm")
            
            # Datumstrennlinie
            if ($currentDate -ne $msgDateStr) {
                $currentDate = $msgDateStr
                $md += ""
                $md += "---"
                $md += "## 📅 $msgDateStr"
                $md += ""
            }
            
            $isMe = $msg.sender.did -eq $MyDid
            $senderName = if ($isMe) { 
                if ($myDisplayName) { $myDisplayName } else { "Du" }
            } else { 
                $memberMap[$msg.sender.did]
            }
            
            $md += "### **$senderName** - $msgTime"
            $md += ""
            $md += $msg.text -replace "<", "\<" -replace ">", "\>"
            $md += ""
            
        } catch {
            Write-Verbose "Nachricht übersprungen: $_"
        }
    }
    
    # Dateiname generieren
    $safePartner = $chatPartner -replace '[^\w\-]', '_'
    $dateStr = $FromDate.ToString("yyyy-MM-dd")
    $fileName = "chat-$safePartner-ab-$dateStr.md"
    $filePath = Join-Path $OutputFolder $fileName
    
    # Speichern
    $md -join "`n" | Out-File -FilePath $filePath -Encoding UTF8
    
    Write-Host "  ✅ Gespeichert: $fileName" -ForegroundColor $successColor
    Write-Host "  📊 $($filteredMessages.Count) Nachrichten exportiert" -ForegroundColor $successColor
}

# ==== EXPORT DURCHFÜHREN ====
Write-Host "`n🚀 Starte Export..." -ForegroundColor $statusColor
Write-Host "📅 Ab Datum: $($FromDate.ToString('dd.MM.yyyy'))" -ForegroundColor $statusColor
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor $statusColor

foreach ($chat in $chatsToExport) {
    Export-ChatToMarkdown -Chat $chat `
        -AccessToken $AccessToken `
        -MyDid $MyDid `
        -MyHandle $MyHandle `
        -FromDate $FromDate `
        -OutputFolder $OutputFolder
}

Write-Host "`n✅ Export abgeschlossen!" -ForegroundColor $successColor
Write-Host "📁 Ordner: $OutputFolder" -ForegroundColor $successColor
Write-Host "👋 Fertig!" -ForegroundColor $subtextColor
