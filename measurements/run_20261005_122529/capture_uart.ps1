[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PortName,[int]$Seconds=30)
$ErrorActionPreference='Stop'
if ($Seconds -lt 1 -or $Seconds -gt 60) { throw 'Seconds must be 1..60' }
if ($PortName -eq 'COM3') { throw 'COM3 was identified as Intel AMT SOL, not this board adapter.' }
$port=New-Object System.IO.Ports.SerialPort $PortName,115200,([System.IO.Ports.Parity]::None),8,([System.IO.Ports.StopBits]::One)
$port.Handshake=[System.IO.Ports.Handshake]::None
$port.DtrEnable=$false
$port.RtsEnable=$false
$port.ReadTimeout=200
$bytes=New-Object 'System.Collections.Generic.List[byte]'
try {
 $port.Open()
 Write-Host "UART capture started on $PortName at 115200 8N1. Press and release KEY[0] now."
 $timer=[System.Diagnostics.Stopwatch]::StartNew()
 while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
  try {
   $value=$port.ReadByte()
   if ($value -ge 0) { $bytes.Add([byte]$value) }
   if ($bytes.Count -ge 2 -and $bytes[$bytes.Count-2] -eq 0x4f -and $bytes[$bytes.Count-1] -eq 0x4b) { break }
  } catch [System.TimeoutException] { }
 }
} finally {
 if ($port.IsOpen) { $port.Close() }
 $port.Dispose()
}
[System.IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'uart_raw.bin'),$bytes.ToArray())
$hex=($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
$text=[System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'uart_capture.log'),"Port=$PortName; 115200 8N1; Bytes=$hex; Text=$text")
Write-Host "Bytes: $hex"
Write-Host "Text: $text"
if ($bytes.Count -ne 2 -or $bytes[0] -ne 0x4f -or $bytes[1] -ne 0x4b) { throw 'Expected exactly OK; inspect uart_raw.bin and wiring.' }
Write-Host 'PASS UART hardware: OK'
