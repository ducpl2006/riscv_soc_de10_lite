[CmdletBinding()]
param(
    [ValidateSet('Base', 'All')]
    [string]$Scope = 'All',
    # Stress core, bộ chia UART, độ sâu FIFO và I2C có/không đồng bộ đầu vào.
    [switch]$Stress
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# Regression RTL RV32I dùng ModelSim/Questa ở chế độ command line.
#
# Đặc tính chính:
#   - Tự suy ra repo root từ vị trí script, không phụ thuộc thư mục hiện hành.
#   - Tìm bộ công cụ trên PATH trước, sau đó thử IntelFPGA 20.1 mặc định.
#   - Chỉ xóa và tạo lại đúng sim/modelsim/work sau khi kiểm tra đường dẫn.
#   - Lấy RTL từ QSF SoC, không trộn các project độc lập nằm dưới rtl/.
#   - Tự khám phá mọi tb_rv32_*.v/.sv và chạy từng top trong tiến trình riêng.
#   - Fail-fast khi tool/compile/simulation lỗi; vẫn in bảng tổng kết cuối cùng.
# =============================================================================

function Add-UniqueDirectory {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    foreach ($existingPath in $List) {
        if ([System.StringComparer]::OrdinalIgnoreCase.Equals(
                $existingPath,
                $fullPath
            )) {
            return
        }
    }

    $List.Add($fullPath)
}

function Resolve-Executable {
    param(
        [string]$Name,
        [string[]]$CandidateDirectories
    )

    $pathCommand = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $pathCommand) {
        return $pathCommand.Source
    }

    foreach ($directory in $CandidateDirectories) {
        foreach ($fileName in @($Name + '.exe', $Name)) {
            $candidate = Join-Path $directory $fileName
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return [System.IO.Path]::GetFullPath($candidate)
            }
        }
    }

    throw "Không tìm thấy '$Name'. Hãy thêm ModelSim/Questa vào PATH."
}

function Invoke-LoggedProcess {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList
    )

    $displayArguments = foreach ($argument in $ArgumentList) {
        if ($argument -match '\s') {
            '"' + $argument + '"'
        }
        else {
            $argument
        }
    }

    Write-Host ('> {0} {1}' -f (
            [System.IO.Path]::GetFileName($FilePath)
        ), ($displayArguments -join ' ')) -ForegroundColor DarkGray

    $rawOutput = @(& $FilePath @ArgumentList 2>&1)
    $exitCode = $LASTEXITCODE
    $outputLines = @(
        $rawOutput | ForEach-Object {
            $_.ToString()
        }
    )

    foreach ($line in $outputLines) {
        Write-Host $line
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = $outputLines -join [System.Environment]::NewLine
    }
}

function Write-Utf8Log {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8WithoutBom)
}

function Reset-SafeWorkDirectory {
    param(
        [string]$SimulationDirectory,
        [string]$WorkDirectory
    )

    $simulationFullPath = [System.IO.Path]::GetFullPath(
        $SimulationDirectory
    ).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $workFullPath = [System.IO.Path]::GetFullPath(
        $WorkDirectory
    ).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $workParent = [System.IO.Path]::GetDirectoryName($workFullPath)
    $workLeaf = [System.IO.Path]::GetFileName($workFullPath)

    $parentIsExpected = [System.StringComparer]::OrdinalIgnoreCase.Equals(
        $workParent,
        $simulationFullPath
    )
    $leafIsExpected = [System.StringComparer]::OrdinalIgnoreCase.Equals(
        $workLeaf,
        'work'
    )

    if (-not $parentIsExpected -or -not $leafIsExpected) {
        throw "Từ chối dọn đường dẫn work không hợp lệ: $workFullPath"
    }

    if (Test-Path -LiteralPath $workFullPath) {
        Remove-Item -LiteralPath $workFullPath -Recurse -Force
    }

    New-Item -ItemType Directory -Path $workFullPath | Out-Null
    return $workFullPath
}

