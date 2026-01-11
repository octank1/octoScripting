<#
.SYNOPSIS
    Discord Token schnell aktualisieren
.EXAMPLE
    .\update-discord-token.ps1
#>

Import-Module (Join-Path $PSScriptRoot "lib\config-mgr.psm1") -Force

Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║         💬 DISCORD TOKEN UPDATE - by Wolli White 💬           ║" -ForegroundColor Magenta
Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

Write-Host "📖 So holst du den Token:" -ForegroundColor Cyan
Write-Host "  1. Discord im Browser öffnen (Chrome/Edge)" -ForegroundColor Gray
Write-Host "  2. F12 drücken → Tab 'Console'" -ForegroundColor Gray
Write-Host "  3. Folgenden Code eingeben:`n" -ForegroundColor Gray
Write-Host "     (webpackChunkdiscord_app.push([[''],{},e=>{m=[];for(let c in e.c)m.push(e.c[c])}]),m).find(m=>m?.exports?.default?.getToken!==void 0).exports.default.getToken()" -ForegroundColor White
Write-Host ""

# Aktuellen Token anzeigen (erste/letzte 10 Zeichen)
$currentToken = Get-Secret -Key "discord.userToken"
if ($currentToken) {
    $masked = $currentToken.Substring(0, [Math]::Min(10, $currentToken.Length)) + "..." + $currentToken.Substring([Math]::Max(0, $currentToken.Length - 10))
    Write-Host "🔑 Aktueller Token: $masked" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "💬 Neuen Discord-Token eingeben (oder Enter zum Abbrechen):" -ForegroundColor Cyan
$newToken = Read-Host "Token"

if ([string]::IsNullOrWhiteSpace($newToken)) {
    Write-Host "`n❌ Abgebrochen." -ForegroundColor Red
    exit
}

# Token validieren (grobe Prüfung)
if ($newToken.Length -lt 50) {
    Write-Host "`n⚠️ Token scheint zu kurz zu sein. Sicher dass das korrekt ist?" -ForegroundColor Yellow
    $confirm = Read-Host "Trotzdem speichern? (j/n)"
    if ($confirm -ne "j") {
        Write-Host "❌ Abgebrochen." -ForegroundColor Red
        exit
    }
}

# Speichern
Set-Secret -Key "discord.userToken" -Value $newToken

# Testen
Write-Host "`n🔍 Teste Token..." -ForegroundColor Cyan

try {
    $headers = @{
        "Authorization" = $newToken
        "Content-Type" = "application/json"
    }
    
    $user = Invoke-RestMethod -Uri "https://discord.com/api/v10/users/@me" `
        -Headers $headers -Method GET -TimeoutSec 5
    
    Write-Host "✅ Token ist gültig!" -ForegroundColor Green
    Write-Host "   Eingeloggt als: $($user.username)#$($user.discriminator)" -ForegroundColor Cyan
    
} catch {
    Write-Host "⚠️ Token-Test fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "   Token wurde trotzdem gespeichert." -ForegroundColor Gray
}

Write-Host "`n🎉 Fertig! Discord-Token aktualisiert." -ForegroundColor Green
Write-Host ""