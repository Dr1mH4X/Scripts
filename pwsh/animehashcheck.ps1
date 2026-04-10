# ==========================================
#   Shingeki no Kyojin Hash Verification (PWSh 7)
# ==========================================

# Define external tool paths
$7zPath = "E:\Software\Scoop\shims\7z.exe"
$xxhPath = "E:\Software\Scoop\shims\xxhsum.exe"

$toolMissing = @()
if (-not (Test-Path $7zPath)) { $toolMissing += "7z.exe" }
if (-not (Test-Path $xxhPath)) { $toolMissing += "xxhsum.exe" }

if ($toolMissing.Count -gt 0) {
    Write-Host "Error: Missing tools: $($toolMissing -join ', '). Exiting." -ForegroundColor Red
    exit
}

# 1. Select Season
Write-Host "Select Season to Verify:" -ForegroundColor Cyan
Write-Host "  1. Season 1 (Ep 01-25)"
Write-Host "  2. Season 2 (Ep 26-37)"
Write-Host "  3. Season 3 (Ep 38-59)"
Write-Host "  4. Season 4 + Specials (Ep 60-89)"
$seasonChoice = Read-Host "Enter number (1/2/3/4)"

# 2. Select Hash Algorithm
Write-Host "`nSelect Hash Algorithm:" -ForegroundColor Cyan
Write-Host "  1. MD5 (32 chars, slowest)"
Write-Host "  2. CRC32 (8 chars, fast via 7-Zip)"
Write-Host "  3. XXH128 (32 chars, Ultra-fast via xxhsum -H2)"
$hashChoice = Read-Host "Enter number (1/2/3)"

$hashMethod = switch ($hashChoice) {
    "2" { "CRC" }
    "3" { "XXH128" }
    default { "MD5" }
}

# 3. Configuration Dictionary (Paths + Episode Offset)
$Config = @{
    "1" = @{ PathM = 'M:\Anime-BD\进击的巨人 (2013)\Season 1\';
            PathZ = 'Z:\Downloads\Anime\[VCB-Studio] Shingeki no Kyojin\[DMG&EMD&VCB-Studio] Shingeki no Kyojin [Ma10p_1080p]\';
            Offset = 0 }
    "2" = @{ PathM = 'M:\Anime-BD\进击的巨人 (2013)\Season 2\';
            PathZ = 'Z:\Downloads\Anime\[VCB-Studio] Shingeki no Kyojin\[DMG&VCB-Studio] Shingeki no Kyojin Season 2 [Ma10p_1080p]\';
            Offset = 25 }
    "3" = @{ PathM = 'M:\Anime-BD\进击的巨人 (2013)\Season 3\';
            PathZ = 'Z:\Downloads\Anime\[VCB-Studio] Shingeki no Kyojin\[BeanSub&VCB-Studio] Shingeki no Kyojin Season 3 [Ma10p_1080p]\';
            Offset = 37 }
    "4" = @{ PathM = 'M:\Anime-BD\进击的巨人 (2013)\Season 4\';
            PathZ = 'Z:\Downloads\Anime\[VCB-Studio] Shingeki no Kyojin\[BeanSub&VCB-Studio] Shingeki no Kyojin The Final Season [Ma10p_1080p]\';
            Offset = 59 }
}

# 4. Validate Input & Get Settings
if (-not $Config.ContainsKey($seasonChoice)) {
    Write-Host "Error: Invalid season choice. Exiting." -ForegroundColor Red
    exit
}

$settings = $Config[$seasonChoice]
$pathM = $settings.PathM
$pathZ = $settings.PathZ
$offset = $settings.Offset

if (-not (Test-Path -LiteralPath $pathM) -or -not (Test-Path -LiteralPath $pathZ)) {
    Write-Host "Error: M-drive or Z-drive path does not exist. Exiting." -ForegroundColor Red
    exit
}

# 5. Get File Lists
$filesM = Get-ChildItem -LiteralPath $pathM -Filter *.mkv
$filesZ = Get-ChildItem -LiteralPath $pathZ -Filter *.mkv

Write-Host "`n--- Shingeki no Kyojin S0$seasonChoice [$hashMethod] Comparison ---" -ForegroundColor Cyan
Write-Host "M Path: $pathM"
Write-Host "Z Path: $pathZ"
Write-Host "Offset: +$offset"
Write-Host "Source M count: $($filesM.Count) | Source Z count: $($filesZ.Count)"
Write-Host "------------------------------------------------"

# 6. Core Comparison Logic
$count = 0
$skipped = 0

