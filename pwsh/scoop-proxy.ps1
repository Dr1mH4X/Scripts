# ============================================================
# scoop-proxy.ps1 — Scoop GitHub proxy manager
#
# Features:
# 1. Custom proxy URL: gh-proxy.com / ghfast.top / custom
# 2. Choose scope: bucket only / download links only / both
# 3. Restore download.ps1 from original backup
# 4. Restore bucket original GitHub URLs
# 5. Command-line update: -Update (with -Proxy to specify new proxy)
#
# Usage:
# Interactive (recommended): irm https://raw.githubusercontent.com/... | iex
# Or run locally: .\scoop-proxy.ps1
#
# Non-interactive:
# Enable proxy: .\scoop-proxy.ps1 -Proxy ghfast.top -Action enable-both
# Status only:  .\scoop-proxy.ps1 -Status
# Update + enable: .\scoop-proxy.ps1 -Update
#
# Notes:
# - If Scoop is not found, use -ScoopDir to specify the root directory
# - scoop update will overwrite download.ps1 and break the patch; rerun this script
# ============================================================

# Manual argument parsing (compatible with irm | iex, iex does not support param block)
$Proxy = $null
$Action = $null
$Status = $false
$ScoopDir = $null
$SkipConfig = $false
$Update = $false

for ($i = 0; $i -lt $args.Count; $i++)
{
    switch ($args[$i])
    {
        '-Proxy'
        { $Proxy = $args[++$i]
        }
        '-Action'
        { $Action = $args[++$i]
        }
        '-ScoopDir'
        { $ScoopDir = $args[++$i]
        }
        '-Status'
        { $Status = $true
        }
        '-SkipConfig'
        { $SkipConfig = $true
        }
        '-Update'
        { $Update = $true
        }
        default
        { Write-Host "WARN: Unknown argument: $($args[$i])" -ForegroundColor Yellow
        }
    }
}

$KnownProxies = @('gh-proxy.com', 'ghfast.top')
$patchMarker = '# === SCOOP-GITHUB-PROXY-PATCHED ==='

# ============================================================
# Utility functions
# ============================================================

function Find-ScoopDir
{
    if ($env:SCOOP -and (Test-Path $env:SCOOP))
    { return $env:SCOOP
    }
    $configPath = "$env:USERPROFILE\.config\scoop\config.json"
    if (Test-Path $configPath)
    {
        try
        {
            $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($cfg.root_path -and (Test-Path $cfg.root_path))
            { return $cfg.root_path
            }
        } catch
        {
        }
    }
    $default = "$env:USERPROFILE\scoop"
    if (Test-Path $default)
    { return $default
    }
    $cmd = Get-Command scoop -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source)
    {
        $root = Split-Path -Parent (Split-Path -Parent $cmd.Source)
        if (Test-Path "$root\apps\scoop\current")
        { return $root
        }
    }
    return $null
}

function Get-DownloadPs1
{
    param([string]$ScoopDir)
    $path = "$ScoopDir\apps\scoop\current\lib\download.ps1"
    if (Test-Path $path)
    { return $path
    }
    return $null
}

function Test-IsPatched
{
    param([string]$Path)
    if (-not $Path -or -not (Test-Path $Path))
    { return $false
    }
    return (Get-Content $Path -Raw -Encoding UTF8).Contains($patchMarker)
}

function Get-OrigPath
{
    param([string]$Path)
    return "$Path.sgp-orig"
}

function Normalize-Proxy
{
    param([string]$Value)
    return ($Value.Trim().TrimStart('http://').TrimStart('https://').TrimEnd('/'))
}

function Send-Notification
{
    param([string]$Text)
    try
    {
        Import-Module BurntToast -ErrorAction Stop
        New-BurntToastNotification -Text $Text
    } catch
    {
        Write-Host 'INFO: BurntToast not available, skipping notification.'
    }
}

