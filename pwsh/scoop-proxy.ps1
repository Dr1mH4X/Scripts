# ============================================================
# scoop-ghproxy.ps1 — Scoop GitHub 加速管理脚本
#
# 功能:
#   1. 自定义加速链接: gh-proxy.com / ghfast.top / 自定义
#   2. 选择替换范围: 仅 bucket / 仅下载链接 / 两者都替换
#   3. 恢复 download.ps1 原始备份
#   4. 恢复 bucket 原始 GitHub 地址
#
# 用法:
#   交互模式:             .\scoop-ghproxy.ps1
#   非交互:               .\scoop-ghproxy.ps1 -Proxy ghfast.top -Action enable-both
#   仅查看状态:           .\scoop-ghproxy.ps1 -Status
#   恢复下载链接 patch:   .\scoop-ghproxy.ps1 -Action restore-download
#   恢复 bucket 原始地址: .\scoop-ghproxy.ps1 -Action restore-bucket
#
# 注意:
#   - 找不到 Scoop 时可用 -ScoopDir 指定根目录
#   - scoop update 自更新会覆盖 download.ps1 导致 patch 失效, 重跑本脚本即可
# ============================================================

param(
    [string]$Proxy,
    [ValidateSet('enable-bucket', 'enable-download', 'enable-both', 'switch-proxy', 'restore-download', 'restore-bucket')]
    [string]$Action,
    [switch]$Status,
    [string]$ScoopDir,
    [switch]$SkipConfig
)

$KnownProxies = @('gh-proxy.com', 'ghfast.top')
$patchMarker = '# === SCOOP-GITHUB-PROXY-PATCHED ==='

# ============================================================
# 工具函数
# ============================================================

function Find-ScoopDir {
    if ($env:SCOOP -and (Test-Path $env:SCOOP)) { return $env:SCOOP }
    $configPath = "$env:USERPROFILE\.config\scoop\config.json"
    if (Test-Path $configPath) {
        try {
            $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($cfg.root_path -and (Test-Path $cfg.root_path)) { return $cfg.root_path }
        } catch { }
    }
    $default = "$env:USERPROFILE\scoop"
    if (Test-Path $default) { return $default }
    $cmd = Get-Command scoop -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $root = Split-Path -Parent (Split-Path -Parent $cmd.Source)
        if (Test-Path "$root\apps\scoop\current") { return $root }
    }
    return $null
}

function Get-DownloadPs1 {
    param([string]$ScoopDir)
    $path = "$ScoopDir\apps\scoop\current\lib\download.ps1"
    if (Test-Path $path) { return $path }
    return $null
}

function Test-IsPatched {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path)) { return $false }
    return (Get-Content $Path -Raw -Encoding UTF8).Contains($patchMarker)
}

function Get-OrigPath {
    param([string]$Path)
    return "$Path.sgp-orig"
}

function Normalize-Proxy {
    param([string]$Value)
    return ($Value.Trim().TrimStart('http://').TrimStart('https://').TrimEnd('/'))
}

function Get-BucketRemoteUrls {
    param([string]$ScoopDir)
    $bucketsDir = Join-Path $ScoopDir 'buckets'
    $map = @{}
    if (-not (Test-Path $bucketsDir)) { return $map }
    Get-ChildItem $bucketsDir -Directory | ForEach-Object {
        $cfgPath = Join-Path $_.FullName '.git\config'
        if (Test-Path $cfgPath) {
            $raw = Get-Content $cfgPath -Raw
            if ($raw -match '(?m)^\s*url\s*=\s*(.+?)\s*$') {
                $map[$_.Name] = $Matches[1].Trim()
            }
        }
    }
    return $map
}

# 裸 github 地址 -> 代理前缀地址 (非 github 地址返回 $null)
function Get-ProxiedUrl {
    param([string]$Url, [string]$Proxy)
    $bare = $Url
    foreach ($p in $KnownProxies) {
        $bare = $bare -replace "^https://$([regex]::Escape($p))/https://", 'https://'
    }
    if ($bare -match '^https?://github\.com/') { return "https://$Proxy/$bare" }
    return $null
}

