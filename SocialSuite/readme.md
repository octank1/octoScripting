# octoScripting

PowerShell-basierte Tools

## [Social Suite](./SocialSuite/)
PowerShell-basierte Social Media Automation für Bluesky & Discord

### Bluesky Tools
- **Post Editor PRO** - Erstellen von Bluesky-Chats in einer Windows-GUI mit Formatierung und Entwürfen
- **Chat Client** - Interaktiver Console-Chat
- **Bluesky Client** - Einfacher Client um Posts und Benachrichtigungen zu lesen (Beta)
- **Chat Monitor** - Live-Benachrichtigungen über eingegangene Nachrichten
- **Chat Export** - Markdown-Export für Obsidian inkl. Download geposteter Bilder, mit oder ohne Antworten

### Discord Tools
- **Chat Client** - Chatten in DMs & Server für die Konsole
- **Chat Export** - Export eines Chats als Markdown mit Attachments, Parameter werden interaktiv abgefragt 
- **Token update** - Kleiner Helfer zum Speichern des aktuellen Tokens

## Control Center
- **Zentrales Tool-Menü** mit Live-Notification-Bar
- **Auto-Refresh** alle 30 Sekunden


# 1. Installation

1. PowerShell 7+ installieren (winget install powershell)
2. **Clone repository:**
   ```bash
   git clone https://github.com/octank1/octoScripting.git
   cd octoScripting
   ```
3. **Choose your suite:**
   ```powershell
   cd SocialSuite
   .\socialmedia-suite.ps1
   ```

# 2. Konfiguration

## Config-Dateien:

```
config/
├── config.json              ← Einstellungen (Handle, Pfade)
├── config.template.json     ← Template für neue Setups
└── secrets.encrypted        ← Passwörter (DPAPI-verschlüsselt)
```
## Secrets verwalten:

```powershell
# Config-Manager laden
Import-Module .\lib\config-manager.ps1

# Interaktives Setup
Start-ConfigSetup

# Bluesky setzen
Set-Secret -Key "bluesky.appPassword" -Value "test-password-123" -Verbose

# Discord setzen
Set-Secret -Key "discord.userToken" -Value "discord-token-xyz" -Verbose

# Als Einzeiler
Import-Module .\lib\config-mgr.psm1; Set-Secret -Key "discord.userToken" -Value "NEUER_TOKEN"

# Beide abrufen
Write-Host "`nBluesky: $(Get-Secret -Key 'bluesky.appPassword')"
Write-Host "Discord: $(Get-Secret -Key 'discord.userToken')"

```

Das Setup fragt nach:
- **Bluesky Handle** (z.B. `deinname.bsky.social`)
- **Bluesky App-Password** (erstellen auf [bsky.app/settings/app-passwords](https://bsky.app/settings/app-passwords))
- **Discord Token** (optional - siehe [Discord Setup](#discord-setup))

Secrets werden **verschlüsselt** in `config/secrets.encrypted` gespeichert!

## Discord Setup

1. **Discord im Browser öffnen** (Chrome/Edge empfohlen)
2. **F12 drücken** → Tab **"Console"**
3. **Code eingeben:**
   ```javascript
   (webpackChunkdiscord_app.push([[''],{},e=>{m=[];for(let c in e.c)m.push(e.c[c])}]),m).find(m=>m?.exports?.default?.getToken!==void 0).exports.default.getToken()
   ```
4. **Token kopieren**

# Sicherheit

## DPAPI-Verschlüsselung:
- Passwörter/Tokens werden mit **Windows DPAPI** verschlüsselt
- **Nur dein User-Account** auf **deinem PC** kann entschlüsseln
- Kein Klartext auf Festplatte

# Verwendung

```powershell
# Control Center starten
.\socialmedia-suite.ps1

# Oder einzelnes Tool
.\bsky-chat.ps1
.\bsky-post-pro.ps1
.\bsky-chat-monitor.ps1
.\bsky-chat-export.ps1
.\bsky-client.ps1
.\discord-chat.ps1
.\discord-export.ps1
.\discord-token-update.ps1
```

# API-Limits

## Bluesky:
- **Posts abrufen:** 100 pro Request, ~3000 Requests/5 Min
- **Chat-Nachrichten:** 1000 Zeichen (Script teilt automatisch)
- **Rate Limit:** Großzügig, kaum Probleme

## Discord:
- **Nachrichten:** Keine strikte Grenze für User-Tokens
- **API-Calls:** Moderate Rate Limits
- **Tokens:** Laufen bei Browser-Neustart ab

---

# Troubleshooting

## "Config nicht gefunden"
```powershell
Import-Module .\lib\config-mgr.psm1
Start-ConfigSetup
```

## "Bluesky Login fehlgeschlagen"
- App-Password korrekt?
- Handle richtig? (`handle.bsky.social` OHNE `@`)

## "Discord 401 Unauthorized"
- Token abgelaufen → neu setzen:
  ```powershell
  .\discord-token-update.ps1
  ```

## "Secret nicht gefunden"
```powershell
Import-Module .\lib\config-mgr.psm1
Set-Secret -Key "bluesky.appPassword" -Value "DEIN_PASSWORD"
```

---

# Lizenz

MIT License - siehe [LICENSE](LICENSE)

# Credits

- **Author:** [Wolli White](https://bsky.app/profile/wolliwhite.de)
- **AI Assistant:** GitHub Copilot (Claude Sonnet 4.5)
- **Inspiration:** Die Notwendigkeit, Social Media effizienter zu nutzen

---

**Made with ❤️ and a lot of ☕ by Wolli White**

# Buy me a coffee
Falls ich Dich mit den Scripten inspiriert habe oder du sie sogar einsetzt, würde ich mich über [einen Kaffee freuen](https://buymeacoffee.com/octank) freuen.