function Get-BucketRemoteUrls
{
    param([string]$ScoopDir)
    $bucketsDir = Join-Path $ScoopDir 'buckets'
    $map = @{}
    if (-not (Test-Path $bucketsDir))
    { return $map
    }
    Get-ChildItem $bucketsDir -Directory | ForEach-Object {
        $cfgPath = Join-Path $_.FullName '.git\config'
        if (Test-Path $cfgPath)
        {
            $raw = Get-Content $cfgPath -Raw
            if ($raw -match '(?m)^\s*url\s*=\s*(.+?)\s*$')
            {
                $map[$_.Name] = $Matches[1].Trim()
            }
        }
    }
    return $map
}

# Bare github URL -> proxied URL (non-github returns $null)
function Get-ProxiedUrl
{
    param([string]$Url, [string]$Proxy)
    $bare = $Url
    foreach ($p in $KnownProxies)
    {
        $bare = $bare -replace "^https://$([regex]::Escape($p))/https://", 'https://'
    }
    if ($bare -match '^https?://github\.com/')
    {
        return "https://$Proxy/$bare"
    }
    return $null
}

# Proxied URL -> bare github URL (non-proxied returns $null)
function Get-BareUrl
{
    param([string]$Url)
    $bare = $Url
    foreach ($p in $KnownProxies)
    {
        $bare = $bare -replace "^https://$([regex]::Escape($p))/https://", 'https://'
    }
    if ($bare -ne $Url)
    { return $bare
    }
    return $null
}

function Read-ProxyConfig
{
    foreach ($cfgPath in @("$env:USERPROFILE\.config\scoop\config.json", "$ScoopDir\config.json"))
    {
        if ($cfgPath -and (Test-Path $cfgPath))
        {
            try
            {
                $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
                if ($cfg.GITHUB_PROXY)
                { return [string]$cfg.GITHUB_PROXY
                }
            } catch
            {
            }
        }
    }
    return $null
}

# ============================================================
# Enable - replace bucket URLs
# ============================================================

function Enable-BucketProxy
{
    param([string]$ScoopRoot, [string]$Proxy)
    Write-Host "--- Replacing buckets (proxy: https://$Proxy) ---"
    $map = Get-BucketRemoteUrls $ScoopRoot
    $changed = 0
    foreach ($name in ($map.Keys | Sort-Object))
    {
        $new = Get-ProxiedUrl $map[$name] $Proxy
        if ($new -and $new -ne $map[$name])
        {
            git -C (Join-Path (Join-Path $ScoopRoot 'buckets') $name) remote set-url origin $new
            Write-Host " [OK] $name -> $new" -ForegroundColor Green
            $changed++
        } elseif ($new -and $new -eq $map[$name])
        {
            Write-Host " [--] $name already set to $new"
        }
    }
    if ($changed -eq 0)
    { Write-Host ' No GitHub buckets need replacement' -ForegroundColor Yellow
    }
}

# ============================================================
# Enable - replace download links
# ============================================================

function Ensure-AutoStash
{
    $autostash = ((scoop config autostash_on_conflict 2>$null 6>$null | Out-String).Trim())
    if ($autostash -notmatch '^(?i)true$')
    {
        scoop config autostash_on_conflict true 6>$null | Out-Null
        Write-Host 'OK: autostash_on_conflict enabled (scoop update will no longer abort on patch)' -ForegroundColor Green
    }
}

