# 1. 检查管理员权限，如果没有则自动提权
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
    # 使用 pwsh（PowerShell 7+）重新运行自身并请求管理员权限
    Start-Process pwsh.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# 2. 强制关闭 HWiNFO64 进程（忽略未找到进程的报错）
Stop-Process -Name "HWiNFO64" -Force -ErrorAction SilentlyContinue

# 3. 等待 3 秒
Start-Sleep -Seconds 3

# 4. 启动目标程序
Start-Process -FilePath "E:\Software\Scoop\apps\hwinfo\current\HWiNFO64.EXE"
