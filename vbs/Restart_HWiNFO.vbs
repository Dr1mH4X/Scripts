Set WshShell = CreateObject("WScript.Shell")

' 强制关闭目标程序
WshShell.Run "taskkill /F /IM HWiNFO64.EXE", 0, True

' 等待3秒
WScript.Sleep 3000

' 启动目标程序
WshShell.Run """E:\Software\Scoop\apps\hwinfo\current\HWiNFO64.EXE""", 0, False