param(
    [Parameter(Mandatory = $true)][string]$PdfPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [int[]]$ObjectIds = @(40, 48, 49, 50, 57)
)

$bytes  = [System.IO.File]::ReadAllBytes($PdfPath)
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$rawPdf = $latin1.GetString($bytes)

[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null

foreach ($objectId in $ObjectIds) {
    $pattern = '(?s)(?<!\d)' + $objectId + '\s+0\s+obj\s*<<(.*?)>>\s*stream\r?\n'
    $match = [regex]::Match($rawPdf, $pattern)
    if (-not $match.Success) {
        throw "Khong tim thay stream cua PDF object $objectId"
    }

    $dictionary = $match.Groups[1].Value
    if ($dictionary -notmatch '/DCTDecode') {
        throw "PDF object $objectId khong phai anh JPEG"
    }

    $lengthMatch = [regex]::Match($dictionary, '/Length\s+(\d+)')
    if (-not $lengthMatch.Success) {
        throw "PDF object $objectId khong co Length truc tiep"
    }

    $length = [int]$lengthMatch.Groups[1].Value
    $start  = $match.Index + $match.Length
    [byte[]]$imageBytes = New-Object byte[] $length
    [System.Array]::Copy($bytes, $start, $imageBytes, 0, $length)

    $outputPath = Join-Path $OutputDirectory ("paper_obj_{0}.jpg" -f $objectId)
    [System.IO.File]::WriteAllBytes($outputPath, $imageBytes)
    Write-Host "$objectId -> $outputPath ($length bytes)"
}
