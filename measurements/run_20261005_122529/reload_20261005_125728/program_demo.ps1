[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Cable)
$ErrorActionPreference = 'Stop'
$toolDir = 'C:\intelFPGA_lite\20.1\quartus\bin64'
$sof = Join-Path $PSScriptRoot 'riscv_soc.sof'
$expected = '6c9d103d173a53ec0135bedd85e385543094c9ee7234e4837f6b3f996587b934'
if ((Get-FileHash -LiteralPath $sof -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'SOF checksum mismatch; use the artifact recorded in this run.'
}
$chain = & (Join-Path $toolDir 'jtagconfig.exe') 2>&1
$chain | Tee-Object -FilePath (Join-Path $PSScriptRoot 'jtag_before_program.log')
if ($LASTEXITCODE -ne 0 -or ($chain -join "`n") -notmatch '10M50') {
    throw 'Expected 10M50 was not detected. Check USB-Blaster, board power and cable.'
}
& (Join-Path $toolDir 'quartus_pgm.exe') -c $Cable -m JTAG -o ("p;" + $sof) 2>&1 | Tee-Object -FilePath (Join-Path $PSScriptRoot 'program.log')
if ($LASTEXITCODE -ne 0) { throw 'Programming failed; inspect program.log.' }