function Enable-DownloadProxy
{
    param([string]$ScoopRoot, [string]$Proxy)
    $downloadPs1 = Get-DownloadPs1 $ScoopRoot
    if (-not $downloadPs1)
    { Write-Host 'ERROR: download.ps1 not found' -ForegroundColor Red; return
    }

    if (Test-IsPatched $downloadPs1)
    {
        if (-not $SkipConfig)
        {
            scoop config GITHUB_PROXY "https://$Proxy" 6>$null | Out-Null
            Write-Host "OK: download.ps1 already patched, only updated GITHUB_PROXY = https://$Proxy (no re-injection needed)" -ForegroundColor Green
            Ensure-AutoStash
        } else
        {
            Write-Host 'INFO: download.ps1 already patched, skipping config update'
        }
        return
    }

    $orig = Get-OrigPath $downloadPs1
    Copy-Item $downloadPs1 $orig -Force
    Write-Host "OK: original file backed up -> download.ps1.sgp-orig"
    if (-not $SkipConfig)
    {
        scoop config GITHUB_PROXY "https://$Proxy" 6>$null | Out-Null
        Write-Host "OK: scoop config GITHUB_PROXY = https://$Proxy"
        Ensure-AutoStash
    }

    $content = Get-Content $downloadPs1 -Raw -Encoding UTF8
    $lines = $content -split '\r?\n'
    $funcStart = -1; $funcEnd = -1; $braceCount = 0; $inFunction = $false

    for ($i = 0; $i -lt $lines.Count; $i++)
    {
        $line = $lines[$i]
        if (-not $inFunction -and $line -match '^\s*function\s+handle_special_urls\s*\(')
        {
            $funcStart = $i; $inFunction = $true
        }
        if ($inFunction)
        {
            $opens = ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
            $closes = ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
            $braceCount += ($opens - $closes)
            if ($braceCount -le 0)
            { $funcEnd = $i; break
            }
        }
    }

    if ($funcStart -lt 0 -or $funcEnd -lt 0)
    { Write-Host 'ERROR: could not locate handle_special_urls function' -ForegroundColor Red; return
    }

    $lastReturnLine = -1
    for ($i = $funcEnd - 1; $i -gt $funcStart; $i--)
    {
        if ($lines[$i] -match '^\s*return\s+\$url\s*$')
        { $lastReturnLine = $i; break
        }
    }
    if ($lastReturnLine -lt 0)
    { Write-Host 'ERROR: could not find return $url in handle_special_urls' -ForegroundColor Red; return
    }

    $indent = ''
    if ($lines[$lastReturnLine] -match '^(\s*)')
    { $indent = $Matches[1]
    }

    $injected = @'
# === SCOOP-GITHUB-PROXY-PATCHED ===
# Automatically prefixes GitHub download URLs with a proxy, configurable via scoop config GITHUB_PROXY
$ghProxy = get_config GITHUB_PROXY
if ( $ghProxy -and $url -match '^https?://(github\.com|raw\.githubusercontent\.com|api\.github\.com|objects-githubusercontent\.com|release-assets\.githubusercontent\.com|codeload\.github\.com|gist\.githubusercontent\.com)/' ) {
    $url = "$ghProxy/$url"
}
# === END SCOOP-GITHUB-PROXY ===
'@
    $blockLines = $injected -split "`r?`n" | ForEach-Object { $indent + $_ }
    $newLines = $lines[0..($lastReturnLine - 1)] + $blockLines + $lines[$lastReturnLine..($lines.Count - 1)]
    $newContent = $newLines -join "`r`n"

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($downloadPs1, $newContent, $utf8NoBom)
    Write-Host "OK: download.ps1 patched" -ForegroundColor Green
}

# ============================================================
# Switch proxy (updates config + bucket prefix only, no re-patch)
# ============================================================

function Switch-Proxy
{
    param([string]$ScoopRoot, [string]$Proxy)
    $downloadPs1 = Get-DownloadPs1 $ScoopRoot
    if (Test-IsPatched $downloadPs1)
    {
        if (-not $SkipConfig)
        {
            scoop config GITHUB_PROXY "https://$Proxy" 6>$null | Out-Null
            Write-Host "OK: GITHUB_PROXY updated to https://$Proxy (download.ps1 does not need re-patching)" -ForegroundColor Green
        }
    } else
    { Write-Host 'INFO: download.ps1 not patched, skipping download link proxy'
    }
    Enable-BucketProxy $ScoopRoot $Proxy
}

