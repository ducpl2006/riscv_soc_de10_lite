param([Parameter(Mandatory = $true)][string]$PdfPath)

$bytes = [System.IO.File]::ReadAllBytes($PdfPath)
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$rawPdf = $latin1.GetString($bytes)

function Get-PdfObjectBody {
    param([int]$ObjectId)
    $pattern = '(?s)(?<!\d)' + $ObjectId + '\s+0\s+obj\s*(.*?)\s*endobj'
    $match = [regex]::Match($rawPdf, $pattern)
    if (-not $match.Success) { throw "Không tìm thấy PDF object $ObjectId" }
    return $match.Groups[1].Value
}

function Get-PdfStream {
    param([int]$ObjectId)
    $body = Get-PdfObjectBody $ObjectId
    $match = [regex]::Match($body, '(?s)<<(.*?)>>\s*stream\r?\n(.*)endstream')
    if (-not $match.Success) { return '' }
    [byte[]]$data = $latin1.GetBytes($match.Groups[2].Value)
    while ($data.Length -gt 0 -and ($data[-1] -eq 10 -or $data[-1] -eq 13)) {
        if ($data.Length -eq 1) { return '' }
        $data = $data[0..($data.Length - 2)]
    }
    if ($match.Groups[1].Value -notmatch '/FlateDecode') {
        return $latin1.GetString($data)
    }
    $input = [System.IO.MemoryStream]::new($data, 2, $data.Length - 6, $false)
    $deflate = [System.IO.Compression.DeflateStream]::new(
        $input,
        [System.IO.Compression.CompressionMode]::Decompress
    )
    $output = [System.IO.MemoryStream]::new()
    $deflate.CopyTo($output)
    $deflate.Dispose()
    return $latin1.GetString($output.ToArray())
}

function Convert-HexUnicode {
    param([string]$Hex)
    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index + 3 -lt $Hex.Length; $index += 4) {
        $code = [Convert]::ToInt32($Hex.Substring($index, 4), 16)
        [void]$builder.Append([char]$code)
    }
    return $builder.ToString()
}

function Get-ToUnicodeMap {
    param([int]$ObjectId)
    $cmap = Get-PdfStream $ObjectId
    $map = @{}
    $codeBytes = 1
    $space = [regex]::Match($cmap, '(?s)begincodespacerange\s*<([0-9A-Fa-f]+)>')
    if ($space.Success) { $codeBytes = [Math]::Max(1, $space.Groups[1].Value.Length / 2) }

    foreach ($match in [regex]::Matches(
            $cmap,
            '<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>'
        )) {
        $start = [Convert]::ToInt32($match.Groups[1].Value, 16)
        $finish = [Convert]::ToInt32($match.Groups[2].Value, 16)
        $unicodeStart = [Convert]::ToInt32($match.Groups[3].Value, 16)
        for ($code = $start; $code -le $finish; $code++) {
            $map[$code] = [char]($unicodeStart + ($code - $start))
        }
    }

    foreach ($match in [regex]::Matches(
            $cmap,
            '<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[(.*?)\]',
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )) {
        $code = [Convert]::ToInt32($match.Groups[1].Value, 16)
        foreach ($unicodeMatch in [regex]::Matches(
                $match.Groups[3].Value,
                '<([0-9A-Fa-f]+)>'
            )) {
            $map[$code] = Convert-HexUnicode $unicodeMatch.Groups[1].Value
            $code++
        }
    }
    return [pscustomobject]@{ Map = $map; CodeBytes = $codeBytes }
}

function Convert-LiteralToBytes {
    param([string]$Literal)
    $result = [System.Collections.Generic.List[byte]]::new()
    for ($index = 1; $index -lt $Literal.Length - 1; $index++) {
        $character = $Literal[$index]
        if ($character -ne '\') {
            $result.Add([byte][char]$character)
            continue
        }
        $index++
        if ($index -ge $Literal.Length - 1) { break }
        $escaped = $Literal[$index]
        switch ($escaped) {
            'n' { $result.Add(10); continue }
            'r' { $result.Add(13); continue }
            't' { $result.Add(9); continue }
            'b' { $result.Add(8); continue }
            'f' { $result.Add(12); continue }
            "`n" { continue }
            "`r" {
                if ($index + 1 -lt $Literal.Length -and $Literal[$index + 1] -eq "`n") {
                    $index++
                }
                continue
            }
        }
        if ($escaped -ge '0' -and $escaped -le '7') {
            $octal = [string]$escaped
            for ($count = 0; $count -lt 2 -and $index + 1 -lt $Literal.Length - 1; $count++) {
                $next = $Literal[$index + 1]
                if ($next -lt '0' -or $next -gt '7') { break }
                $index++
                $octal += $next
            }
            $result.Add([Convert]::ToByte($octal, 8))
        }
        else {
            $result.Add([byte][char]$escaped)
        }
    }
    return $result.ToArray()
}

