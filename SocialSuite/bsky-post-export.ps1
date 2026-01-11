<#
.SYNOPSIS
    Exportiert eigene Bluesky Posts als Markdown
.DESCRIPTION
    Lädt alle eigene Posts und speichert sie chronologisch als Markdown
    
    Kompatibel mit PowerShell 5.1+ und PowerShell 7+
    
.EXAMPLE
    .\bsky-post-export.ps1
    .\bsky-post-export.ps1 -FromDate "2025-01-01"
    .\bsky-post-export.ps1 -FromDate "2025-01-01" -DownloadImages
.NOTES
    Kompatibilität: PowerShell 5.1+ und PowerShell 7+
    File Name      : bsky-post-export.ps1
    Author         : Oliver C. Tank
    Prerequisite   : PowerShell 7.0+
    Copyright      : 2025 - MIT License
    Version        : 1.0.0
    Created        : 2025-01-15
    Last Modified  : 2025-12-28

.LINK
    https://github.com/octank1/octoScripts/tree/main/SocialMediaController

.EXAMPLE
    .\bsky-post-export.ps1
    Exportiert eigene Bluesky Posts als Markdown

.COMPONENT
    Benötigt: lib/config-mgr.psm1

.LICENSE
    MIT License
    
    Copyright (c) 2025 Oliver C. Tank
    
    Details siehe .\LICENSE 
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false, HelpMessage="Datum ab dem Posts exportiert werden (z.B. '2025-01-01'). Standard: Erster Tag des aktuellen Monats")]
    [DateTime]$FromDate = (Get-Date).StartOfMonth(),
    
    [Parameter(Mandatory=$false, HelpMessage="Ordner in den die Posts exportiert werden. Standard: .\exports\bluesky-posts")]
    [string]$OutputFolder = ".\exports\bluesky-posts",

    [Parameter(Mandatory=$false, HelpMessage="Replies (Antworten) von der Export ausgeschlossen werden")]
    [switch]$ExcludeReplies,
    
    [Parameter(Mandatory=$false, HelpMessage="Bilder aus den Posts herunterladen")]
    [switch]$DownloadImages
)

# ================================
# ENCODING SETUP
# ================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# ================================
# CONFIG LADEN
# ================================
Import-Module (Join-Path $PSScriptRoot "lib\config-mgr.psm1") -Force

if (-not (Initialize-Config)) {
    Write-Host "`n⚠️  Bitte config.json anpassen und Script neu starten!" -ForegroundColor Yellow
    Read-Host "Enter drücken zum Beenden"
    exit
}

$config = Get-Config

if (-not $config) {
    Write-Host "❌ Konfiguration konnte nicht geladen werden!" -ForegroundColor Red
    Read-Host "Enter drücken zum Beenden"
    exit
}

$BlueskyAppPassword = Get-Secret -Key "bluesky.appPassword"
if ([string]::IsNullOrEmpty($BlueskyAppPassword)) {
    Write-Host "`n⚠️  Bluesky App-Password nicht konfiguriert!" -ForegroundColor Yellow
    Write-Host "📝 Bitte Setup durchführen: Start-ConfigSetup" -ForegroundColor Cyan
    Read-Host "Enter drücken zum Beenden"
    exit
}
$BlueskyHandle = $config.settings.bluesky.handle

# Ausgabepfad aus Config (falls definiert)
if ($config.settings.bluesky.postExportPath -and -not $PSBoundParameters.ContainsKey('OutputFolder')) {
    $OutputFolder = $config.settings.bluesky.postExportPath
}

# Ordner erstellen
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}

$AttachmentsFolder = Join-Path $OutputFolder "_attachments"
if ($DownloadImages -and -not (Test-Path $AttachmentsFolder)) {
    New-Item -ItemType Directory -Path $AttachmentsFolder | Out-Null
}

$BaseUrl = "https://bsky.social/xrpc"
$subtextColor = $config.settings.general.subtextColor
$titleColor = $config.settings.general.titleColor
$statusColor = $config.settings.general.statusColor
$errorColor = $config.settings.general.errorColor
$successColor = $config.settings.general.successColor

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $titleColor
Write-Host "║        🦋 BLUESKY POST EXPORT - by Wolli White 🦋              ║" -ForegroundColor $titleColor
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $titleColor
Write-Host ""

# ==== LOGIN ====
Write-Host "🔑 Melde mich bei Bluesky an..." -ForegroundColor $statusColor

$loginBody = @{
    identifier = $BlueskyHandle
    password = $BlueskyAppPassword
} | ConvertTo-Json