# ============================================================
# Restore - revert download.ps1
# ============================================================

function Disable-DownloadProxy
{
    param([string]$ScoopRoot, [switch]$Silent)
    $downloadPs1 = Get-DownloadPs1 $ScoopRoot
    if (-not $downloadPs1)
    { if (-not $Silent)
        { Write-Host 'ERROR: download.ps1 not found' -ForegroundColor Red
        }; return
    }

    $orig = Get-OrigPath $downloadPs1
    if (Test-Path $orig)
    {
        Copy-Item $orig $downloadPs1 -Force
        Remove-Item $orig
        if (-not $Silent)
        { Write-Host 'OK: original download.ps1 restored from backup' -ForegroundColor Green
        }
    } elseif (Test-IsPatched $downloadPs1)
    {
        $content = Get-Content $downloadPs1 -Raw -Encoding UTF8
        $pattern = '(?sm)^\s*# === SCOOP-GITHUB-PROXY-PATCHED ===.*?# === END SCOOP-GITHUB-PROXY ===\s*\r?\n'
        $newContent = $content -replace $pattern, ''
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($downloadPs1, $newContent, $utf8NoBom)
        if (-not $Silent)
        { Write-Host 'OK: patch code removed (no backup, cleaned via regex)' -ForegroundColor Green
        }
    } else
    {
        if (-not $Silent)
        { Write-Host 'INFO: download.ps1 is not patched, nothing to do'
        }
        if ($SkipConfig)
        { return
        }
    }

    if (-not $SkipConfig)
    {
        scoop config rm GITHUB_PROXY 2>&1 6>$null | Out-Null
        Write-Host 'OK: GITHUB_PROXY config removed'
    }
}

# ============================================================
# Restore - remove bucket proxy prefix
# ============================================================

function Disable-BucketProxy
{
    param([string]$ScoopRoot)
    Write-Host '--- Restoring bucket original GitHub URLs ---'
    $map = Get-BucketRemoteUrls $ScoopRoot
    $changed = 0
    foreach ($name in ($map.Keys | Sort-Object))
    {
        $bare = Get-BareUrl $map[$name]
        if ($bare)
        {
            git -C (Join-Path (Join-Path $ScoopRoot 'buckets') $name) remote set-url origin $bare
            Write-Host " [OK] $name -> $bare" -ForegroundColor Green
            $changed++
        }
    }
    if ($changed -eq 0)
    { Write-Host ' No buckets with proxy prefix' -ForegroundColor Yellow
    }
}

# ============================================================
# Status
# ============================================================

function Show-Status
{
    param([string]$ScoopRoot)
    Write-Host ''
    Write-Host '=== Scoop GitHub proxy status ===' -ForegroundColor Cyan
    Write-Host "Scoop path: $ScoopRoot"
    $downloadPs1 = Get-DownloadPs1 $ScoopRoot
    $patched = $downloadPs1 -and (Test-IsPatched $downloadPs1)
    $hasBackup = $downloadPs1 -and (Test-Path (Get-OrigPath $downloadPs1))
    Write-Host -NoNewline 'download.ps1: '
    if ($patched)
    { Write-Host 'Patched' -ForegroundColor Green
    } else
    { Write-Host 'Not patched' -ForegroundColor Yellow
    }
    Write-Host -NoNewline 'Backup file: '
    if ($hasBackup)
    { Write-Host 'present'
    } else
    { Write-Host 'absent' -ForegroundColor Yellow
    }

    $proxy = Read-ProxyConfig
    Write-Host -NoNewline 'GITHUB_PROXY: '
    if ($proxy)
    { Write-Host $proxy
    } else
    { Write-Host 'not set' -ForegroundColor Yellow
    }

    $map = Get-BucketRemoteUrls $ScoopRoot
    $proxied = @(); $bare = @(); $other = @()
    foreach ($name in ($map.Keys | Sort-Object))
    {
        $u = $map[$name]
        if ($u -match "^https://(gh-proxy\.com|ghfast\.top)/https://github\.com/")
        { $proxied += $name
        } elseif ($u -match '^https?://github\.com/')
        { $bare += $name
        } else
        { $other += $name
        }
    }
    Write-Host -NoNewline 'buckets with proxy: '
    if ($proxied)
    { Write-Host ($proxied -join ', ')
    } else
    { Write-Host 'none' -ForegroundColor Yellow
    }
    Write-Host -NoNewline 'buckets direct: '
    if ($bare)
    { Write-Host ($bare -join ', ')
    } else
    { Write-Host 'none' -ForegroundColor Yellow
    }
    Write-Host -NoNewline 'buckets other sources: '
    if ($other)
    { Write-Host ($other -join ', ')
    } else
    { Write-Host 'none'
    }
    Write-Host ''
}