# 代理前缀地址 -> 裸 github 地址 (非代理地址返回 $null)
function Get-BareUrl {
    param([string]$Url)
    $bare = $Url
    foreach ($p in $KnownProxies) {
        $bare = $bare -replace "^https://$([regex]::Escape($p))/https://", 'https://'
    }
    if ($bare -ne $Url) { return $bare }
    return $null
}

function Read-ProxyConfig {
    foreach ($cfgPath in @("$env:USERPROFILE\.config\scoop\config.json", "$ScoopDir\config.json")) {
        if ($cfgPath -and (Test-Path $cfgPath)) {
            try {
                $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
                if ($cfg.GITHUB_PROXY) { return [string]$cfg.GITHUB_PROXY }
            } catch { }
        }
    }
    return $null
}

# ============================================================
# 启用 - 替换 bucket 地址
# ============================================================

function Enable-BucketProxy {
    param([string]$ScoopRoot, [string]$Proxy)
    Write-Host "--- 替换 bucket (代理: https://$Proxy) ---"
    $map = Get-BucketRemoteUrls $ScoopRoot
    $changed = 0
    foreach ($name in ($map.Keys | Sort-Object)) {
        $new = Get-ProxiedUrl $map[$name] $Proxy
        if ($new -and $new -ne $map[$name]) {
            git -C (Join-Path (Join-Path $ScoopRoot 'buckets') $name) remote set-url origin $new
            Write-Host "  [OK] $name -> $new" -ForegroundColor Green
            $changed++
        } elseif ($new -and $new -eq $map[$name]) {
            Write-Host "  [--] $name 已是 $new"
        }
    }
    if ($changed -eq 0) { Write-Host '  没有需要替换的 GitHub bucket' -ForegroundColor Yellow }
}

# ============================================================
# 启用 - 替换下载链接 (patch download.ps1)
# ============================================================

function Enable-DownloadProxy {
    param([string]$ScoopRoot, [string]$Proxy)
    $downloadPs1 = Get-DownloadPs1 $ScoopRoot
    if (-not $downloadPs1) {
        Write-Host 'ERROR: 找不到 download.ps1' -ForegroundColor Red
        return
    }

    if (Test-IsPatched $downloadPs1) {
        if (-not $SkipConfig) {
            scoop config GITHUB_PROXY "https://$Proxy" | Out-Null
            Write-Host "OK: download.ps1 已 patch, 仅更新 GITHUB_PROXY = https://$Proxy (无需重新注入)" -ForegroundColor Green
        } else {
            Write-Host 'INFO: download.ps1 已 patch, 跳过配置更新 (SkipConfig)'
        }
        return
    }

    $orig = Get-OrigPath $downloadPs1
    Copy-Item $downloadPs1 $orig -Force
    Write-Host "OK: 已备份原始文件 -> download.ps1.sgp-orig"

    if (-not $SkipConfig) {
        scoop config GITHUB_PROXY "https://$Proxy" | Out-Null
        Write-Host "OK: scoop config GITHUB_PROXY = https://$Proxy"
    }

    $content = Get-Content $downloadPs1 -Raw -Encoding UTF8
    $lines = $content -split '\r?\n'

    $funcStart = -1
    $funcEnd = -1
    $braceCount = 0
    $inFunction = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if (-not $inFunction -and $line -match '^\s*function\s+handle_special_urls\s*\(') {
            $funcStart = $i
            $inFunction = $true
        }
        if ($inFunction) {
            $opens = ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
            $closes = ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
            $braceCount += ($opens - $closes)
            if ($braceCount -le 0) {
                $funcEnd = $i
                break
            }
        }
    }

    if ($funcStart -lt 0 -or $funcEnd -lt 0) {
        Write-Host 'ERROR: 无法定位 handle_special_urls 函数' -ForegroundColor Red
        return
    }

    $lastReturnLine = -1
    for ($i = $funcEnd - 1; $i -gt $funcStart; $i--) {
        if ($lines[$i] -match '^\s*return\s+\$url\s*$') {
            $lastReturnLine = $i
            break
        }
    }

    if ($lastReturnLine -lt 0) {
        Write-Host 'ERROR: 在 handle_special_urls 中未找到 return $url' -ForegroundColor Red
        return
    }

    $indent = ''
    if ($lines[$lastReturnLine] -match '^(\s*)') { $indent = $Matches[1] }

    $injected = @'
