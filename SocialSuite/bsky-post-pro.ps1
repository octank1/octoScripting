<#
.SYNOPSIS
    Bluesky PowerShell GUI Client - PRO Edition
.DESCRIPTION
    Erweiterte Version mit Drafts, Templates, Emoji-Picker und Rich-Text Support
.NOTES
    Requires: PowerShell 5.1+ with Windows Forms
    File Name      : bsky-post-pro.ps1
    Author         : Oliver C. Tank
    Prerequisite   : PowerShell 7.0+
    Copyright      : 2025 - MIT License
    Version        : 1.0.0
    Created        : 2025-01-15
    Last Modified  : 2025-12-28

.LINK
    https://github.com/octank1/octoScripts/tree/main/SocialMediaController

.EXAMPLE
    .\bsky-post-pro.ps1
    Startet den interaktiven Post-Client

.COMPONENT
    Benötigt: lib/config-mgr.psm1

.LICENSE
    MIT License
    
    Copyright (c) 2025 Oliver C. Tank
    
    Details siehe .\LICENSE 
#>

# Encoding Setup
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues = @{
    'Invoke-RestMethod:Encoding' = 'UTF8'
    'Invoke-WebRequest:Encoding' = 'UTF8'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing


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

# Für Bluesky-Scripts:
$BlueskyAppPassword = Get-Secret -Key "bluesky.appPassword"
if ([string]::IsNullOrEmpty($BlueskyAppPassword)) {
    Write-Host "`n⚠️  Bluesky App-Password nicht konfiguriert!" -ForegroundColor Yellow
    Write-Host "📝 Bitte Setup durchführen: Start-ConfigSetup" -ForegroundColor Cyan
    Read-Host "Enter drücken zum Beenden"
    exit
}
$BlueskyHandle = $config.settings.bluesky.handle

# Dateipfade
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$DraftsPath = Join-Path $ScriptPath "bluesky-drafts.json"
$TemplatesPath = Join-Path $ScriptPath "bluesky-templates.json"

$subtextColor = $config.settings.general.subtextColor
$titleColor = $config.settings.general.titleColor
$highlightColor = $config.settings.general.highlightColor
$errorColor = $config.settings.general.errorColor


# ================================
# DATEN LADEN/SPEICHERN
# ================================
function Get-Drafts {
    if (Test-Path $DraftsPath) {
        try {
            $json = Get-Content $DraftsPath -Raw -Encoding UTF8
            $drafts = $json | ConvertFrom-Json
            # Als Array zurückgeben, auch wenn nur 1 Element
            if ($drafts -is [array]) {
                return @($drafts)
            } else {
                return @($drafts)
            }
        } catch {
            return @()
        }
    }
    return @()
}

function Save-Drafts {
    param($Drafts)
    # Sicherstellen, dass es ein Array ist
    $draftsArray = @($Drafts)
    $draftsArray | ConvertTo-Json -Depth 5 | Out-File $DraftsPath -Encoding UTF8
}

function Get-Templates {
    if (Test-Path $TemplatesPath) {
        try {
            $json = Get-Content $TemplatesPath -Raw -Encoding UTF8
            return ($json | ConvertFrom-Json)
        } catch {
            return @()
        }
    }
    # Standard-Templates
    return @(
        @{ Name = "Ankündigung"; Text = "📢 Neue Ankündigung:`n`n[Text hier]`n`n#Update" }
        @{ Name = "Artikel-Link"; Text = "📖 Interessanter Artikel:`n`n[Link]`n`n#Lesetipp" }
        @{ Name = "Tipp des Tages"; Text = "💡 Tipp des Tages:`n`n[Tipp]`n`n#TipOfTheDay" }
    )
}

function Save-Templates {
    param($Templates)
    $Templates | ConvertTo-Json -Depth 5 | Out-File $TemplatesPath -Encoding UTF8
}


# ================================
# UNICODE TEXT CONVERSION
# ================================
function Convert-ToPseudoBold {
    param([string]$Text)
    
    Write-Host "Konvertiere zu Fettschrift... $Text" -ForegroundColor Cyan
    # Case-sensitive Hashtable!
    $boldMap = New-Object System.Collections.Hashtable
    $boldMap.Add('a','𝗮');$boldMap.Add('b','𝗯');$boldMap.Add('c','𝗰');$boldMap.Add('d','𝗱');$boldMap.Add('e','𝗲');$boldMap.Add('f','𝗳');$boldMap.Add('g','𝗴');$boldMap.Add('h','𝗵');$boldMap.Add('i','𝗶');$boldMap.Add('j','𝗷');$boldMap.Add('k','𝗸');$boldMap.Add('l','𝗹');$boldMap.Add('m','𝗺');$boldMap.Add('n','𝗻');$boldMap.Add('o','𝗼');$boldMap.Add('p','𝗽');$boldMap.Add('q','𝗾');$boldMap.Add('r','𝗿');$boldMap.Add('s','𝘀');$boldMap.Add('t','𝘁');$boldMap.Add('u','𝘂');$boldMap.Add('v','𝘃');$boldMap.Add('w','𝘄');$boldMap.Add('x','𝘅');$boldMap.Add('y','𝘆');$boldMap.Add('z','𝘇')
    $boldMap.Add('A','𝗔');$boldMap.Add('B','𝗕');$boldMap.Add('C','𝗖');$boldMap.Add('D','𝗗');$boldMap.Add('E','𝗘');$boldMap.Add('F','𝗙');$boldMap.Add('G','𝗚');$boldMap.Add('H','𝗛');$boldMap.Add('I','𝗜');$boldMap.Add('J','𝗝');$boldMap.Add('K','𝗞');$boldMap.Add('L','𝗟');$boldMap.Add('M','𝗠');$boldMap.Add('N','𝗡');$boldMap.Add('O','𝗢');$boldMap.Add('P','𝗣');$boldMap.Add('Q','𝗤');$boldMap.Add('R','𝗥');$boldMap.Add('S','𝗦');$boldMap.Add('T','𝗧');$boldMap.Add('U','𝗨');$boldMap.Add('V','𝗩');$boldMap.Add('W','𝗪');$boldMap.Add('X','𝗫');$boldMap.Add('Y','𝗬');$boldMap.Add('Z','𝗭')
    $boldMap.Add('0','𝟬');$boldMap.Add('1','𝟭');$boldMap.Add('2','𝟮');$boldMap.Add('3','𝟯');$boldMap.Add('4','𝟰');$boldMap.Add('5','𝟱');$boldMap.Add('6','𝟲');$boldMap.Add('7','𝟳');$boldMap.Add('8','𝟴');$boldMap.Add('9','𝟵')
    
    $result = ""
    foreach ($char in $Text.ToCharArray()) {
        if ($boldMap.ContainsKey([string]$char)) {
            $result += $boldMap[[string]$char]
        } else {
            $result += $char
        }
    }
    Write-Host $result
    return $result
}

function Convert-ToPseudoItalic {
    param([string]$Text)
    
    $italicMap = New-Object System.Collections.Hashtable
    $italicMap.Add('a','𝘢');$italicMap.Add('b','𝘣');$italicMap.Add('c','𝘤');$italicMap.Add('d','𝘥');$italicMap.Add('e','𝘦');$italicMap.Add('f','𝘧');$italicMap.Add('g','𝘨');$italicMap.Add('h','𝘩');$italicMap.Add('i','𝘪');$italicMap.Add('j','𝘫');$italicMap.Add('k','𝘬');$italicMap.Add('l','𝘭');$italicMap.Add('m','𝘮');$italicMap.Add('n','𝘯');$italicMap.Add('o','𝘰');$italicMap.Add('p','𝘱');$italicMap.Add('q','𝘲');$italicMap.Add('r','𝘳');$italicMap.Add('s','𝘴');$italicMap.Add('t','𝘵');$italicMap.Add('u','𝘶');$italicMap.Add('v','𝘷');$italicMap.Add('w','𝘸');$italicMap.Add('x','𝘹');$italicMap.Add('y','𝘺');$italicMap.Add('z','𝘻')
    $italicMap.Add('A','𝘈');$italicMap.Add('B','𝘉');$italicMap.Add('C','𝘊');$italicMap.Add('D','𝘋');$italicMap.Add('E','𝘌');$italicMap.Add('F','𝘍');$italicMap.Add('G','𝘎');$italicMap.Add('H','𝘏');$italicMap.Add('I','𝘐');$italicMap.Add('J','𝘑');$italicMap.Add('K','𝘒');$italicMap.Add('L','𝘓');$italicMap.Add('M','𝘔');$italicMap.Add('N','𝘕');$italicMap.Add('O','𝘖');$italicMap.Add('P','𝘗');$italicMap.Add('Q','𝘘');$italicMap.Add('R','𝘙');$italicMap.Add('S','𝘚');$italicMap.Add('T','𝘛');$italicMap.Add('U','𝘜');$italicMap.Add('V','𝘝');$italicMap.Add('W','𝘞');$italicMap.Add('X','𝘟');$italicMap.Add('Y','𝘠');$italicMap.Add('Z','𝘡')
    
    $result = ""
    foreach ($char in $Text.ToCharArray()) {
        if ($italicMap.ContainsKey([string]$char)) {
            $result += $italicMap[[string]$char]
        } else {
            $result += $char
        }
    }
    return $result
}

function Convert-ToMonospace {
    param([string]$Text)
    
    $monoMap = New-Object System.Collections.Hashtable
    $monoMap.Add('a','𝚊');$monoMap.Add('b','𝚋');$monoMap.Add('c','𝚌');$monoMap.Add('d','𝚍');$monoMap.Add('e','𝚎');$monoMap.Add('f','𝚏');$monoMap.Add('g','𝚐');$monoMap.Add('h','𝚑');$monoMap.Add('i','𝚒');$monoMap.Add('j','𝚓');$monoMap.Add('k','𝚔');$monoMap.Add('l','𝚕');$monoMap.Add('m','𝚖');$monoMap.Add('n','𝚗');$monoMap.Add('o','𝚘');$monoMap.Add('p','𝚙');$monoMap.Add('q','𝚚');$monoMap.Add('r','𝚛');$monoMap.Add('s','𝚜');$monoMap.Add('t','𝚝');$monoMap.Add('u','𝚞');$monoMap.Add('v','𝚟');$monoMap.Add('w','𝚠');$monoMap.Add('x','𝚡');$monoMap.Add('y','𝚢');$monoMap.Add('z','𝚣')
    $monoMap.Add('A','𝙰');$monoMap.Add('B','𝙱');$monoMap.Add('C','𝙲');$monoMap.Add('D','𝙳');$monoMap.Add('E','𝙴');$monoMap.Add('F','𝙵');$monoMap.Add('G','𝙶');$monoMap.Add('H','𝙷');$monoMap.Add('I','𝙸');$monoMap.Add('J','𝙹');$monoMap.Add('K','𝙺');$monoMap.Add('L','𝙻');$monoMap.Add('M','𝙼');$monoMap.Add('N','𝙽');$monoMap.Add('O','𝙾');$monoMap.Add('P','𝙿');$monoMap.Add('Q','𝚀');$monoMap.Add('R','𝚁');$monoMap.Add('S','𝚂');$monoMap.Add('T','𝚃');$monoMap.Add('U','𝚄');$monoMap.Add('V','𝚅');$monoMap.Add('W','𝚆');$monoMap.Add('X','𝚇');$monoMap.Add('Y','𝚈');$monoMap.Add('Z','𝚉')
    $monoMap.Add('0','𝟶');$monoMap.Add('1','𝟷');$monoMap.Add('2','𝟸');$monoMap.Add('3','𝟹');$monoMap.Add('4','𝟺');$monoMap.Add('5','𝟻');$monoMap.Add('6','𝟼');$monoMap.Add('7','𝟽');$monoMap.Add('8','𝟾');$monoMap.Add('9','𝟿')
    
    $result = ""
    foreach ($char in $Text.ToCharArray()) {
        if ($monoMap.ContainsKey([string]$char)) {
            $result += $monoMap[[string]$char]
        } else {
            $result += $char
        }
    }
    return $result
}

# ================================
# FACETS - RICH TEXT PARSING
# ================================
function Find-Facets {
    param([string]$Text)
    
    $facets = @()
    
    # URLs finden
    $urlPattern = 'https?://[^\s]+'
    $urlMatches = [regex]::Matches($Text, $urlPattern)
    
    foreach ($match in $urlMatches) {
        # Byte-Positionen berechnen (UTF-8)
        $beforeText = $Text.Substring(0, $match.Index)
        $byteStart = [System.Text.Encoding]::UTF8.GetByteCount($beforeText)
        $byteEnd = $byteStart + [System.Text.Encoding]::UTF8.GetByteCount($match.Value)
        
        $facets += @{
            index = @{
                byteStart = $byteStart
                byteEnd = $byteEnd
            }
            features = @(
                @{
                    '$type' = 'app.bsky.richtext.facet#link'
                    uri = $match.Value
                }
            )
        }
    }
    
    # Mentions finden (@handle)
    $mentionPattern = '@([a-zA-Z0-9.-]+)'
    $mentionMatches = [regex]::Matches($Text, $mentionPattern)
    
    foreach ($match in $mentionMatches) {
        $beforeText = $Text.Substring(0, $match.Index)
        $byteStart = [System.Text.Encoding]::UTF8.GetByteCount($beforeText)
        $byteEnd = $byteStart + [System.Text.Encoding]::UTF8.GetByteCount($match.Value)
        
        # DID auflösen würde hier passieren - für jetzt nur Handle
        $facets += @{
            index = @{
                byteStart = $byteStart
                byteEnd = $byteEnd
            }
            features = @(
                @{
                    '$type' = 'app.bsky.richtext.facet#mention'
                    did = "at://$($match.Groups[1].Value)"  # Vereinfacht
                }
            )
        }
    }
    
    # Hashtags finden
    $hashtagPattern = '#([a-zA-Z0-9_]+)'
    $hashtagMatches = [regex]::Matches($Text, $hashtagPattern)
    
    foreach ($match in $hashtagMatches) {
        $beforeText = $Text.Substring(0, $match.Index)
        $byteStart = [System.Text.Encoding]::UTF8.GetByteCount($beforeText)
        $byteEnd = $byteStart + [System.Text.Encoding]::UTF8.GetByteCount($match.Value)
        
        $facets += @{
            index = @{
                byteStart = $byteStart
                byteEnd = $byteEnd
            }
            features = @(
                @{
                    '$type' = 'app.bsky.richtext.facet#tag'
                    tag = $match.Groups[1].Value
                }
            )
        }
    }
    
    return $facets
}

# ================================
# BLUESKY API
# ================================
function Send-BlueskyPost {
    param(
        [string]$Text,
        [array]$Facets = @(),
        [string]$ReplyToUri = $null,
        [string]$ReplyToCid = $null
    )
    
    try {
        Write-Host "Authentifiziere bei Bluesky..." -ForegroundColor Cyan
        
        $authBody = @{
            identifier = $BlueskyHandle
            password = $BlueskyAppPassword
        } | ConvertTo-Json -Depth 10

        $authBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($authBody)

        $sessionResponse = Invoke-RestMethod -Uri "https://bsky.social/xrpc/com.atproto.server.createSession" `
            -Method POST -Body $authBodyBytes -ContentType "application/json; charset=utf-8"

        if (-not $sessionResponse.accessJwt) {
            return @{ Success = $false; Error = "Authentifizierung fehlgeschlagen" }
        }

        Write-Host "Sende Post..." -ForegroundColor Cyan

        $record = @{
            text = $Text
            createdAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        
        # Facets hinzufügen wenn vorhanden
        if ($Facets.Count -gt 0) {
            $record.facets = $Facets
        }
        
        # Reply-Referenz hinzufügen (für Threads)
        if ($ReplyToUri -and $ReplyToCid) {
            $record.reply = @{
                root = @{
                    uri = $ReplyToUri
                    cid = $ReplyToCid
                }
                parent = @{
                    uri = $ReplyToUri
                    cid = $ReplyToCid
                }
            }
        }

        $postBody = @{
            repo = $sessionResponse.did
            collection = "app.bsky.feed.post"
            record = $record
        } | ConvertTo-Json -Depth 10

        $headers = @{
            "Authorization" = "Bearer $($sessionResponse.accessJwt)"
            "Content-Type" = "application/json; charset=utf-8"
        }

        $postBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($postBody)
        
        $postResponse = Invoke-RestMethod -Uri "https://bsky.social/xrpc/com.atproto.repo.createRecord" `
            -Method POST -Body $postBodyBytes -Headers $headers

        Write-Host "Post erfolgreich gesendet!" -ForegroundColor Green
        
        return @{ 
            Success = $true
            Uri = $postResponse.uri
            Cid = $postResponse.cid
        }

    } catch {
        Write-Host "Fehler: $($_.Exception.Message)" -ForegroundColor Red
        return @{ 
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Send-BlueskyThread {
    param(
        [string]$FullText,
        [bool]$UseRichText = $true
    )
    
    # Text in Posts mit max. 300 Zeichen aufteilen
    $maxLength = 280  # Etwas Puffer für "(1/3)" etc.
    $posts = @()
    
    # Intelligente Aufteilung: Nach Absätzen, dann nach Sätzen
    $paragraphs = $FullText -split "`n`n"
    $currentPost = ""
    
    foreach ($para in $paragraphs) {
        if (($currentPost + $para).Length -le $maxLength) {
            $currentPost += $para + "`n`n"
        } else {
            # Aktuellen Post speichern wenn nicht leer
            if ($currentPost.Trim()) {
                $posts += $currentPost.Trim()
            }
            
            # Paragraph zu lang? Weiter aufteilen nach Sätzen
            if ($para.Length -gt $maxLength) {
                $sentences = $para -split '(?<=[.!?])\s+'
                $currentPost = ""
                
                foreach ($sentence in $sentences) {
                    if (($currentPost + $sentence).Length -le $maxLength) {
                        $currentPost += $sentence + " "
                    } else {
                        if ($currentPost.Trim()) {
                            $posts += $currentPost.Trim()
                        }
                        $currentPost = $sentence + " "
                    }
                }
            } else {
                $currentPost = $para + "`n`n"
            }
        }
    }
    
    # Letzten Post hinzufügen
    if ($currentPost.Trim()) {
        $posts += $currentPost.Trim()
    }
    
    $totalPosts = $posts.Count
    
    if ($totalPosts -eq 1) {
        # Nur ein Post - normal senden
        $facets = if ($UseRichText) { Find-Facets -Text $posts[0] } else { @() }
        return Send-BlueskyPost -Text $posts[0] -Facets $facets
    }
    
    # Thread senden
    Write-Host "`n🧵 Sende Thread mit $totalPosts Posts..." -ForegroundColor Cyan
    
    # $previousUri = $null
    # $previousCid = $null
    $rootUri = $null
    $rootCid = $null
    $results = @()
    
    for ($i = 0; $i -lt $totalPosts; $i++) {
        $postNumber = $i + 1
        $postText = "($postNumber/$totalPosts)`n`n" + $posts[$i]
        
        Write-Host "  📤 Sende Post $postNumber/$totalPosts..." -ForegroundColor Yellow
        
        $facets = if ($UseRichText) { Find-Facets -Text $postText } else { @() }
        
        if ($i -eq 0) {
            # Erster Post
            $result = Send-BlueskyPost -Text $postText -Facets $facets
        } else {
            # Reply auf vorherigen Post
            $result = Send-BlueskyPost -Text $postText -Facets $facets -ReplyToUri $rootUri -ReplyToCid $rootCid
        }
        
        if (-not $result.Success) {
            Write-Host "  ❌ Fehler bei Post $postNumber!" -ForegroundColor Red
            return @{
                Success = $false
                Error = "Fehler bei Post $postNumber`: $($result.Error)"
                PostsSent = $i
            }
        }
        
        # Ersten Post als Root speichern
        if ($i -eq 0) {
            $rootUri = $result.Uri
            $rootCid = $result.Cid
        }
        
        # $previousUri = $result.Uri
        # $previousCid = $result.Cid
        $results += $result
        
        Write-Host "  ✅ Post $postNumber gesendet!" -ForegroundColor Green
        
        # Kleine Pause zwischen Posts
        if ($i -lt $totalPosts - 1) {
            Start-Sleep -Milliseconds 500
        }
    }
    
    Write-Host "`n✅ Thread komplett gesendet! ($totalPosts Posts)" -ForegroundColor Green
    
    return @{
        Success = $true
        ThreadUri = $rootUri
        PostCount = $totalPosts
        Results = $results
    }
}



# ================================
# GUI - HAUPTFENSTER
# ================================
function Show-BlueskyEditorPro {
    # $drafts = Get-Drafts
    $templates = Get-Templates
    
    # Main Form
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Bluesky Post Editor PRO 🚀"
    $form.Size = New-Object System.Drawing.Size(600, 550)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    # ========== HEADER ==========
    $headerLabel = New-Object System.Windows.Forms.Label
    $headerLabel.Text = "Schreibe deinen Bluesky-Post (max. 300 Zeichen):"
    $headerLabel.Location = New-Object System.Drawing.Point(10, 10)
    $headerLabel.Size = New-Object System.Drawing.Size(560, 20)
    $headerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($headerLabel)

    # ========== TOOLBAR ==========
    $toolbarPanel = New-Object System.Windows.Forms.Panel
    $toolbarPanel.Location = New-Object System.Drawing.Point(10, 35)
    $toolbarPanel.Size = New-Object System.Drawing.Size(560, 70)  # Höher für 2 Reihen
    $toolbarPanel.BorderStyle = "FixedSingle"
    $form.Controls.Add($toolbarPanel)

    # Reihe 1
    # Template Button
    $templateBtn = New-Object System.Windows.Forms.Button
    $templateBtn.Text = "Template"
    $templateBtn.Location = New-Object System.Drawing.Point(5, 5)
    $templateBtn.Size = New-Object System.Drawing.Size(90, 25)
    $toolbarPanel.Controls.Add($templateBtn)

    # Draft Button
    $draftBtn = New-Object System.Windows.Forms.Button
    $draftBtn.Text = "Drafts"
    $draftBtn.Location = New-Object System.Drawing.Point(100, 5)
    $draftBtn.Size = New-Object System.Drawing.Size(90, 25)
    $toolbarPanel.Controls.Add($draftBtn)

    # Emoji Button
    $emojiBtn = New-Object System.Windows.Forms.Button
    $emojiBtn.Text = "Emoji"
    $emojiBtn.Location = New-Object System.Drawing.Point(195, 5)
    $emojiBtn.Size = New-Object System.Drawing.Size(90, 25)
    $toolbarPanel.Controls.Add($emojiBtn)

    # Format Button
    $formatBtn = New-Object System.Windows.Forms.Button
    $formatBtn.Text = "Format"
    $formatBtn.Location = New-Object System.Drawing.Point(290, 5)
    $formatBtn.Size = New-Object System.Drawing.Size(90, 25)
    $toolbarPanel.Controls.Add($formatBtn)

    # Clear Button
    $clearBtn = New-Object System.Windows.Forms.Button
    $clearBtn.Text = "Leeren"
    $clearBtn.Location = New-Object System.Drawing.Point(385, 5)
    $clearBtn.Size = New-Object System.Drawing.Size(90, 25)
    $clearBtn.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $toolbarPanel.Controls.Add($clearBtn)

    # Reihe 2
    # Rich Text Toggle
    $richTextCheckbox = New-Object System.Windows.Forms.CheckBox
    $richTextCheckbox.Text = "Rich Text aktivieren (Links, Mentions, Hashtags)"
    $richTextCheckbox.Location = New-Object System.Drawing.Point(10, 40)
    $richTextCheckbox.Size = New-Object System.Drawing.Size(350, 20)
    $richTextCheckbox.Checked = $true
    $toolbarPanel.Controls.Add($richTextCheckbox)

    # ========== TEXT AREA ==========
    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Multiline = $true
    $textBox.ScrollBars = "Vertical"
    $textBox.Location = New-Object System.Drawing.Point(10, 115)  # Y-Position angepasst
    $textBox.Size = New-Object System.Drawing.Size(560, 215)  # Etwas kleiner
    $textBox.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $textBox.AcceptsReturn = $true
    $textBox.AcceptsTab = $false
    $textBox.HideSelection = $false  # ⭐ WICHTIG: Selektion bleibt sichtbar!
    $form.Controls.Add($textBox)

    # ========== COUNTER & INFO ==========
    $counterLabel = New-Object System.Windows.Forms.Label
    $counterLabel.Location = New-Object System.Drawing.Point(10, 340)
    $counterLabel.Size = New-Object System.Drawing.Size(400, 20)
    $counterLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($counterLabel)

    $facetLabel = New-Object System.Windows.Forms.Label
    $facetLabel.Location = New-Object System.Drawing.Point(10, 360)
    $facetLabel.Size = New-Object System.Drawing.Size(560, 20)
    $facetLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $facetLabel.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($facetLabel)

    # Update Counter
    $updateCounter = {
        $length = $textBox.Text.Length
        $remaining = 300 - $length
        $words = ($textBox.Text -split '\s+' | Where-Object { $_ -ne '' }).Count

        if ($remaining -lt 0) {
            $counterLabel.Text = "Wörter: $words | Zeichen: $length/300 | $([Math]::Abs($remaining)) zu viel!"
            $counterLabel.ForeColor = [System.Drawing.Color]::Red
        } elseif ($remaining -lt 50) {
            $counterLabel.Text = "Wörter: $words | Zeichen: $length/300 | Verbleibend: $remaining"
            $counterLabel.ForeColor = [System.Drawing.Color]::Orange
        } else {
            $counterLabel.Text = "Wörter: $words | Zeichen: $length/300 | Verbleibend: $remaining"
            $counterLabel.ForeColor = [System.Drawing.Color]::Green
        }
        
        # Facets anzeigen wenn Rich Text aktiv
        if ($richTextCheckbox.Checked) {
            $facets = Find-Facets -Text $textBox.Text
            $urlCount = ($facets | Where-Object { $_.features[0].'$type' -eq 'app.bsky.richtext.facet#link' }).Count
            $mentionCount = ($facets | Where-Object { $_.features[0].'$type' -eq 'app.bsky.richtext.facet#mention' }).Count
            $hashtagCount = ($facets | Where-Object { $_.features[0].'$type' -eq 'app.bsky.richtext.facet#tag' }).Count
            
            $facetLabel.Text = "Links: $urlCount | @Mentions: $mentionCount | #Hashtags: $hashtagCount"
        } else {
            $facetLabel.Text = ""
        }
    }

    $textBox.Add_TextChanged($updateCounter)
    & $updateCounter

    # ========== BUTTONS ==========
    $buttonY = 390

    # Save Draft Button
    $saveDraftBtn = New-Object System.Windows.Forms.Button
    $saveDraftBtn.Text = "Draft speichern"
    $saveDraftBtn.Location = New-Object System.Drawing.Point(10, $buttonY)
    $saveDraftBtn.Size = New-Object System.Drawing.Size(130, 35)
    $form.Controls.Add($saveDraftBtn)

    # Preview Button
    $previewBtn = New-Object System.Windows.Forms.Button
    $previewBtn.Text = "Vorschau"
    $previewBtn.Location = New-Object System.Drawing.Point(150, $buttonY)
    $previewBtn.Size = New-Object System.Drawing.Size(100, 35)
    $form.Controls.Add($previewBtn)

    # Send Button
    $sendBtn = New-Object System.Windows.Forms.Button
    $sendBtn.Text = "Senden"
    $sendBtn.Location = New-Object System.Drawing.Point(260, $buttonY)
    $sendBtn.Size = New-Object System.Drawing.Size(100, 35)
    $sendBtn.BackColor = [System.Drawing.Color]::LightGreen
    $sendBtn.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $form.Controls.Add($sendBtn)

    # Cancel Button
    $cancelBtn = New-Object System.Windows.Forms.Button
    $cancelBtn.Text = "Abbrechen"
    $cancelBtn.Location = New-Object System.Drawing.Point(370, $buttonY)
    $cancelBtn.Size = New-Object System.Drawing.Size(100, 35)
    $cancelBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelBtn)

    # Status Label
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Location = New-Object System.Drawing.Point(10, 435)
    $statusLabel.Size = New-Object System.Drawing.Size(560, 30)
    $statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $statusLabel.Visible = $false
    $form.Controls.Add($statusLabel)

    # ========== EVENT HANDLERS ==========
    
    # Template Button
    $templateBtn.Add_Click({
        $templateForm = New-Object System.Windows.Forms.Form
        $templateForm.Text = "Template auswählen"
        $templateForm.Size = New-Object System.Drawing.Size(400, 300)
        $templateForm.StartPosition = "CenterParent"
        $templateForm.FormBorderStyle = "FixedDialog"
        
        $listBox = New-Object System.Windows.Forms.ListBox
        $listBox.Location = New-Object System.Drawing.Point(10, 10)
        $listBox.Size = New-Object System.Drawing.Size(360, 200)
        $templates | ForEach-Object { $listBox.Items.Add($_.Name) }
        $templateForm.Controls.Add($listBox)
        
        $okBtn = New-Object System.Windows.Forms.Button
        $okBtn.Text = "Auswählen"
        $okBtn.Location = New-Object System.Drawing.Point(10, 220)
        $okBtn.Size = New-Object System.Drawing.Size(100, 30)
        $okBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $templateForm.Controls.Add($okBtn)
        
        $cancelTemplateBtn = New-Object System.Windows.Forms.Button
        $cancelTemplateBtn.Text = "Abbrechen"
        $cancelTemplateBtn.Location = New-Object System.Drawing.Point(120, 220)
        $cancelTemplateBtn.Size = New-Object System.Drawing.Size(100, 30)
        $cancelTemplateBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $templateForm.Controls.Add($cancelTemplateBtn)
        
        if ($templateForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $listBox.SelectedIndex -ge 0) {
            $textBox.Text = $templates[$listBox.SelectedIndex].Text
        }
    })

    # Draft Button
    $draftBtn.Add_Click({
        $draftForm = New-Object System.Windows.Forms.Form
        $draftForm.Text = "Draft laden"
        $draftForm.Size = New-Object System.Drawing.Size(500, 350)
        $draftForm.StartPosition = "CenterParent"
        $draftForm.FormBorderStyle = "FixedDialog"
        
        $listBox = New-Object System.Windows.Forms.ListBox
        $listBox.Location = New-Object System.Drawing.Point(10, 10)
        $listBox.Size = New-Object System.Drawing.Size(460, 250)
        
        $currentDrafts = Get-Drafts
        $currentDrafts | ForEach-Object {
            $preview = if ($_.Text.Length -gt 60) { $_.Text.Substring(0, 60) + "..." } else { $_.Text }
            $listBox.Items.Add("[$($_.Date)] $preview")
        }
        $draftForm.Controls.Add($listBox)
        
        $loadBtn = New-Object System.Windows.Forms.Button
        $loadBtn.Text = "Laden"
        $loadBtn.Location = New-Object System.Drawing.Point(10, 270)
        $loadBtn.Size = New-Object System.Drawing.Size(100, 30)
        $loadBtn.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $draftForm.Controls.Add($loadBtn)
        
        $deleteBtn = New-Object System.Windows.Forms.Button
        $deleteBtn.Text = "Löschen"
        $deleteBtn.Location = New-Object System.Drawing.Point(120, 270)
        $deleteBtn.Size = New-Object System.Drawing.Size(100, 30)
        $draftForm.Controls.Add($deleteBtn)
        
        $deleteBtn.Add_Click({
            if ($listBox.SelectedIndex -ge 0) {
                $currentDrafts = Get-Drafts
                $currentDrafts = $currentDrafts | Where-Object { $_ -ne $currentDrafts[$listBox.SelectedIndex] }
                Save-Drafts -Drafts $currentDrafts
                $listBox.Items.RemoveAt($listBox.SelectedIndex)
            }
        })
        
        $cancelDraftBtn = New-Object System.Windows.Forms.Button
        $cancelDraftBtn.Text = "Abbrechen"
        $cancelDraftBtn.Location = New-Object System.Drawing.Point(230, 270)
        $cancelDraftBtn.Size = New-Object System.Drawing.Size(100, 30)
        $cancelDraftBtn.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $draftForm.Controls.Add($cancelDraftBtn)
        
        if ($draftForm.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $listBox.SelectedIndex -ge 0) {
            $textBox.Text = $currentDrafts[$listBox.SelectedIndex].Text
        }
    })

    # Emoji Button
    $emojiBtn.Add_Click({
        $emojis = @(
            "😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃",
            "😉","😊","😇","🥰","😍","🤩","😘","😗","😚","😙",
            "👍","👎","👏","🙌","👋","🤝","💪","🙏","❤️","🧡",
            "💛","💚","💙","💜","🖤","🤍","🤎","💔","❣️","💕",
            "💯","🔥","✨","⭐","🌟","💫","🎉","🎊","🎈","🎁",
            "🏆","🥇","🥈","🥉","🏅","🎖️","📢","📣","📯","🔔",
            "🚀","💡","📝","📚","📖","✍️","📌","📍","🎯","✅"
        )
        
        $emojiForm = New-Object System.Windows.Forms.Form
        $emojiForm.Text = "Emoji auswählen"
        $emojiForm.Size = New-Object System.Drawing.Size(450, 400)
        $emojiForm.StartPosition = "CenterParent"
        $emojiForm.FormBorderStyle = "FixedDialog"
        
        $panel = New-Object System.Windows.Forms.FlowLayoutPanel
        $panel.Location = New-Object System.Drawing.Point(10, 10)
        $panel.Size = New-Object System.Drawing.Size(410, 330)
        $panel.AutoScroll = $true
        $emojiForm.Controls.Add($panel)
        
        foreach ($emoji in $emojis) {
            $btn = New-Object System.Windows.Forms.Button
            $btn.Text = $emoji
            $btn.Size = New-Object System.Drawing.Size(40, 40)
            $btn.Font = New-Object System.Drawing.Font("Segoe UI Emoji", 14)
            $btn.Add_Click({
                $textBox.SelectedText = $this.Text
                $emojiForm.Close()
            }.GetNewClosure())
            $panel.Controls.Add($btn)
        }
        
        $emojiForm.ShowDialog()
    })

    # Format Button Event Handler
    # Format Button Event Handler
    $formatBtn.Add_Click({
        # ⭐ Selektion VOR Menu-Anzeige speichern
        $script:selStart = $textBox.SelectionStart
        $script:selLength = $textBox.SelectionLength
        $script:selText = $textBox.SelectedText
        
        Write-Host "Gespeicherte Selektion: Start=$($script:selStart), Länge=$($script:selLength), Text='$($script:selText)'" -ForegroundColor Yellow
        
        $formatMenu = New-Object System.Windows.Forms.ContextMenuStrip
        
        # Lokale Referenz auf $textBox für Closure
        $script:txtBox = $textBox
        
        # Funktionen in Script-Scope kopieren
        $script:ConvertBold = ${function:Convert-ToPseudoBold}
        $script:ConvertItalic = ${function:Convert-ToPseudoItalic}
        $script:ConvertMono = ${function:Convert-ToMonospace}
        
        # Bold (Pseudo mit Unicode)
        $boldItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $boldItem.Text = "𝗙𝗲𝘁𝘁 (Unicode)"
        $boldItem.Add_Click({
            Write-Host "Bold-Click: Text='$($script:selText)'" -ForegroundColor Magenta
            # ⭐ Script-Scope Variablen verwenden
            if ($script:selText) {
                $bold = & $script:ConvertBold -Text $script:selText
                # Selektion wiederherstellen und ersetzen
                $script:txtBox.Select($script:selStart, $script:selLength)
                $script:txtBox.SelectedText = $bold
                $script:txtBox.Focus()
            } else {
                [System.Windows.Forms.MessageBox]::Show("Bitte Text markieren!", "Hinweis", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
        })
        $formatMenu.Items.Add($boldItem)
        
        # Italic (Pseudo mit Unicode)
        $italicItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $italicItem.Text = "𝘒𝘶𝘳𝘴𝘪𝘷 (Unicode)"
        $italicItem.Add_Click({
            if ($script:selText) {
                $italic = & $script:ConvertItalic -Text $script:selText
                $script:txtBox.Select($script:selStart, $script:selLength)
                $script:txtBox.SelectedText = $italic
                $script:txtBox.Focus()
            } else {
                [System.Windows.Forms.MessageBox]::Show("Bitte Text markieren!", "Hinweis", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            }
        })
        $formatMenu.Items.Add($italicItem)
        
        # Separator
        $formatMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        
        # Quote Block
        $quoteItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $quoteItem.Text = "❝ Zitat-Block"
        $quoteItem.Add_Click({
            if ($script:selText) {
                $lines = $script:selText -split "`n"
                $quoted = ($lines | ForEach-Object { "❝ $_" }) -join "`n"
                $script:txtBox.Select($script:selStart, $script:selLength)
                $script:txtBox.SelectedText = $quoted
                $script:txtBox.Focus()
            }
        })
        $formatMenu.Items.Add($quoteItem)
        
        # Bullet List
        $bulletItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $bulletItem.Text = "• Aufzählung"
        $bulletItem.Add_Click({
            if ($script:selText) {
                $lines = $script:selText -split "`n"
                $bullets = ($lines | ForEach-Object { "• $_" }) -join "`n"
                $script:txtBox.Select($script:selStart, $script:selLength)
                $script:txtBox.SelectedText = $bullets
                $script:txtBox.Focus()
            }
        })
        $formatMenu.Items.Add($bulletItem)
        
        # Numbered List
        $numberedItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $numberedItem.Text = "1️⃣ Nummerierung"
        $numberedItem.Add_Click({
            if ($script:selText) {
                $lines = $script:selText -split "`n"
                $numbered = for ($i = 0; $i -lt $lines.Count; $i++) {
                    "$($i+1). $($lines[$i])"
                }
                $script:txtBox.Select($script:selStart, $script:selLength)
                $script:txtBox.SelectedText = ($numbered -join "`n")
                $script:txtBox.Focus()
            }
        })
        $formatMenu.Items.Add($numberedItem)
        
        # Code Block (Monospace)
        $codeItem = New-Object System.Windows.Forms.ToolStripMenuItem
        $codeItem.Text = "𝙲𝚘𝚍𝚎 (Monospace)"
        $codeItem.Add_Click({
            if ($script:selText) {
                $code = & $script:ConvertMono -Text $script:selText
                $script:txtBox.Select($script:selStart, $script:selLength)
                $script:txtBox.SelectedText = $code
                $script:txtBox.Focus()
            }
        })
        $formatMenu.Items.Add($codeItem)
        
        $formatMenu.Show($formatBtn, (New-Object System.Drawing.Point(0, $formatBtn.Height)))
    })


    # Clear Button
    $clearBtn.Add_Click({
        if ([System.Windows.Forms.MessageBox]::Show("Text wirklich leeren?", "Bestätigung", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question) -eq [System.Windows.Forms.DialogResult]::Yes) {
            $textBox.Clear()
        }
    })

    # Save Draft Button
    $saveDraftBtn.Add_Click({
        if ([string]::IsNullOrEmpty($textBox.Text.Trim())) {
            [System.Windows.Forms.MessageBox]::Show("Kein Text zum Speichern!", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        # Drafts laden als echtes Array
        $currentDrafts = @(Get-Drafts)
        
        $newDraft = @{
            Date = (Get-Date).ToString("dd.MM.yyyy HH:mm")
            Text = $textBox.Text
        }
        
        # Als ArrayList behandeln oder neues Array erstellen
        $updatedDrafts = [System.Collections.ArrayList]::new()
        $currentDrafts | ForEach-Object { $updatedDrafts.Add($_) | Out-Null }
        $updatedDrafts.Add($newDraft) | Out-Null
        
        Save-Drafts -Drafts $updatedDrafts.ToArray()
        
        [System.Windows.Forms.MessageBox]::Show("Draft gespeichert!", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    })

    # Preview Button
    $previewBtn.Add_Click({
        $text = $textBox.Text.Trim()
        if ([string]::IsNullOrEmpty($text)) {
            [System.Windows.Forms.MessageBox]::Show("Kein Text eingegeben!", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $length = $text.Length
        $words = ($text -split '\s+' | Where-Object { $_ -ne '' }).Count
        $remaining = 300 - $length
        
        $facets = if ($richTextCheckbox.Checked) { Find-Facets -Text $text } else { @() }
        $facetInfo = if ($facets.Count -gt 0) {
            $urlCount = ($facets | Where-Object { $_.features[0].'$type' -eq 'app.bsky.richtext.facet#link' }).Count
            $mentionCount = ($facets | Where-Object { $_.features[0].'$type' -eq 'app.bsky.richtext.facet#mention' }).Count
            $hashtagCount = ($facets | Where-Object { $_.features[0].'$type' -eq 'app.bsky.richtext.facet#tag' }).Count
            "`n`nRICH TEXT:`nLinks: $urlCount | @Mentions: $mentionCount | #Hashtags: $hashtagCount"
        } else { "" }

        $previewText = @"
STATISTIKEN:
Wörter: $words
Zeichen: $length/300
Verbleibend: $remaining$facetInfo

DEIN POST:
─────────────────
$text
─────────────────
"@

        if ($length -gt 300) {
            $result = [System.Windows.Forms.MessageBox]::Show("$previewText`n`n❌ Text ist zu lang! Nochmal bearbeiten?", "Vorschau - ZU LANG", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                $textBox.Focus()
            }
        } else {
            [System.Windows.Forms.MessageBox]::Show($previewText, "Vorschau - Bereit zum Senden", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })

    # Send Button
    $sendBtn.Add_Click({
        $text = $textBox.Text.Trim()
        if ([string]::IsNullOrEmpty($text)) {
            [System.Windows.Forms.MessageBox]::Show("Kein Text eingegeben!", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        # Prüfen ob Thread nötig ist
        $needsThread = $text.Length -gt 300
        
        if ($needsThread) {
            $estimatedPosts = [Math]::Ceiling($text.Length / 280)
            $result = [System.Windows.Forms.MessageBox]::Show(
                "Text ist $($text.Length) Zeichen lang.`n`nAls Thread senden (~$estimatedPosts Posts)?`n`nJa = Thread | Nein = Einzelpost (wird gekürzt)", 
                "Thread erstellen?", 
                [System.Windows.Forms.MessageBoxButtons]::YesNoCancel, 
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            if ($result -eq [System.Windows.Forms.DialogResult]::Cancel) {
                return
            }
            
            $sendAsThread = ($result -eq [System.Windows.Forms.DialogResult]::Yes)
        } else {
            # Normaler Post
            $result = [System.Windows.Forms.MessageBox]::Show("Post jetzt an Bluesky senden?", "Bestätigung", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($result -ne [System.Windows.Forms.DialogResult]::Yes) {
                return
            }
            $sendAsThread = $false
        }

        $sendBtn.Enabled = $false
        $previewBtn.Enabled = $false
        $cancelBtn.Enabled = $false
        
        if ($sendAsThread) {
            $statusLabel.Text = "🧵 Thread wird gesendet..."
        } else {
            $statusLabel.Text = "📤 Post wird gesendet..."
        }
        $statusLabel.ForeColor = [System.Drawing.Color]::Blue
        $statusLabel.Visible = $true
        $form.Refresh()

        try {
            if ($sendAsThread) {
                # Als Thread senden
                $result = Send-BlueskyThread -FullText $text -UseRichText $richTextCheckbox.Checked
                
                if ($result.Success) {
                    $statusLabel.Text = "✅ Thread erfolgreich gesendet! ($($result.PostCount) Posts)"
                    $statusLabel.ForeColor = [System.Drawing.Color]::Green
                    
                    [System.Windows.Forms.MessageBox]::Show(
                        "Thread erfolgreich gesendet!`n`nAnzahl Posts: $($result.PostCount)`nThread-URI: $($result.ThreadUri)", 
                        "Erfolg", 
                        [System.Windows.Forms.MessageBoxButtons]::OK, 
                        [System.Windows.Forms.MessageBoxIcon]::Information
                    )
                    
                    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                    $form.Close()
                } else {
                    $statusLabel.Text = "❌ Fehler beim Senden!"
                    $statusLabel.ForeColor = [System.Drawing.Color]::Red
                    
                    [System.Windows.Forms.MessageBox]::Show("Fehler beim Senden:`n`n$($result.Error)", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    
                    $sendBtn.Enabled = $true
                    $previewBtn.Enabled = $true
                    $cancelBtn.Enabled = $true
                }
            } else {
                # Normal senden
                $facets = if ($richTextCheckbox.Checked) { Find-Facets -Text $text } else { @() }
                $result = Send-BlueskyPost -Text $text -Facets $facets
                
                if ($result.Success) {
                    $statusLabel.Text = "✅ Post erfolgreich gesendet!"
                    $statusLabel.ForeColor = [System.Drawing.Color]::Green
                    
                    [System.Windows.Forms.MessageBox]::Show("Post erfolgreich gesendet!`n`nURI: $($result.Uri)", "Erfolg", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    
                    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                    $form.Close()
                } else {
                    $statusLabel.Text = "❌ Fehler beim Senden!"
                    $statusLabel.ForeColor = [System.Drawing.Color]::Red
                    
                    [System.Windows.Forms.MessageBox]::Show("Fehler beim Senden:`n`n$($result.Error)", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    
                    $sendBtn.Enabled = $true
                    $previewBtn.Enabled = $true
                    $cancelBtn.Enabled = $true
                }
            }
        } catch {
            $statusLabel.Text = "❌ Unerwarteter Fehler!"
            $statusLabel.ForeColor = [System.Drawing.Color]::Red

            [System.Windows.Forms.MessageBox]::Show("Unerwarteter Fehler:`n`n$($_.Exception.Message)", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)

            $sendBtn.Enabled = $true
            $previewBtn.Enabled = $true
            $cancelBtn.Enabled = $true
        }
    })

    # Form Settings
    $form.AcceptButton = $sendBtn
    $form.CancelButton = $cancelBtn
    $textBox.Focus()

    $form.ShowDialog()
}

# ================================
# SCRIPT ENTRY POINT
# ================================
Write-Host "╔════════════════════════════════════════╗" -ForegroundColor $titleColor
Write-Host "║  Bluesky PowerShell Client - PRO 🚀    ║" -ForegroundColor $titleColor
Write-Host "╚════════════════════════════════════════╝" -ForegroundColor $titleColor
Write-Host ""

if ([string]::IsNullOrEmpty($BlueskyHandle) -or $BlueskyHandle -eq "dein.handle.bsky.social") {
    Write-Host "❌ FEHLER: Bitte Handle und App-Password im Script eintragen!" -ForegroundColor $errorColor
    Write-Host "📝 Zeile 24-25 bearbeiten!" -ForegroundColor $highlightColor
    Read-Host "Enter drücken zum Beenden"
    exit
}

Show-BlueskyEditorPro

Write-Host ""
Write-Host "👋 Auf Wiedersehen" -ForegroundColor $subtextColor
