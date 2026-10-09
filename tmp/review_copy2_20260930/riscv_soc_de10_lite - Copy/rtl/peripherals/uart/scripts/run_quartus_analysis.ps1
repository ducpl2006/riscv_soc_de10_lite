[CmdletBinding()]
param(
    [string]$QuartusBin = $env:QUARTUS_BIN
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$quartusProjectDir = Join-Path $projectRoot 'quartus'

function Find-QuartusMap {
    param([string]$RequestedBin)

    if ($RequestedBin) {
        $candidate = Join-Path ([System.IO.Path]::GetFullPath($RequestedBin)) 'quartus_map.exe'
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
        throw "quartus_map.exe was not found in QuartusBin: $RequestedBin"
    }

    $command = Get-Command quartus_map.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    foreach ($searchRoot in @('C:\intelFPGA_lite', 'C:\intelFPGA', 'C:\altera')) {
        if (-not (Test-Path -LiteralPath $searchRoot)) {
            continue
        }

        $candidate = Get-ChildItem -LiteralPath $searchRoot `
            -Filter 'quartus_map.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw @'
Quartus was not found. Add quartus_map.exe to PATH or run:
  .\scripts\run_quartus_analysis.ps1 -QuartusBin C:\path\to\quartus\bin64
'@
}

$quartusMap = Find-QuartusMap -RequestedBin $QuartusBin

Push-Location $quartusProjectDir
try {
    & $quartusMap `
        '--read_settings_files=on' `
        '--write_settings_files=off' `
        'uart_loopback' `
        '-c' `
        'uart_loopback'

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}