# === SCOOP-GITHUB-PROXY-PATCHED ===
# 自动为 GitHub 下载 URL 拼接代理，可通过 scoop config GITHUB_PROXY 配置
$ghProxy = get_config GITHUB_PROXY
if (
    $ghProxy -and
    $url -match '^https?://(github\.com|raw\.githubusercontent\.com|api\.github\.com|objects-githubusercontent\.com|release-assets\.githubusercontent\.com|codeload\.github\.com|gist\.githubusercontent\.com)/'
) {
    $url = "$ghProxy/$url"
}
# === END SCOOP-GITHUB-PROXY ===
'@
    $blockLines = $injected -split "`r?`n" | ForEach-Object { $indent + $_ }
    $newLines = $lines[0..($lastReturnLine - 1)] + $blockLines + $lines[$lastReturnLine..($lines.Count - 1)]
    $newContent = $newLines -join "`r`n"

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($downloadPs1, $newContent, $utf8NoBom)
    Write-Host "OK: download.ps1 已 patch (代理: https://$Proxy)" -ForegroundColor Green
}

# ============================================================
# 切换加速链接 (只更新配置与 bucket 前缀, 无需重新 patch)
# ============================================================

function Switch-Proxy {
    param([string]$ScoopRoot, [string]$Proxy)
    $downloadPs1 = Get-DownloadPs1 $ScoopRoot
    if (Test-IsPatched $downloadPs1) {
        if (-not $SkipConfig) {
            scoop config GITHUB_PROXY "https://$Proxy" | Out-Null
            Write-Host "OK: GITHUB_PROXY 已更新为 https://$Proxy (download.ps1 无需重新 patch)" -ForegroundColor Green
        }
    } else {
        Write-Host 'INFO: download.ps1 未 patch, 跳过下载链接代理'
    }
    Enable-BucketProxy $ScoopRoot $Proxy
}

# ============================================================
# 恢复 - 还原 download.ps1
# ============================================================

function Disable-DownloadProxy {
    param([string]$ScoopRoot, [switch]$Silent)
    $downloadPs1 = Get-DownloadPs1 $ScoopRoot
    if (-not $downloadPs1) {
        if (-not $Silent) { Write-Host 'ERROR: 找不到 download.ps1' -ForegroundColor Red }
        return
    }

    $orig = Get-OrigPath $downloadPs1
    if (Test-Path $orig) {
        Copy-Item $orig $downloadPs1 -Force
        Remove-Item $orig
        if (-not $Silent) { Write-Host 'OK: 已从备份 (.sgp-orig) 恢复原始 download.ps1' -ForegroundColor Green }
    } elseif (Test-IsPatched $downloadPs1) {
        $content = Get-Content $downloadPs1 -Raw -Encoding UTF8
        $pattern = '(?sm)^\s*# === SCOOP-GITHUB-PROXY-PATCHED ===.*?# === END SCOOP-GITHUB-PROXY ===\s*\r?\n'
        $newContent = $content -replace $pattern, ''
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($downloadPs1, $newContent, $utf8NoBom)
        if (-not $Silent) { Write-Host 'OK: 已移除 patch 代码 (无备份, 正则清理)' -ForegroundColor Green }
    } else {
        if (-not $Silent) { Write-Host 'INFO: download.ps1 未被 patch, 无需操作' }
        if ($SkipConfig) { return }
    }

    if (-not $SkipConfig) {
        scoop config rm GITHUB_PROXY 2>&1 | Out-Null
        Write-Host 'OK: 已移除 GITHUB_PROXY 配置'
    }
}

# ============================================================
# 恢复 - 移除 bucket 代理前缀
# ============================================================

function Disable-BucketProxy {
    param([string]$ScoopRoot)
    Write-Host '--- 恢复 bucket 原始 GitHub 地址 ---'
    $map = Get-BucketRemoteUrls $ScoopRoot
    $changed = 0
    foreach ($name in ($map.Keys | Sort-Object)) {
        $bare = Get-BareUrl $map[$name]
        if ($bare) {
            git -C (Join-Path (Join-Path $ScoopRoot 'buckets') $name) remote set-url origin $bare
            Write-Host "  [OK] $name -> $bare" -ForegroundColor Green
            $changed++
        }
    }
    if ($changed -eq 0) { Write-Host '  没有带代理前缀的 bucket' -ForegroundColor Yellow }
}