# ============================================================
# Update Scoop core and re-enable proxy
# ============================================================

function Update-ScoopAndReEnable
{
    param([string]$ScoopRoot, [string]$Proxy)
    Ensure-AutoStash
    Write-Host '--- Updating Scoop core ---'
    scoop update scoop 2>&1
    Write-Host ''

    if (-not $Proxy)
    {
        Write-Host 'ERROR: No proxy config found after update, please re-enable the proxy manually.' -ForegroundColor Red
        return
    }

    Write-Host "Using GITHUB_PROXY $Proxy, re-enabling..." -ForegroundColor Cyan
    Enable-DownloadProxy $ScoopRoot $Proxy

    Write-Host ''
    $scoopCurrentDir = Join-Path $ScoopRoot 'apps\scoop\current'
    if (Test-Path "$scoopCurrentDir\.git")
    {
        git -C $scoopCurrentDir stash clear 2>&1 | Out-Null
        Write-Host 'OK: autostash residue cleared' -ForegroundColor Green
    }
    Send-Notification 'Scoop Update Complete.'
}

# ============================================================
# Interactive menu
# ============================================================

function Select-Proxy
{
    Write-Host ''
    Write-Host ' Select proxy URL:'
    Write-Host ' 1. gh-proxy.com'
    Write-Host ' 2. ghfast.top'
    Write-Host ' 3. Custom (enter domain, without https://)'
    $c = Read-Host ' Enter [1-3]'
    switch ($c)
    {
        '1'
        { return 'gh-proxy.com'
        }
        '2'
        { return 'ghfast.top'
        }
        '3'
        { $u = Read-Host ' Proxy domain (e.g. my-proxy.example.com)'; if ($u)
            { return (Normalize-Proxy $u)
            }; Write-Host ' Invalid input' -ForegroundColor Red; return $null
        }
        default
        { Write-Host " Invalid input: $c" -ForegroundColor Red; return $null
        }
    }
}