foreach ($fM in $filesM) {
    if ($fM.Name -match 'E(\d+)') {
        $relEp = $matches[1]
        $absEp = [int]$relEp + $offset

        # 修复 1：格式化集数为 2 位数（如 01），避免误将 1 匹配为 10, 11
        $epStr = "{0:D2}" -f $absEp

        # 修复 2：极其严格的独立集数正则。避免贪婪匹配，坚决排查掉 1080p、10bit 的干扰
        # 仅匹配带有方括号、空格包裹、紧连扩展名或 E前缀 的独立剧集，支持 v2 修复版
        $strictRegex = "\[$epStr(?:v\d)?\]|\s$epStr(?:v\d)?\s|\s$epStr(?:v\d)?\.|E$epStr\b|\-$epStr\b"

        $fZ = $filesZ | Where-Object { $_.Name -match $strictRegex }

        if (-not $fZ -and $seasonChoice -eq "4" -and $relEp -eq "29") {
            $fZ = $filesZ | Where-Object { $_.Name -match "Kanketsu-hen.*Zenpen" }
        }
        if (-not $fZ -and $seasonChoice -eq "4" -and $relEp -eq "30") {
            $fZ = $filesZ | Where-Object { $_.Name -match "Kanketsu-hen.*Kouhen" }
        }

        if (-not $fZ) {
            Write-Host "Skip: S0${seasonChoice}E$relEp - No matching file on Z-Drive." -ForegroundColor DarkYellow
            $skipped++
            continue
        }

        # 如果意外匹配到多个文件(如同集有 v1 和 v2 且都在目录中)，强制取字典序最后的一个
        if ($fZ -is [array] -or $fZ.Count -gt 1) {
            $fZ = $fZ | Sort-Object Name | Select-Object -Last 1
        }

        $count++
        Write-Progress -Activity "Calculating $hashMethod (Parallel)" -Status "Processing S0${seasonChoice}E$relEp (Abs: $absEp)" -PercentComplete (($count / $filesM.Count) * 100)

            try {
                # 修复 3：打包带有 Key 标识的哈希字典，彻底根绝 Parallel 乱序返回带来的数据错乱
                $tasks = @(
                    @{ Key = "M"; Path = $fM.FullName },
                    @{ Key = "Z"; Path = $fZ.FullName }
                )

                $hashes = $tasks | ForEach-Object -Parallel {
                    $item = $_
                    $file = $item.Path
                    $method = $using:hashMethod
                    $7z = $using:7zPath
                    $xxh = $using:xxhPath
                    $result = "HASH_FAILED"

                    $tmpFile = Join-Path $env:TEMP "hash_$(Get-Random)_$($item.Key).txt"

                    try {
                        if ($method -eq "MD5") {
                            $result = (Get-FileHash -LiteralPath $file -Algorithm MD5).Hash
                        } else {
                            if ($method -eq "CRC") {
                                & $7z h -scrcCRC32 $file > $tmpFile 2>&1
                            } elseif ($method -eq "XXH128") {
                                & $xxh -H2 $file > $tmpFile 2>&1
                            }
                            $out = Get-Content -Path $tmpFile -Raw

                            if ($method -eq "CRC" -and $out -match "CRC32.*([0-9A-Fa-f]{8})\s*$") {
                                $result = $matches[1].ToUpper()
                            } elseif ($method -eq "XXH128" -and $out -match "\\?([0-9A-Fa-f]{32})\s") {
                                $result = $matches[1].ToUpper()
                            }
                        }
                    } catch {
                    } finally {
                        if (Test-Path -LiteralPath $tmpFile) {
                            Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
                        }
                    }

                    # 包含身份标识返回
                    [PSCustomObject]@{
                        Key  = $item.Key
                        Hash = $result
                    }
                } -ThrottleLimit 2
            } catch {
                Write-Host "Error: Parallel execution failed for S0${seasonChoice}E$relEp." -ForegroundColor Red
                continue
            }

        if ($null -eq $hashes -or $hashes.Count -lt 2) {
            Write-Host "Error: Hash calculation returned no results for S0${seasonChoice}E$relEp." -ForegroundColor Red
            continue
        }

        # 通过 Key 来绝对定位，防止顺序乱掉
        $hashM = ($hashes | Where-Object { $_.Key -eq "M" }).Hash
        $hashZ = ($hashes | Where-Object { $_.Key -eq "Z" }).Hash

        Write-Host "S0${seasonChoice}E$relEp (Abs: $absEp):" -ForegroundColor Yellow
        Write-Host "  M-File: $($fM.Name)"
        Write-Host "  Z-File: $($fZ.Name)"
        Write-Host "  $hashMethod-M : $hashM"
        Write-Host "  $hashMethod-Z : $hashZ"

        if ($hashM -eq "HASH_FAILED" -or $hashZ -eq "HASH_FAILED") {
            Write-Host "  Result: [ HASH FAILED ]" -ForegroundColor Magenta
        } elseif ($hashM -eq $hashZ) {
            Write-Host "  Result: [ MATCH ]" -ForegroundColor Green
        } else {
            Write-Host "  Result: [ CONFLICT / MISMATCH ]" -ForegroundColor Red
        }
        Write-Host "------------------------------------------------"
    }
}

# 7. Final Summary
Write-Host "================ Summary ================" -ForegroundColor Cyan
Write-Host "  Compared : $count"
Write-Host "  Skipped  : $skipped"
Write-Host "  Algorithm: $hashMethod"
Write-Host "=========================================" -ForegroundColor Cyan
