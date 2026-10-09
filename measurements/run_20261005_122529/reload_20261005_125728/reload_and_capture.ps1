$ErrorActionPreference='Stop'
$port=$null
$opened=$false
$programmed=$false
$bytes=New-Object 'System.Collections.Generic.List[byte]'
try {
 try {
  $port=New-Object System.IO.Ports.SerialPort 'COM7',115200,([System.IO.Ports.Parity]::None),8,([System.IO.Ports.StopBits]::One)
  $port.Handshake=[System.IO.Ports.Handshake]::None
  $port.DtrEnable=$false
  $port.RtsEnable=$false
  $port.ReadTimeout=200
  $port.Open()
  $port.DiscardInBuffer()
  $opened=$true
  Write-Host 'COM7 opened at 115200 8N1 before FPGA configuration.'
 } catch {
  Write-Host ('UART unavailable: '+$_.Exception.Message)
 }
 & (Join-Path $PSScriptRoot 'program_demo.ps1') -Cable 'USB-Blaster [USB-0]'
 $programmed=$true
 if ($opened) {
  $timer=[System.Diagnostics.Stopwatch]::StartNew()
  while ($timer.Elapsed.TotalSeconds -lt 5) {
   try {
    $value=$port.ReadByte()
    if ($value -ge 0) { $bytes.Add([byte]$value) }
    if ($bytes.Count -ge 2 -and $bytes[$bytes.Count-2] -eq 0x4f -and $bytes[$bytes.Count-1] -eq 0x4b) { break }
   } catch [System.TimeoutException] { }
  }
 }
} finally {
 if ($null -ne $port) {
  if ($port.IsOpen) { $port.Close() }
  $port.Dispose()
 }
 [System.IO.File]::WriteAllBytes((Join-Path $PSScriptRoot 'uart_raw.bin'),$bytes.ToArray())
 $hex=($bytes | ForEach-Object { $_.ToString('X2') }) -join ' '
 $uartPassed=$opened -and $bytes.Count -eq 2 -and $bytes[0] -eq 0x4f -and $bytes[1] -eq 0x4b
 $status=[ordered]@{programming_succeeded=$programmed;uart_opened=$opened;port='COM7';baud=115200;uart_hex=$hex;uart_pass=$uartPassed}
 $status | ConvertTo-Json | Out-File -LiteralPath (Join-Path $PSScriptRoot 'reload_results.json') -Encoding utf8
 Write-Host ('Programming succeeded: '+$programmed)
 Write-Host ('UART bytes: '+$hex)
 Write-Host ('UART PASS: '+$uartPassed)
}
