Set WshShell = CreateObject("WScript.Shell") 
WshShell.Run chr(34) & "LAUNCH_t.bat" & Chr(34), 0
Set WshShell = Nothing