function Get-RtlPriority {
    param(
        [System.IO.FileInfo]$File,
        [hashtable]$PriorityByName
    )

    if ($File.BaseName -match '(?i)(package|pkg)$') {
        return -100
    }

    if ($PriorityByName.ContainsKey($File.Name)) {
        return $PriorityByName[$File.Name]
    }

    return 500
}

function Write-RegressionSummary {
    param(
        [object[]]$Results,
        [bool]$Succeeded,
        [string]$FailureReason
    )

    Write-Host ''
    Write-Host '================ REGRESSION SUMMARY ================'

    if ($Results.Count -eq 0) {
        Write-Host 'Chưa có testbench nào hoàn tất.'
    }
    else {
        foreach ($result in $Results) {
            $summaryLine = '{0,-32} {1,-6} {2,8:N3} s' -f $result.Name, $result.Status, $result.Seconds
            Write-Host $summaryLine
        }
    }

    if ($Succeeded) {
        $passSummary = 'RESULT: PASS ({0}/{0} test runs)' -f $Results.Count
        Write-Host $passSummary -ForegroundColor Green
    }
    else {
        Write-Host ('RESULT: FAIL - ' + $FailureReason) -ForegroundColor Red
    }

    Write-Host '===================================================='
}

$repoRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..')
)
$rtlRoot = Join-Path $repoRoot 'rtl'
$rtlCore = Join-Path $rtlRoot 'core'
$rtlBus = Join-Path $rtlRoot 'bus'
$rtlAccelerator = Join-Path $rtlRoot 'accelerator'
$testbenchRoot = Join-Path $repoRoot 'tb'
$simulationRoot = Join-Path $repoRoot 'sim\modelsim'
$workRoot = Join-Path $simulationRoot 'work'

$testResults = @()
$regressionSucceeded = $false
$failureReason = 'Lỗi chưa xác định.'
$locationPushed = $false

