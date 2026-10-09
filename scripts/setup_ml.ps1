[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Cài thư viện hệ thống trong Ubuntu/WSL mặc định, không tạo Python trong repo.
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'Thiếu WSL. Chạy lệnh apt trong terminal Ubuntu theo README.'
}
& wsl.exe -- sudo apt-get update
if ($LASTEXITCODE -ne 0) { throw 'apt-get update thất bại.' }
& wsl.exe -- sudo apt-get install -y --no-install-recommends python3-numpy python3-openpyxl iverilog
if ($LASTEXITCODE -ne 0) { throw 'Cài thư viện Ubuntu thất bại.' }
