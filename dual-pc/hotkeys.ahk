#Requires AutoHotkey v2.0
#SingleInstance Force

InstallRoot := "C:\Program Files\DualPcProfiles"
PowerShell := "C:\Program Files\PowerShell\7\pwsh.exe"
EntryPoint := InstallRoot "\dual-pc.ps1"

ResetState() {
    global PowerShell, EntryPoint
    command := '"' PowerShell '" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' EntryPoint '" -Command ResetState'
    Run(command, , "Hide")
}

PowerBroadcast(wParam, lParam, msg, hwnd) {
    if (wParam = 7 || wParam = 18)
        ResetState()
}

InvokeProfile(profile, force := false) {
    global PowerShell, EntryPoint
    forceArgument := force ? " -Force" : ""
    command := '"' PowerShell '" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' EntryPoint '" -Command Request -Profile ' profile forceArgument
    Run(command, , "Hide")
}

^!F9::InvokeProfile("PC")
^!F10::InvokeProfile("mix")
^!F12::InvokeProfile("NB")

+^!F9::InvokeProfile("PC", true)
+^!F10::InvokeProfile("mix", true)
+^!F12::InvokeProfile("NB", true)

OnMessage(0x218, PowerBroadcast)
ResetState()