# ============================================================
# 状态
# ============================================================

function Show-Status {
    param([string]$ScoopRoot)
    Write-Host ''
    Write-Host '=== Scoop GitHub 加速状态 ===' -ForegroundColor Cyan
    Write-Host "Scoop 路径: $ScoopRoot"

    $downloadPs1 = Get-DownloadPs1 $ScoopRoot
    $patched = $downloadPs1 -and (Test-IsPatched $downloadPs1)
    $hasBackup = $downloadPs1 -and (Test-Path (Get-OrigPath $downloadPs1))
    Write-Host -NoNewline 'download.ps1:  '
    if ($patched) { Write-Host '已 Patch' -ForegroundColor Green } else { Write-Host '未 Patch' -ForegroundColor Yellow }
    Write-Host -NoNewline '备份文件:      '
    if ($hasBackup) { Write-Host '有 (download.ps1.sgp-orig)' } else { Write-Host '无' -ForegroundColor Yellow }

    $proxy = Read-ProxyConfig
    Write-Host -NoNewline 'GITHUB_PROXY:  '
    if ($proxy) { Write-Host $proxy } else { Write-Host '未设置' -ForegroundColor Yellow }

    $map = Get-BucketRemoteUrls $ScoopRoot
    $proxied = @(); $bare = @(); $other = @()
    foreach ($name in ($map.Keys | Sort-Object)) {
        $u = $map[$name]
        if ($u -match "^https://(gh-proxy\.com|ghfast\.top)/https://github\.com/") { $proxied += $name }
        elseif ($u -match '^https?://github\.com/') { $bare += $name }
        else { $other += $name }
    }
    Write-Host -NoNewline 'bucket 带代理:  '
    if ($proxied) { Write-Host ($proxied -join ', ') } else { Write-Host '无' -ForegroundColor Yellow }
    Write-Host -NoNewline 'bucket 直连:    '
    if ($bare) { Write-Host ($bare -join ', ') } else { Write-Host '无' -ForegroundColor Yellow }
    Write-Host -NoNewline 'bucket 其他源:  '
    if ($other) { Write-Host ($other -join ', ') } else { Write-Host '无' }
    Write-Host ''
}

# ============================================================
# 更新 Scoop 核心并重新启用加速
# ============================================================

function Update-ScoopAndReEnable {
    param([string]$ScoopRoot)
    $autostash = ((scoop config autostash_on_conflict 2>$null | Out-String).Trim())
    if ($autostash -notmatch '^(?i)true$') {
        scoop config autostash_on_conflict true | Out-Null
        Write-Host 'OK: 已启用 autostash_on_conflict (scoop update 不再因 patch 中止)' -ForegroundColor Green
    }
    Write-Host '--- 更新 Scoop 核心 ---'
    scoop update scoop 2>&1
    Write-Host ''

    $proxy = Read-ProxyConfig
    if (-not $proxy) {
        Write-Host 'GITHUB_PROXY 未设置, 请选择加速链接:' -ForegroundColor Yellow
        $p = Select-Proxy
        if (-not $p) { return }
        Enable-DownloadProxy $ScoopRoot $p
    } else {
        $proxyHost = Normalize-Proxy $proxy
        Write-Host "GITHUB_PROXY 当前为 $proxy, 重新启用..." -ForegroundColor Cyan
        Enable-DownloadProxy $ScoopRoot $proxyHost
    }

    Write-Host ''
    git -C "$ScoopRoot\apps\scoop\current" stash clear
    Write-Host 'OK: 已清理 autostash 残留 (git stash clear)' -ForegroundColor Green
}

# ============================================================
# 交互菜单
# ============================================================

