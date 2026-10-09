[CmdletBinding()]
param(
    [string]$Prefix = 'riscv32-unknown-elf-',
    [ValidateRange(1, 8192)]
    [int]$RomWords = 8192,
    [string[]]$Define = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# Build firmware bare-metal RV32I và sinh ảnh ROM dùng chung cho mô phỏng/Quartus.
# Script không tự tải toolchain. Có thể đổi -Prefix thành riscv64-unknown-elf-
# nếu bộ compiler đó hỗ trợ multilib rv32i/ilp32.
# =============================================================================

function Resolve-Tool {
    param([string]$Name)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        throw "Không tìm thấy '$Name' trên PATH. Hãy cài GNU RISC-V embedded toolchain hoặc truyền -Prefix phù hợp."
    }
    return $command.Source
}

function Invoke-Checked {
    param([string]$FilePath, [string[]]$ArgumentList)
    Write-Host ('> {0} {1}' -f [IO.Path]::GetFileName($FilePath), ($ArgumentList -join ' '))
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Lệnh $([IO.Path]::GetFileName($FilePath)) thất bại với mã $LASTEXITCODE."
    }
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$firmwareRoot = Join-Path $repoRoot 'firmware'
$buildRoot = Join-Path $firmwareRoot 'build'
$gcc = Resolve-Tool ($Prefix + 'gcc')
$objcopy = Resolve-Tool ($Prefix + 'objcopy')
$objdump = Resolve-Tool ($Prefix + 'objdump')

if (-not (Test-Path -LiteralPath $buildRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $buildRoot | Out-Null
}

$elfPath = Join-Path $buildRoot 'boot.elf'
$binPath = Join-Path $buildRoot 'boot.bin'
$mapPath = Join-Path $buildRoot 'boot.map'
$dumpPath = Join-Path $buildRoot 'boot.disasm'
$hexPath = Join-Path $buildRoot 'boot.hex'
$mifPath = Join-Path $buildRoot 'boot.mif'

$commonFlags = @(
    '-march=rv32i', '-mabi=ilp32', '-mcmodel=medany',
    '-Os', '-ffreestanding', '-fno-builtin', '-fno-common',
    '-ffunction-sections', '-fdata-sections',
    '-Wall', '-Wextra', '-Werror'
    '-msmall-data-limit=0', '-mno-relax'
)
$linkFlags = @(
    '-nostartfiles', '-nostdlib',
    ('-Wl,-T,' + (Join-Path $firmwareRoot 'linker.ld')),
    ('-Wl,-Map,' + $mapPath), '-Wl,--gc-sections', '-Wl,--no-relax'
)

Invoke-Checked $gcc ($commonFlags + $linkFlags + @($Define | ForEach-Object { '-D' + $_ }) + @(
    (Join-Path $firmwareRoot 'start.S'),
    (Join-Path $firmwareRoot 'main.c'),
    (Join-Path $firmwareRoot 'sample_pipeline.c'),
    (Join-Path $firmwareRoot 'soc_platform.c'),
    (Join-Path $firmwareRoot 'ina228.c'),
    (Join-Path $firmwareRoot 'runtime.c'),
    '-lgcc', '-o', $elfPath
))
Invoke-Checked $objcopy @('-O', 'binary', $elfPath, $binPath)

$disassembly = & $objdump '-d' '-S' $elfPath
if ($LASTEXITCODE -ne 0) { throw 'objdump thất bại.' }
[IO.File]::WriteAllLines($dumpPath, [string[]]$disassembly,
    [Text.UTF8Encoding]::new($false))

$bytes = [IO.File]::ReadAllBytes($binPath)
$capacityBytes = $RomWords * 4
if ($bytes.Length -gt $capacityBytes) {
    throw "Firmware dài $($bytes.Length) byte, vượt ROM $capacityBytes byte."
}

$wordCount = [Math]::Ceiling($bytes.Length / 4.0)
$hexLines = New-Object 'System.Collections.Generic.List[string]'
$mifLines = New-Object 'System.Collections.Generic.List[string]'
$mifLines.Add("DEPTH = $RomWords;")
$mifLines.Add('WIDTH = 32;')
$mifLines.Add('ADDRESS_RADIX = HEX;')
$mifLines.Add('DATA_RADIX = HEX;')
$mifLines.Add('CONTENT BEGIN')

for ($wordIndex = 0; $wordIndex -lt $wordCount; ++$wordIndex) {
    [uint32]$word = 0
    for ($lane = 0; $lane -lt 4; ++$lane) {
        $byteIndex = 4 * $wordIndex + $lane
        if ($byteIndex -lt $bytes.Length) {
            $word = $word -bor ([uint32]$bytes[$byteIndex] -shl (8 * $lane))
        }
    }
    $hexWord = '{0:X8}' -f $word
    $hexLines.Add($hexWord)
    $mifLines.Add(('    {0:X4} : {1};' -f $wordIndex, $hexWord))
}

if ($wordCount -lt $RomWords) {
    $mifLines.Add(('    [{0:X4}..{1:X4}] : 00000013;' -f $wordCount, ($RomWords - 1)))
}
$mifLines.Add('END;')

$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllLines($hexPath, $hexLines, $utf8NoBom)
[IO.File]::WriteAllLines($mifPath, $mifLines, $utf8NoBom)

Write-Host ("Firmware OK: {0} byte, {1}/{2} word ROM." -f $bytes.Length, $wordCount, $RomWords) -ForegroundColor Green
Write-Host ('ELF : ' + $elfPath)
Write-Host ('HEX : ' + $hexPath)
Write-Host ('MIF : ' + $mifPath)
