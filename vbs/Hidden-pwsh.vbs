' ============================================================
' Hidden-pwsh.vbs - Generic hidden PowerShell launcher
' Usage:
'   wscript Hidden-pwsh.vbs "C:\path\to\script.ps1"
' ============================================================

Option Explicit

' ---- Change PowerShell executable here ----
' PowerShell 7: use "pwsh.exe"
' Built-in Windows PowerShell: use "powershell.exe"
Const PWSH_EXE = "pwsh.exe"

Dim WshShell, fso, target, cmd
Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' ---- Check arguments ----
If WScript.Arguments.Count = 0 Then
    WScript.Echo "Error: Missing argument." & vbCrLf & _
                 "Usage: wscript Hidden-pwsh.vbs ""C:\path\to\script.ps1"""
    WScript.Quit 1
End If

target = WScript.Arguments(0)

If Not fso.FileExists(target) Then
    WScript.Echo "Error: File not found - " & target
    WScript.Quit 1
End If

' ---- Run hidden ----
cmd = PWSH_EXE & " -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & target & """"

' 0 = hidden window, True = wait for PowerShell to finish
WshShell.Run cmd, 0, True