function Select-Proxy {
    Write-Host ''
    Write-Host '  选择加速链接:'
    Write-Host '  1. gh-proxy.com'
    Write-Host '  2. ghfast.top'
    Write-Host '  3. 自定义 (输入域名, 不带 https://)'
    $c = Read-Host '  请输入 [1-3]'
    switch ($c) {
        '1' { return 'gh-proxy.com' }
        '2' { return 'ghfast.top' }
        '3' {
            $u = Read-Host '  代理域名 (如 my-proxy.example.com)'
            if ($u) { return (Normalize-Proxy $u) }
            Write-Host '  无效输入' -ForegroundColor Red
            return $null
        }
        default {
            Write-Host "  无效输入: $c" -ForegroundColor Red
            return $null
        }
    }
}

function Show-Menu {
    param([string]$ScoopRoot)
    Show-Status $ScoopRoot
    while ($true) {
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host '      Scoop GitHub 加速管理' -ForegroundColor Cyan
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host '  1. 启用加速 - 替换 bucket (git remote 加代理前缀)'
        Write-Host '  2. 启用加速 - 替换下载链接 (patch download.ps1)'
        Write-Host '  3. 启用加速 - 两者都替换'
        Write-Host '  4. 恢复 - 还原 download.ps1 原始备份'
        Write-Host '  5. 恢复 - 移除 bucket 代理前缀'
        Write-Host '  6. 更新 Scoop 并重新启用加速 (autostash 兼容)'
        Write-Host '  0. 退出'
        $choice = Read-Host '  请输入 [0-6]'
        switch ($choice) {
            '1' {
                $p = Select-Proxy
                if ($p) { Enable-BucketProxy $ScoopRoot $p }
            }
            '2' {
                $p = Select-Proxy
                if ($p) { Enable-DownloadProxy $ScoopRoot $p }
            }
            '3' {
                $p = Select-Proxy
                if ($p) { Enable-DownloadProxy $ScoopRoot $p; Enable-BucketProxy $ScoopRoot $p }
            }
            '4' { Disable-DownloadProxy $ScoopRoot }
            '5' { Disable-BucketProxy $ScoopRoot }
            '6' { Update-ScoopAndReEnable $ScoopRoot }
            '0' { return }
            default { Write-Host "  无效输入: $choice" -ForegroundColor Red }
        }
    }
}

# ============================================================
# Main
# ============================================================

function Main {
    $script:ScoopDir = if ($ScoopDir) { $ScoopDir } else { Find-ScoopDir }
    if (-not $script:ScoopDir -or -not (Test-Path $script:ScoopDir)) {
        Write-Host 'ERROR: 找不到 Scoop 安装目录 (可设置 SCOOP 环境变量或用 -ScoopDir 指定)' -ForegroundColor Red
        exit 1
    }

    if ($Status) {
        Show-Status $script:ScoopDir
        return
    }

    if ($Action) {
        if ($Proxy) { $Proxy = Normalize-Proxy $Proxy }
        switch ($Action) {
            'enable-bucket' {
                if (-not $Proxy) { Write-Host 'ERROR: 需要 -Proxy 参数 (如 ghfast.top)' -ForegroundColor Red; return }
                Enable-BucketProxy $script:ScoopDir $Proxy
            }
            'enable-download' {
                if (-not $Proxy) { Write-Host 'ERROR: 需要 -Proxy 参数 (如 ghfast.top)' -ForegroundColor Red; return }
                Enable-DownloadProxy $script:ScoopDir $Proxy
            }
            'enable-both' {
                if (-not $Proxy) { Write-Host 'ERROR: 需要 -Proxy 参数 (如 ghfast.top)' -ForegroundColor Red; return }
                Enable-DownloadProxy $script:ScoopDir $Proxy
                Enable-BucketProxy $script:ScoopDir $Proxy
            }
            'switch-proxy' {
                if (-not $Proxy) { Write-Host 'ERROR: 需要 -Proxy 参数 (如 ghfast.top)' -ForegroundColor Red; return }
                Switch-Proxy $script:ScoopDir $Proxy
            }
            'restore-download' { Disable-DownloadProxy $script:ScoopDir }
            'restore-bucket' { Disable-BucketProxy $script:ScoopDir }
        }
        return
    }

    Show-Menu $script:ScoopDir
}

if ($MyInvocation.InvocationName -ne '.') { Main }
