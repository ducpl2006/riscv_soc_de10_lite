[CmdletBinding()]
param(
    [ValidateRange(1, 500)]
    [int]$Epochs = 150,
    [ValidateRange(1, 100)]
    [int]$TrainStride = 1,
    [switch]$Install
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# Chạy pipeline CALCE bằng Python hệ thống trong Ubuntu/WSL mặc định.
# Mặc định chỉ sinh artifact trong ml/artifacts. -Install chỉ cài model sau khi
# script Python đã hoàn tất mọi kiểm tra số học và ngưỡng chất lượng.
# =============================================================================

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'Thiếu WSL. Trong Ubuntu, chạy python3 ml/train_quantize_export.py theo README.'
}
$linuxRoot = & wsl.exe -- wslpath -a $repoRoot
if ($LASTEXITCODE -ne 0) { throw 'Không đổi được đường dẫn project sang WSL.' }
$linuxRoot = $linuxRoot.Trim()

$arguments = @(
    '--', 'python3', ($linuxRoot + '/ml/train_quantize_export.py'),
    '--repo-root', $linuxRoot,
    '--epochs', $Epochs.ToString([System.Globalization.CultureInfo]::InvariantCulture),
    '--train-stride', $TrainStride.ToString([System.Globalization.CultureInfo]::InvariantCulture),
    '--eval-stride', '1'
)
if ($Install) {
    $arguments += '--install'
}

& wsl.exe @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Pipeline ML thất bại với mã $LASTEXITCODE"
}
