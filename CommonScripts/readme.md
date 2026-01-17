# octoScripting

PowerShell-basierte Tools

## Common Scripts

### Hex De/Encoder

Kleines interaktives Powershell-Script, um einen Text in HEX-ASCII-Codes oder HEX-Codes in Text zu verwandeln. 

#### Text codieren (in 10-er Blöcken)
`hex-encoder -encode -padlines`

#### HEX decodieren
`hex-encoder -decode`

### HaveIbeenpawned API

Powershell-Script zur Prüfung, ob Passwörtern geleaked wurden. Dazu wird ein Passwort abgefragt oder es kann eine Text-Datei mit Passwörtern übergeben werden. Das Ergebnis kann als CSV exportiert werden.

#### Aufruf des Scripts

`pwnd-api -PasswordFile "dateiname.txt" -ExportCSV`

### Winget-Update

Powershell-Script, das über winget eine Liste der zu aktualisierenden Programme anzeigt, die dann einzeln über eine Auswahl aktualisiert werden können.
Falls eine Konsole mit erhöhten Rechten zum Update notwendig ist, wird diese automatisch gestartet.

#### Aufruf des Scripts

`winget-updates.ps1`

### Verzeichnisstruktur erstellen

Powershell-Script, mit dem man eine immer gleichartige Verzeichnisstruktur für ein Jahr anlegen kann. Falls man Daten, z.B. für die Fibu oder Krankenkassenbelege etc. in einer Struktur

- Jahr
    - Person 1
        - Belegart 1
        - Belegart 2
    - Person 2
        - Belegart 1
        - Belegart 2

oder ähnlich strukturiert hat, erzeugt dieses Script den kompletten Jahresordner oder alle fehlenden Ordner innerhalb eines Jahresorders.

#### Aufruf des Scripts

`create-folderstructure.ps1 -Year 2026`

---

## Lizenz

MIT License - siehe [LICENSE](LICENSE)

## Credits

- **Author:** [Wolli White](https://bsky.app/profile/wolliwhite.de)
- **AI Assistant:** GitHub Copilot (Claude Sonnet 4.5)
- **Inspiration:** Die Notwendigkeit, Social Media effizienter zu nutzen

---

**Made with ❤️ and a lot of ☕ by Wolli White**

## Buy me a coffee
Falls ich Dich mit den Scripten inspiriert habe oder du sie sogar einsetzt, würde ich mich über [einen Kaffee freuen](https://buymeacoffee.com/octank) freuen.