try {
    foreach ($requiredDirectory in @($rtlRoot, $rtlCore, $rtlAccelerator, $testbenchRoot)) {
        if (-not (Test-Path -LiteralPath $requiredDirectory -PathType Container)) {
            throw "Thiếu thư mục bắt buộc: $requiredDirectory"
        }
    }

    if (-not (Test-Path -LiteralPath $simulationRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $simulationRoot -Force | Out-Null
    }

    $toolDirectories = New-Object 'System.Collections.Generic.List[string]'

    foreach ($environmentDirectory in @(
            $env:MODELSIM_HOME,
            $env:QUESTA_HOME
        )) {
        Add-UniqueDirectory $toolDirectories $environmentDirectory
        if (-not [string]::IsNullOrWhiteSpace($environmentDirectory)) {
            $environmentBin = Join-Path $environmentDirectory 'bin'
            Add-UniqueDirectory -List $toolDirectories -Path $environmentBin
        }
    }

    foreach ($quartusRoot in @(
            $env:INTELFPGA_ROOTDIR,
            $env:QUARTUS_ROOTDIR
        )) {
        if (-not [string]::IsNullOrWhiteSpace($quartusRoot)) {
            $versionRoot = Split-Path ([System.IO.Path]::GetFullPath($quartusRoot)) -Parent
            $win64Directory = Join-Path $versionRoot 'modelsim_ase\win64aloem'
            $win32Directory = Join-Path $versionRoot 'modelsim_ase\win32aloem'
            Add-UniqueDirectory -List $toolDirectories -Path $win64Directory
            Add-UniqueDirectory -List $toolDirectories -Path $win32Directory
        }
    }

    $systemDrive = $env:SystemDrive
    if ([string]::IsNullOrWhiteSpace($systemDrive)) {
        $systemDrive = 'C:'
    }

    foreach ($relativeToolDirectory in @(
            'intelFPGA_lite\20.1\modelsim_ase\win64aloem',
            'intelFPGA_lite\20.1\modelsim_ase\win32aloem',
            'intelFPGA\20.1\modelsim_ase\win64aloem',
            'intelFPGA\20.1\modelsim_ase\win32aloem'
        )) {
        $defaultToolDirectory = Join-Path $systemDrive $relativeToolDirectory
        Add-UniqueDirectory -List $toolDirectories -Path $defaultToolDirectory
    }

    $vlogPath = Resolve-Executable 'vlog' $toolDirectories.ToArray()
    $vsimPath = Resolve-Executable 'vsim' $toolDirectories.ToArray()

    # Ưu tiên vlib/vmap nằm cạnh vlog để không trộn phiên bản ModelSim.
    $vlogDirectory = Split-Path $vlogPath -Parent
    $libraryToolDirectories = @($vlogDirectory) + $toolDirectories.ToArray()
    $vlibPath = Resolve-Executable 'vlib' $libraryToolDirectories
    $vmapPath = Resolve-Executable 'vmap' $libraryToolDirectories

    Write-Host ('Repo root : ' + $repoRoot)
    Write-Host ('ModelSim  : ' + (Split-Path $vlogPath -Parent))

    $workRoot = Reset-SafeWorkDirectory $simulationRoot $workRoot
    Push-Location $workRoot
    $locationPushed = $true

    $libraryResult = Invoke-LoggedProcess $vlibPath @('rtl_work')
    if ($libraryResult.ExitCode -ne 0) {
        throw "vlib thất bại với mã $($libraryResult.ExitCode)."
    }

    $mapResult = Invoke-LoggedProcess $vmapPath @('work', 'rtl_work')
    if ($mapResult.ExitCode -ne 0) {
        throw "vmap thất bại với mã $($mapResult.ExitCode)."
    }

    $projectPath = Join-Path $repoRoot 'quartus/riscv_soc.qsf'
    $projectDirectory = Split-Path -Parent $projectPath
    $rtlFiles = @(
        foreach ($line in Get-Content -LiteralPath $projectPath) {
            if ($line -match '^\s*set_global_assignment\s+-name\s+(?:VERILOG_FILE|SYSTEMVERILOG_FILE)\s+(.+?)\s*$') {
                $literal = $Matches[1]
                if ($literal -notmatch '^"([^"$\[\]]+)"$|^([^\s"${}\[\]]+)$') {
                    throw "Unsupported RTL path in QSF: $line"
                }
                $relativePath = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
                $source = Get-Item -LiteralPath (Join-Path $projectDirectory $relativePath)
                if ($source.PSIsContainer -or $source.Extension -notin @('.v', '.sv')) {
                    throw "Invalid RTL source: $($source.FullName)"
                }
                $source
            }
        }
    )
    if ($rtlFiles.Count -eq 0) {
        throw "Không tìm thấy RTL .v/.sv trong $projectPath"
    }
    if (@($rtlFiles | Group-Object FullName | Where-Object Count -gt 1).Count -ne 0) {
        throw 'Duplicate RTL source in QSF'
    }

    $priorityNames = @(
        'rv32_alu.v',
        'rv32_branch_unit.v',
        'rv32_decoder.v',
        'rv32_hazard_unit.v',
        'rv32_imm_gen.v',
        'rv32_lsu.v',
        'rv32_regfile.v',
        'rv32_core.v'
    )
    $priorityByName = @{}
    for ($index = 0; $index -lt $priorityNames.Count; $index++) {
        $priorityByName[$priorityNames[$index]] = $index * 10
    }

    $rtlFiles = @(
        $rtlFiles | Sort-Object -Property @(
            @{
                Expression = {
                    Get-RtlPriority $_ $priorityByName
                }
            },
            @{
                Expression = {
                    $_.FullName
                }
            }
        )
    )

    Write-Host ''
    $rtlCompileMessage = 'Compiling {0} RTL file(s)...' -f $rtlFiles.Count
    Write-Host $rtlCompileMessage -ForegroundColor Cyan
    foreach ($rtlFile in $rtlFiles) {
        $compileResult = Invoke-LoggedProcess $vlogPath @(
            '-sv',
            '-work',
            'rtl_work',
            ('+incdir+' + $rtlCore),
            ('+incdir+' + $rtlBus),
            ('+incdir+' + $rtlAccelerator),
            $rtlFile.FullName
        )
        $rtlLogPath = Join-Path $workRoot ('compile_' + $rtlFile.BaseName + '.log')
        Write-Utf8Log -Path $rtlLogPath -Content $compileResult.Output

        if ($compileResult.ExitCode -ne 0) {
            throw "Compile RTL thất bại tại $($rtlFile.FullName)."
        }
    }

    $testbenchFiles = @(
        Get-ChildItem -LiteralPath $testbenchRoot -Recurse -File |
            Where-Object {
                $_.Name -match '^tb_rv32_.*\.(v|sv)$'
            } |
            Sort-Object -Property Name, FullName
    )
    if ($Scope -eq 'Base') {
        $testbenchFiles = @($testbenchFiles | Where-Object {
            $_.FullName -notmatch '[\\/]accelerator[\\/]' -and $_.BaseName -ne 'tb_rv32_soc'
        })
    }
    if ($testbenchFiles.Count -eq 0) {
        throw "Không tìm thấy testbench tb_rv32_*.v/.sv trong $testbenchRoot"
    }

    $duplicateTops = @(
        $testbenchFiles |
            Group-Object -Property BaseName |
            Where-Object {
                $_.Count -gt 1
            }
    )
    if ($duplicateTops.Count -ne 0) {
        $duplicateNames = ($duplicateTops | ForEach-Object Name) -join ', '
        throw "Tên top testbench bị trùng: $duplicateNames"
    }

    Write-Host ''
    $testbenchCompileMessage = 'Compiling {0} testbench file(s)...' -f $testbenchFiles.Count
    Write-Host $testbenchCompileMessage -ForegroundColor Cyan
    foreach ($testbenchFile in $testbenchFiles) {
        $compileResult = Invoke-LoggedProcess $vlogPath @(
            '-sv',
            '-work',
            'rtl_work',
            ('+incdir+' + $rtlCore),
            ('+incdir+' + $rtlBus),
            ('+incdir+' + $rtlAccelerator),
            $testbenchFile.FullName
        )
        $testbenchLogPath = Join-Path $workRoot ('compile_' + $testbenchFile.BaseName + '.log')
        Write-Utf8Log -Path $testbenchLogPath -Content $compileResult.Output

        if ($compileResult.ExitCode -ne 0) {
            throw "Compile testbench thất bại tại $($testbenchFile.FullName)."
        }
    }

    Write-Host ''
    Write-Host 'Running testbenches...' -ForegroundColor Cyan

    $failureMarker = '(?im)\*\*\s+(?:error|fatal|failure)\b|\bFAIL\b'
    $passMarker = '(?im)\bPASS\b'
    $runMacroPath = Join-Path $workRoot 'run_test.do'
    $runMacroContent = @'
onerror {quit -force -code 2}
run -all
quit -force -code 0
'@
    Write-Utf8Log -Path $runMacroPath -Content $runMacroContent

    $testRuns = @($testbenchFiles | ForEach-Object {
        [pscustomobject]@{ Name = $_.BaseName; Top = $_.BaseName; Arguments = @() }
    })
    if ($Stress) {
        # The fake-sensor C firmware runs as a normal bench. Stress additionally
        # exercises real INA228 byte transactions and bounded failure paths.
        foreach ($fault in 0..7) {
            $testRuns += [pscustomobject]@{
                Name="tb_rv32_firmware_ina228_fault_$fault"
                Top='tb_rv32_firmware_e2e'
                Arguments=@('-gSENSOR_MODE=2', "-gFAULT_MODE=$fault")
            }
        }
        foreach ($config in @(@(8,1), @(9,3), @(100,1))) {
            $testRuns += [pscustomobject]@{
                Name = "tb_rv32_uart_rx_div_$($config[0])_depth_$($config[1])"
                Top = 'tb_rv32_uart_rx'
                Arguments = @("-gDIV=$($config[0])", "-gDEPTH=$($config[1])")
            }
        }
        $testRuns += [pscustomobject]@{
            Name='tb_rv32_uart_rx_fifo_depth_1'; Top='tb_rv32_uart_rx_fifo'; Arguments=@('-gDEPTH=1')
        }
        $testRuns += [pscustomobject]@{
            Name='tb_rv32_gpio_width_10'; Top='tb_rv32_gpio'; Arguments=@('-gLED_WIDTH=10')
        }
        foreach ($seed in 1..16) {
            $testRuns += [pscustomobject]@{
                Name = "tb_rv32_core_seed_$seed"; Top = 'tb_rv32_core'
                Arguments = @("-gSTRESS_SEED=$seed")
            }
        }
        foreach ($divider in @(1, 2, 3, 7)) {
            $testRuns += [pscustomobject]@{
                Name = "tb_rv32_uart_tx_div_$divider"; Top = 'tb_rv32_uart_tx'
                Arguments = @("-gDIV=$divider")
            }
        }
        foreach ($config in @(@(1, 1), @(1, 3), @(7, 3))) {
            $testRuns += [pscustomobject]@{
                Name = "tb_rv32_uart_fifo_div_$($config[0])_depth_$($config[1])"
                Top = 'tb_rv32_uart_fifo'
                Arguments = @("-gDIV=$($config[0])", "-gDEPTH=$($config[1])")
            }
        }
        foreach ($config in @(@(2, 0), @(2, 1), @(3, 0), @(3, 1), @(5, 0))) {
            $testRuns += [pscustomobject]@{
                Name = "tb_rv32_i2c_div_$($config[0])_sync_$($config[1])"
                Top = 'tb_rv32_i2c_transactions'
                Arguments = @("-gHALF_DIV=$($config[0])", "-gSYNC_INPUTS=$($config[1])")
            }
            $testRuns += [pscustomobject]@{
                Name = "tb_rv32_i2c_recovery_div_$($config[0])_sync_$($config[1])"
                Top = 'tb_rv32_i2c_recovery'
                Arguments = @("-gHALF_DIV=$($config[0])", "-gSYNC_INPUTS=$($config[1])")
            }
        }
    }

    foreach ($testRun in $testRuns) {
        $topName = $testRun.Name
        Write-Host ''
        Write-Host ('--- ' + $topName + ' ---') -ForegroundColor Yellow

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $simulationArguments = @(
            '-c',
            '-L',
            'rtl_work',
            ('work.' + $testRun.Top),
            '-do',
            $runMacroPath
        ) + $testRun.Arguments
        $simulationResult = Invoke-LoggedProcess $vsimPath $simulationArguments
        $stopwatch.Stop()

        $simulationLogPath = Join-Path $workRoot ($topName + '.log')
        Write-Utf8Log -Path $simulationLogPath -Content $simulationResult.Output

        $hasFailureMarker = [System.Text.RegularExpressions.Regex]::IsMatch(
            $simulationResult.Output,
            $failureMarker
        )
        $hasPassMarker = [System.Text.RegularExpressions.Regex]::IsMatch(
            $simulationResult.Output,
            $passMarker
        )
        $testPassed = $simulationResult.ExitCode -eq 0
        $testPassed = $testPassed -and (-not $hasFailureMarker)
        $testPassed = $testPassed -and $hasPassMarker

        $testResults += [pscustomobject]@{
            Name    = $topName
            Status  = if ($testPassed) { 'PASS' } else { 'FAIL' }
            Seconds = $stopwatch.Elapsed.TotalSeconds
        }

        if (-not $testPassed) {
            if ($simulationResult.ExitCode -ne 0) {
                throw "$topName trả mã $($simulationResult.ExitCode)."
            }
            elseif ($hasFailureMarker) {
                throw "$topName in dấu hiệu FAIL/Error/Fatal."
            }
            else {
                throw "$topName kết thúc nhưng không in PASS."
            }
        }
    }

    $regressionSucceeded = $true
    $failureReason = ''
}
catch {
    $failureReason = $_.Exception.Message
    Write-Host ''
    Write-Host ('Regression stopped: ' + $failureReason) -ForegroundColor Red
}
finally {
    if ($locationPushed) {
        Pop-Location
    }

    Write-RegressionSummary -Results $testResults -Succeeded $regressionSucceeded -FailureReason $failureReason
}

if (-not $regressionSucceeded) {
    exit 1
}

exit 0