function Show-Menu
{
    param([string]$ScoopRoot)
    Show-Status $ScoopRoot
    while ($true)
    {
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host ' Scoop GitHub Proxy Manager' -ForegroundColor Cyan
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host ' 1. Enable - replace buckets (add proxy prefix to git remote)'
        Write-Host ' 2. Enable - replace download links (patch download.ps1)'
        Write-Host ' 3. Enable - replace both'
        Write-Host ' 4. Restore - revert download.ps1 from original backup'
        Write-Host ' 5. Restore - remove bucket proxy prefix'
        Write-Host ' 6. Update Scoop and re-enable proxy'
        Write-Host ' 0. Exit'
        $choice = Read-Host ' Enter [0-6]'
        switch ($choice)
        {
            '1'
            { $p = Select-Proxy; if ($p)
                { Enable-BucketProxy $ScoopRoot $p; Send-Notification 'Scoop Proxy: bucket proxy enabled.'
                }
            }
            '2'
            { $p = Select-Proxy; if ($p)
                { Enable-DownloadProxy $ScoopRoot $p; Send-Notification 'Scoop Proxy: download proxy enabled.'
                }
            }
            '3'
            { $p = Select-Proxy; if ($p)
                { Enable-DownloadProxy $ScoopRoot $p; Enable-BucketProxy $ScoopRoot $p; Send-Notification 'Scoop Proxy: proxy enabled (buckets + download).'
                }
            }
            '4'
            { Disable-DownloadProxy $ScoopRoot; Send-Notification 'Scoop Proxy: download proxy restored.'
            }
            '5'
            { Disable-BucketProxy $ScoopRoot; Send-Notification 'Scoop Proxy: bucket proxy restored.'
            }
            '6'
            { $p = Read-ProxyConfig; if (-not $p)
                { $p = Select-Proxy
                }; if ($p)
                { Update-ScoopAndReEnable $ScoopRoot $p
                }
            }
            '0'
            { return
            }
            default
            { Write-Host " Invalid input: $choice" -ForegroundColor Red
            }
        }
    }
}

# ============================================================
# Main
# ============================================================

function Main
{
    $script:ScoopDir = if ($ScoopDir)
    { $ScoopDir
    } else
    { Find-ScoopDir
    }
    if (-not $script:ScoopDir -or -not (Test-Path $script:ScoopDir))
    {
        Write-Host 'ERROR: Scoop installation directory not found (set SCOOP env var or use -ScoopDir)' -ForegroundColor Red
        exit 1
    }

    if ($Status)
    { Show-Status $script:ScoopDir; return
    }

    # Handle -Update argument
    if ($Update)
    {
        # If no -Proxy on command line, try to read from config
        if (-not $Proxy)
        { $Proxy = Read-ProxyConfig
        }
        if (-not $Proxy)
        {
            Write-Host "ERROR: No proxy specified and GITHUB_PROXY not found in config." -ForegroundColor Red
            Write-Host "Usage: .\scoop-proxy.ps1 -Update -Proxy ghfast.top" -ForegroundColor Yellow
            return
        }
        $Proxy = Normalize-Proxy $Proxy
        Update-ScoopAndReEnable $script:ScoopDir $Proxy
        return
    }

    if ($Action)
    {
        if ($Proxy)
        { $Proxy = Normalize-Proxy $Proxy
        }
        switch ($Action)
        {
            'enable-bucket'
            { if (-not $Proxy)
                { Write-Host 'ERROR: -Proxy argument required' -ForegroundColor Red; return
                }; Enable-BucketProxy $script:ScoopDir $Proxy
            }
            'enable-download'
            { if (-not $Proxy)
                { Write-Host 'ERROR: -Proxy argument required' -ForegroundColor Red; return
                }; Enable-DownloadProxy $script:ScoopDir $Proxy
            }
            'enable-both'
            { if (-not $Proxy)
                { Write-Host 'ERROR: -Proxy argument required' -ForegroundColor Red; return
                }; Enable-DownloadProxy $script:ScoopDir $Proxy; Enable-BucketProxy $script:ScoopDir $Proxy
            }
            'switch-proxy'
            { if (-not $Proxy)
                { Write-Host 'ERROR: -Proxy argument required' -ForegroundColor Red; return
                }; Switch-Proxy $script:ScoopDir $Proxy
            }
            'restore-download'
            { Disable-DownloadProxy $script:ScoopDir
            }
            'restore-bucket'
            { Disable-BucketProxy $script:ScoopDir
            }
        }
        $knownActions = @('enable-bucket', 'enable-download', 'enable-both', 'switch-proxy', 'restore-download', 'restore-bucket')
        if ($knownActions -contains $Action)
        { Send-Notification "Scoop Proxy: $Action completed."
        }
        return
    }

    Show-Menu $script:ScoopDir
}

if ($MyInvocation.InvocationName -ne '.')
{ Main
}
