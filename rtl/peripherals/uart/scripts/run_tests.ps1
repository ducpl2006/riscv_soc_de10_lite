[CmdletBinding()]
param(
    [string]$ModelSimBin = $env:MODELSIM_BIN,
    [switch]$KeepBuild
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..')
)

function Find-ModelSimBin {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        $resolved = [System.IO.Path]::GetFullPath($RequestedPath)
        if (Test-Path -LiteralPath (Join-Path $resolved 'vlog.exe')) {
            return $resolved
        }
        throw "vlog.exe was not found in ModelSimBin: $resolved"
    }

    $vlogCommand = Get-Command vlog.exe -ErrorAction SilentlyContinue
    if ($vlogCommand) {
        return Split-Path -Parent $vlogCommand.Source
    }

    $searchRoots = @(
        'C:\intelFPGA_lite',
        'C:\intelFPGA',
        'C:\altera'
    )

    foreach ($searchRoot in $searchRoots) {
        if (-not (Test-Path -LiteralPath $searchRoot)) {
            continue
        }

        $candidate = Get-ChildItem -LiteralPath $searchRoot `
            -Filter 'vlog.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($candidate) {
            return $candidate.Directory.FullName
        }
    }

    throw @'
ModelSim/Questa was not found. Add its bin directory to PATH or run:
  .\scripts\run_tests.ps1 -ModelSimBin C:\path\to\modelsim\win32aloem
'@
}

function Invoke-CheckedTool {
    param(
        [string]$Executable,
        [string[]]$Arguments
    )

    $output = & $Executable @Arguments 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    Write-Host $output

    if ($exitCode -ne 0) {
        throw "Command failed with exit code ${exitCode}: $Executable"
    }

    return $output
}

$ModelSimBin = Find-ModelSimBin -RequestedPath $ModelSimBin
$vlib = Join-Path $ModelSimBin 'vlib.exe'
$vlog = Join-Path $ModelSimBin 'vlog.exe'
$vsim = Join-Path $ModelSimBin 'vsim.exe'

foreach ($tool in @($vlib, $vlog, $vsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Required simulator tool was not found: $tool"
    }
}

$buildRoot = Join-Path $ProjectRoot 'build'
$buildDir = Join-Path $buildRoot 'modelsim'

if (-not $buildDir.StartsWith($ProjectRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use a build directory outside the project: $buildDir"
}

if ((Test-Path -LiteralPath $buildDir) -and (-not $KeepBuild)) {
    Remove-Item -LiteralPath $buildDir -Recurse -Force
}

New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

$sources = @(
    'rtl\reset_sync.v',
    'rtl\uart_rx_sync.v',
    'rtl\uart_baud_gen.v',
    'rtl\sync_fifo.v',
    'rtl\uart_tx.v',
    'rtl\uart_rx.v',
    'rtl\uart_top.v',
    'rtl\uart_loopback_top.v',
    'tb\tb_uart_baud_gen.v',
    'tb\tb_sync_fifo.v',
    'tb\tb_uart_tx.v',
    'tb\tb_uart_rx.v',
    'tb\tb_uart_top.v',
    'tb\tb_uart_loopback.v'
) | ForEach-Object { Join-Path $ProjectRoot $_ }

$testbenches = @(
    'tb_uart_baud_gen',
    'tb_sync_fifo',
    'tb_uart_tx',
    'tb_uart_rx',
    'tb_uart_top',
    'tb_uart_loopback_top'
)

Push-Location $buildDir
try {
    Invoke-CheckedTool -Executable $vlib -Arguments @('work') | Out-Null

    $compileArguments = @('-lint', '-pedanticerrors', '-work', 'work') + $sources
    Invoke-CheckedTool -Executable $vlog -Arguments $compileArguments | Out-Null

    $failedTests = @()

    foreach ($testbench in $testbenches) {
        Write-Host "=== Running $testbench ==="
        # Marker PASS/FAIL là kết quả chính thức vì nhiều simulator Verilog trả
        # mã tiến trình 0 cho cả hai nhánh của lệnh $finish trong testbench.
        $doCommand = 'run -all; quit -code 0 -f'
        $arguments = @(
            '-c',
            '-quiet',
            '-lib', 'work',
            $testbench,
            '-do', $doCommand
        )

        try {
            $simulationOutput = Invoke-CheckedTool `
                -Executable $vsim `
                -Arguments $arguments
        } catch {
            Write-Host $_
            $failedTests += $testbench
            continue
        }

        $passMarker = "TEST_RESULT: PASS: $testbench"
        if (
            (-not $simulationOutput.Contains($passMarker)) -or
            $simulationOutput.Contains('TEST_RESULT: FAIL:')
        ) {
            Write-Host "Missing PASS marker or FAIL marker detected: $testbench"
            $failedTests += $testbench
        }
    }

    if ($failedTests.Count -ne 0) {
        Write-Host "FAILED TESTS: $($failedTests -join ', ')"
        exit 1
    }

    Write-Host "ALL TESTS PASSED ($($testbenches.Count)/$($testbenches.Count))"
} finally {
    Pop-Location
}