try {
    $session = Invoke-RestMethod -Uri "$BaseUrl/com.atproto.server.createSession" `
        -Method POST -ContentType "application/json" -Body $loginBody
    
    $accessToken = $session.accessJwt
    $myDid = $session.did
    
    Write-Host "✅ Login erfolgreich als: $BlueskyHandle" -ForegroundColor $successColor
} catch {
    Write-Host "❌ Login fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor $errorColor
    exit
}

# ==== POSTS LADEN ====
Write-Host "`n📥 Lade eigene Posts..." -ForegroundColor $statusColor
Write-Host "📅 Ab Datum: $($FromDate.ToString('dd.MM.yyyy'))" -ForegroundColor $statusColor

$allPosts = @()
$cursor = $null
$totalLoaded = 0
$totalScanned = 0
$stopLoading = $false

do {
    $retryCount = 0
    $maxRetries = 3
    $success = $false
    
    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            $url = "$BaseUrl/app.bsky.feed.getAuthorFeed?actor=$myDid&limit=100"
            if ($cursor) {
                $url += "&cursor=$cursor"
            }
            
            $response = Invoke-RestMethod -Uri $url `
                -Headers @{ Authorization = "Bearer $accessToken" } `
                -ContentType "application/json" `
                -TimeoutSec 30
            
            $success = $true
            
        } catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "  ⚠️ Fehler (Versuch $retryCount/$maxRetries): $($_.Exception.Message)" -ForegroundColor $errorColor
                Write-Host "  ⏳ Warte 5 Sekunden..." -ForegroundColor $statusColor
                Start-Sleep -Seconds 5
            } else {
                Write-Host "  ❌ Fehler nach $maxRetries Versuchen: $($_.Exception.Message)" -ForegroundColor $errorColor
                throw
            }
        }
    }
    
    if (-not $success) {
        Write-Host "⚠️ Konnte Posts nicht laden, breche ab." -ForegroundColor $errorColor
        break
    }

    $posts = $response.feed | Where-Object { 
        $_.post.author.did -eq $myDid
    }
    
    if (-not $posts -or $posts.Count -eq 0) {
        Write-Host "  ✅ Keine weiteren Posts vorhanden." -ForegroundColor $statusColor
        break
    }
    
    $newPostsInBatch = 0
    $scannedInBatch = 0
    $oldestInBatch = $null
    $newestInBatch = $null
    
    foreach ($item in $posts) {
        $post = $item.post
        $scannedInBatch++
        $totalScanned++
        
        try {
            # Smart DateTime Handling (PS 5.1 + PS 7 kompatibel)
            if ($post.indexedAt -is [DateTime]) {
                # PowerShell 7: Bereits DateTime-Objekt
                $postDate = $post.indexedAt
            } elseif ($post.indexedAt -is [string]) {
                # PowerShell 5.1: String → DateTime konvertieren
                $postDate = [DateTime]::Parse($post.indexedAt)
            } else {
                # Fallback: ToString + Parse
                $postDate = [DateTime]::Parse($post.indexedAt.ToString())
            }
            
            # Ältesten/Neuesten Post im Batch merken
            if (-not $oldestInBatch -or $postDate -lt $oldestInBatch) {
                $oldestInBatch = $postDate
            }
            if (-not $newestInBatch -or $postDate -gt $newestInBatch) {
                $newestInBatch = $postDate
            }
            
            # Datum-Check - Posts NACH FromDate behalten
            if ($postDate -ge $FromDate) {
                # Reply-Check (optional)
                $isReply = $null -ne $post.record.reply
                if (-not ($ExcludeReplies -and $isReply)) {
                    $allPosts += $post
                    $totalLoaded++
                    $newPostsInBatch++
                }
            }
            
        } catch {
            Write-Verbose "Post-Datum konnte nicht geparst werden: $_ (Typ: $($post.indexedAt.GetType().Name))" -ForegroundColor $errorColor
        }
    }
    
    # Status-Output
    $oldestDateStr = if ($oldestInBatch) { $oldestInBatch.ToString('dd.MM.yyyy HH:mm') } else { "N/A" }
    $newestDateStr = if ($newestInBatch) { $newestInBatch.ToString('dd.MM.yyyy HH:mm') } else { "N/A" }
    
    Write-Host "  📊 Batch: $scannedInBatch Posts ($newestDateStr - $oldestDateStr) → $newPostsInBatch relevant | Gesamt: $totalLoaded" -ForegroundColor $statusColor
    
    # Abbruch-Logik: Wenn der ÄLTESTE Post im Batch älter als FromDate ist
    if ($oldestInBatch -and $oldestInBatch -lt $FromDate) {
        Write-Host "  ✅ Alle Posts bis $($FromDate.ToString('dd.MM.yyyy')) durchsucht!" -ForegroundColor $successColor
        $stopLoading = $true
    }
    
    # Cursor-Check (PS 5.1 + PS 7 kompatibel)
    $oldCursor = $cursor
    if ($response.cursor) {
        if ($response.cursor -is [DateTime]) {
            # PowerShell 7: DateTime → ISO-String
            $cursor = $response.cursor.ToString("yyyy-MM-dd'T'HH:mm:ss.ff'Z'")
        } elseif ($response.cursor -is [string]) {
            # PowerShell 5.1: String → DateTime → ISO-String (Normalisierung)
            $cursorDate = [DateTime]::Parse($response.cursor)
            $cursor = $cursorDate.ToString("yyyy-MM-dd'T'HH:mm:ss.ff'Z'")
        } else {
            # Fallback
            $cursor = $response.cursor.ToString()
        }
    } else {
        $cursor = $null
    }
    
    if ($cursor -eq $oldCursor -or [string]::IsNullOrEmpty($cursor)) {
        Write-Host "  ✅ Ende der Timeline erreicht!" -ForegroundColor $successColor
        break
    }
    
    # Rate-Limit-Schutz
    Start-Sleep -Milliseconds 300
    
} while ($cursor -and -not $stopLoading -and $totalScanned -lt 20000)

Write-Host ""
Write-Host "📊 Gescannt: $totalScanned Posts | Geladen: $totalLoaded Posts (ab $($FromDate.ToString('dd.MM.yyyy')))" -ForegroundColor $statusColor

if ($allPosts.Count -eq 0) {
    Write-Host "`n⚠️  Keine Posts seit $($FromDate.ToString('dd.MM.yyyy')) gefunden!" -ForegroundColor $errorColor
    Write-Host "💡 Tipp: Versuche ein älteres Datum (z.B. -FromDate '2024-01-01')" -ForegroundColor $subtextColor
    exit
}

# Statistik
$replyCount = ($allPosts | Where-Object { $_.record.reply -ne $null }).Count
$originalCount = $allPosts.Count - $replyCount
$postsWithImages = ($allPosts | Where-Object { $_.embed.images }).Count

Write-Host "`n📊 Statistik:" -ForegroundColor $subtextColor
Write-Host "   📝 Original-Posts: $originalCount" -ForegroundColor $subtextColor
Write-Host "   💬 Antworten: $replyCount" -ForegroundColor $subtextColor
if ($postsWithImages -gt 0) {
    Write-Host "   📷 Posts mit Bildern: $postsWithImages" -ForegroundColor $subtextColor
}

# ==== BILDER HERUNTERLADEN ====
$imageCounter = 0
$imageMap = @{}

if ($DownloadImages -and $postsWithImages -gt 0) {
    Write-Host "`n📷 Lade Bilder herunter..." -ForegroundColor $statusColor
    
    foreach ($post in $allPosts) {
        if (-not $post.embed.images) { continue }
        
        # Smart DateTime Handling
        if ($post.indexedAt -is [DateTime]) {
            $postDate = $post.indexedAt
        } else {
            $postDate = [DateTime]::Parse($post.indexedAt)
        }
        $datePrefix = $postDate.ToString("yyyyMMdd-HHmmss")
        
        $postImages = @()
        
        for ($i = 0; $i -lt $post.embed.images.Count; $i++) {
            $img = $post.embed.images[$i]
            
            try {
                # Bluesky Image URL
                $imageUrl = $img.fullsize
                
                # Dateiname generieren
                $ext = if ($imageUrl -match '\.(\w+)(@|$)') { $Matches[1] } else { "jpg" }
                $fileName = "${datePrefix}_img${i}.$ext"
                $filePath = Join-Path $AttachmentsFolder $fileName
                
                # Download (nur wenn noch nicht vorhanden)
                if (-not (Test-Path $filePath)) {
                    Invoke-WebRequest -Uri $imageUrl -OutFile $filePath -ErrorAction Stop
                    $imageCounter++
                    Write-Host "  📥 $fileName" -ForegroundColor Gray
                }
                
                $postImages += @{
                    Path = "_attachments/$fileName"
                    Alt = $img.alt
                }
                
            } catch {
                Write-Warning "  ⚠️ Bild konnte nicht geladen werden: $imageUrl" 
            }
        }
        
        # Bilder diesem Post zuordnen
        if ($postImages.Count -gt 0) {
            $imageMap[$post.uri] = $postImages
        }
    }
    
    Write-Host "✅ $imageCounter Bilder heruntergeladen!" -ForegroundColor $successColor
}

# ==== MARKDOWN GENERIEREN ====
Write-Host "`n📝 Generiere Markdown..." -ForegroundColor $statusColor
$sortedPosts = $allPosts | Sort-Object indexedAt

$dateStr = $FromDate.ToString("yyyy-MM-dd")
$outputFile = Join-Path $OutputFolder $config.settings.bluesky.postExportFilename

$md = @()
$md += "# 🦋 Meine Bluesky Posts"
$md += ""
$md += "**Exportiert am:** $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')"
$md += "**Ab Datum:** $($FromDate.ToString('dd.MM.yyyy'))"
$md += "**Anzahl Posts:** $($sortedPosts.Count)"
$md += "**Account:** @$BlueskyHandle"
$md += ""
$md += "---"
$md += ""

$currentMonth = $null

foreach ($post in $sortedPosts) {
    try {
        # Smart DateTime Handling
        if ($post.indexedAt -is [DateTime]) {
            $postDate = $post.indexedAt
        } else {
            $postDate = [DateTime]::Parse($post.indexedAt)
        }
        
        $monthStr = $postDate.ToString("MMMM yyyy")
        $dateStr = $postDate.ToString("dd.MM.yyyy")
        $timeStr = $postDate.ToString("HH:mm")
        
        if ($currentMonth -ne $monthStr) {
            $currentMonth = $monthStr
            $md += ""
            $md += "## 📅 $monthStr"
            $md += ""
        }
        
        $isReply = $null -ne $post.record.reply
        
        if ($isReply) {
            $md += "### 💬 $dateStr - $timeStr **[ANTWORT]**"
        } else {
            $md += "### 🦋 $dateStr - $timeStr"
        }
        $md += ""
        
        # Post-Text
        if ($post.record.text) {
            $md += $post.record.text -replace ">", "\>" -replace "<", "\<"
        } else {
            $md += "*(Kein Text)*"
        }
        
        # Bilder einbetten
        if ($imageMap.ContainsKey($post.uri)) {
            $md += ""
            foreach ($img in $imageMap[$post.uri]) {
                #$altText = if ($img.Alt) { $img.Alt } else { "Bild" }
                $md += "![|600]($($img.Path))"
            }
        }
        
        # Reply-Info
        if ($isReply -and $post.record.reply.parent) {
            $md += ""
            $md += "> 💬 *Antwort auf einen anderen Post*"
        }
        
        # Statistiken
        $stats = @()
        if ($post.likeCount -gt 0) { $stats += "❤️ $($post.likeCount)" }
        if ($post.repostCount -gt 0) { $stats += "🔄 $($post.repostCount)" }
        if ($post.replyCount -gt 0) { $stats += "💬 $($post.replyCount)" }
        
        if ($stats.Count -gt 0) {
            $md += ""
            $md += "*$($stats -join ' | ')*"
        }
        
        # Embed-Infos (für Bilder ohne Download)
        if ($post.embed -and -not $imageMap.ContainsKey($post.uri)) {
            $md += ""
            
            if ($post.embed.images) {
                $md += "**📷 Bilder:** $($post.embed.images.Count)"
                foreach ($img in $post.embed.images) {
                    if ($img.alt) {
                        $md += "- *$($img.alt)*"
                    }
                }
            }
            
            if ($post.embed.external) {
                $md += "**🔗 Link:** [$($post.embed.external.title)]($($post.embed.external.uri))"
            }
            
            if ($post.embed.'$type' -eq 'app.bsky.embed.video') {
                $md += "**🎥 Video**"
            }
        }
        
        # Bluesky-Link
        $uri = $post.uri -replace 'at://', ''
        $parts = $uri -split '/'
        if ($parts.Count -ge 3) {
            $rkey = $parts[-1]
            $blueskyUrl = "https://bsky.app/profile/$BlueskyHandle/post/$rkey"
            $md += ""
            $md += "🔗 [Auf Bluesky ansehen]($blueskyUrl)"
        }
        
        $md += ""
        $md += "---"
        $md += ""
        
    } catch {
        Write-Verbose "Post konnte nicht verarbeitet werden: $_"
    }
}

# ==== SPEICHERN ====
Write-Host "💾 Speichere Markdown..." -ForegroundColor $statusColor

$md -join "`n" | Out-File -FilePath $outputFile -Encoding UTF8

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor $successColor
Write-Host "║                    ✅ EXPORT ERFOLGREICH!                      ║" -ForegroundColor $successColor
Write-Host "╠════════════════════════════════════════════════════════════════╣" -ForegroundColor $successColor
Write-Host "║  📁 Datei: $($outputFile.PadRight(51)) ║" -ForegroundColor $successColor
Write-Host "║  📊 Posts: $($sortedPosts.Count.ToString().PadRight(51)) ║" -ForegroundColor $successColor
if ($DownloadImages) {
    Write-Host "║  📷 Bilder: $($imageCounter.ToString().PadRight(50)) ║" -ForegroundColor $successColor
}
Write-Host "║  📅 Zeitraum: $($FromDate.ToString('dd.MM.yyyy')) - $(Get-Date -Format 'dd.MM.yyyy')".PadRight(64) + " ║" -ForegroundColor $successColor
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor $successColor
Write-Host ""
Write-Host "👋 Fertig! " -ForegroundColor $subtextColor