function Convert-HexToBytes {
    param([string]$Token)
    $hex = ($Token.Substring(1, $Token.Length - 2) -replace '\s', '')
    if (($hex.Length % 2) -ne 0) { $hex += '0' }
    $result = [byte[]]::new($hex.Length / 2)
    for ($index = 0; $index -lt $result.Length; $index++) {
        $result[$index] = [Convert]::ToByte($hex.Substring($index * 2, 2), 16)
    }
    return $result
}

function Convert-FontBytes {
    param([byte[]]$Data, $FontInfo)
    if ($null -eq $FontInfo) { return $latin1.GetString($Data) }
    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Data.Length; $index += $FontInfo.CodeBytes) {
        $code = 0
        for ($part = 0; $part -lt $FontInfo.CodeBytes -and $index + $part -lt $Data.Length; $part++) {
            $code = ($code -shl 8) -bor $Data[$index + $part]
        }
        if ($FontInfo.Map.ContainsKey($code)) {
            [void]$builder.Append($FontInfo.Map[$code])
        }
        else {
            [void]$builder.Append('�')
        }
    }
    return $builder.ToString()
}

function Get-PageText {
    param([int]$PageObjectId)
    $page = Get-PdfObjectBody $PageObjectId
    $fontInfoByAlias = @{}
    foreach ($fontMatch in [regex]::Matches($page, '/([A-Za-z0-9_]+)\s+(\d+)\s+0\s+R')) {
        $alias = $fontMatch.Groups[1].Value
        $fontObjectId = [int]$fontMatch.Groups[2].Value
        $fontBody = Get-PdfObjectBody $fontObjectId
        $unicodeMatch = [regex]::Match($fontBody, '/ToUnicode\s+(\d+)\s+0\s+R')
        if ($unicodeMatch.Success) {
            $fontInfoByAlias[$alias] = Get-ToUnicodeMap ([int]$unicodeMatch.Groups[1].Value)
        }
    }

    $contentMatch = [regex]::Match($page, '/Contents\s*\[(.*?)\]')
    $contentIds = @([regex]::Matches($contentMatch.Groups[1].Value, '(\d+)\s+0\s+R') |
        ForEach-Object { [int]$_.Groups[1].Value })
    $output = [System.Text.StringBuilder]::new()

    foreach ($contentId in $contentIds) {
        $content = Get-PdfStream $contentId
        $tokenPattern = '/([A-Za-z0-9_]+)\s+[-+0-9.]+\s+Tf|' +
                        '(\((?:\\.|[^\\()])*\)|<[0-9A-Fa-f\s]+>)|' +
                        '\b(?:Td|TD|Tm|T\*|ET)\b'
        $currentFont = $null
        foreach ($tokenMatch in [regex]::Matches($content, $tokenPattern)) {
            if ($tokenMatch.Groups[1].Success) {
                $alias = $tokenMatch.Groups[1].Value
                $currentFont = if ($fontInfoByAlias.ContainsKey($alias)) {
                    $fontInfoByAlias[$alias]
                } else { $null }
            }
            elseif ($tokenMatch.Groups[2].Success) {
                $token = $tokenMatch.Groups[2].Value
                [byte[]]$data = if ($token[0] -eq '(') {
                    Convert-LiteralToBytes $token
                } else {
                    Convert-HexToBytes $token
                }
                [void]$output.Append((Convert-FontBytes $data $currentFont))
            }
            else {
                if ($output.Length -gt 0 -and $output[$output.Length - 1] -ne "`n") {
                    [void]$output.AppendLine()
                }
            }
        }
    }
    return $output.ToString()
}

$pageIds = [System.Collections.Generic.List[int]]::new()
foreach ($objectMatch in [regex]::Matches($rawPdf, '(?m)^(\d+)\s+0\s+obj\s*$')) {
    $candidateId = [int]$objectMatch.Groups[1].Value
    $candidateBody = Get-PdfObjectBody $candidateId
    if ($candidateBody -match '/Type\s*/Page\b') {
        $pageIds.Add($candidateId)
    }
}

for ($pageIndex = 0; $pageIndex -lt $pageIds.Count; $pageIndex++) {
    $pageId = $pageIds[$pageIndex]
    Write-Output "`n================ PAGE $($pageIndex + 1) (object $pageId) ================"
    Write-Output (Get-PageText $pageId)
}
