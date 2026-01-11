<#
.SYNOPSIS
    Konvertiert Text in hexadezimale ASCII-Codes und zurück.

.DESCRIPTION
    Dieses Script kann Text in HEX-Codes umwandeln und HEX-Codes zurück in Text.

.PARAMETER Encode
    Konvertiert Text in HEX-Codes.

.PARAMETER Decode
    Konvertiert HEX-Codes zurück in Text.

.EXAMPLE
    .\Convert-TextToHex.ps1 -Encode
    
.EXAMPLE
    .\Convert-TextToHex.ps1 -Decode
#>

[CmdletBinding(DefaultParameterSetName='Encode')]
param(
    [Parameter(ParameterSetName='Encode')]
    [switch]$Encode,
    
    [Parameter(ParameterSetName='Decode')]
    [switch]$Decode
)

# Standardmäßig Encode, wenn nichts angegeben
if (-not $Encode -and -not $Decode) {
    $Encode = $true
}

if ($Encode) {
    # Text in HEX konvertieren
    $text = Read-Host "Bitte gib den Text ein, der in HEX umgewandelt werden soll"
    
    if ([string]::IsNullOrEmpty($text)) {
        Write-Host "Kein Text eingegeben. Script wird beendet." -ForegroundColor Yellow
        exit
    }
    
    Write-Host "`nOriginaltext: $text" -ForegroundColor Cyan
    Write-Host "`nHEX-Codes:" -ForegroundColor Green
    
    # Jeden Buchstaben durchgehen und als HEX ausgeben
    foreach ($char in $text.ToCharArray()) {
        $asciiValue = [int][char]$char
        $hexValue = "{0:X2}" -f $asciiValue
        Write-Host "  '$char' => 0x$hexValue (Dez: $asciiValue)"
    }
    
    # Kompakte Ausgabe (alle HEX-Codes in einer Zeile)
    Write-Host "`nKompakt:" -ForegroundColor Green
    $hexString = ($text.ToCharArray() | ForEach-Object { "{0:X2}" -f [int][char]$_ }) -join ' '
    Write-Host "  $hexString"
}
elseif ($Decode) {
    # HEX in Text konvertieren
    $hexInput = Read-Host "Bitte gib die HEX-Codes ein (mit oder ohne Leerzeichen, z.B. '41 42' oder '4142')"
    
    if ([string]::IsNullOrEmpty($hexInput)) {
        Write-Host "Keine HEX-Codes eingegeben. Script wird beendet." -ForegroundColor Yellow
        exit
    }
    
    try {
        # Leerzeichen und 0x-Präfixe entfernen
        $hexClean = $hexInput -replace '\s+', '' -replace '0x', ''
        
        # Prüfen, ob die Länge gerade ist (jedes Zeichen = 2 HEX-Stellen)
        if ($hexClean.Length % 2 -ne 0) {
            Write-Host "Fehler: Ungerade Anzahl von HEX-Zeichen. Jedes Zeichen benötigt 2 HEX-Stellen." -ForegroundColor Red
            exit
        }
        
        Write-Host "`nHEX-Input: $hexInput" -ForegroundColor Cyan
        Write-Host "`nDekodierung:" -ForegroundColor Green
        
        $decodedText = ""
        
        # Jeweils 2 HEX-Zeichen als ein Byte interpretieren
        for ($i = 0; $i -lt $hexClean.Length; $i += 2) {
            $hexByte = $hexClean.Substring($i, 2)
            $decValue = [Convert]::ToInt32($hexByte, 16)
            $char = [char]$decValue
            $decodedText += $char
            Write-Host "  0x$hexByte (Dez: $decValue) => '$char'"
        }
        
        Write-Host "`nDekodierter Text:" -ForegroundColor Green
        Write-Host "  $decodedText" -ForegroundColor White
    }
    catch {
        Write-Host "Fehler beim Dekodieren: $_" -ForegroundColor Red
        Write-Host "Bitte stelle sicher, dass nur gültige HEX-Zeichen (0-9, A-F) eingegeben wurden." -ForegroundColor Yellow
    }
}