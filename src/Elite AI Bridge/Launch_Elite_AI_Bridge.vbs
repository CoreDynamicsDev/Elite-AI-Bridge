Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
ready = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\EliteAIBridge\runtime\.ready"
pythonw = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\EliteAIBridge\runtime\.venv\Scripts\pythonw.exe"
If Not fso.FileExists(ready) Or Not fso.FileExists(pythonw) Then
    MsgBox "Elite AI Bridge runtime is not ready yet." & vbCrLf & vbCrLf & _
           "Run START_HERE.bat once to install/repair the runtime and Supertonic voice.", 48, "Elite AI Bridge"
    WScript.Quit 2
End If
shell.CurrentDirectory = root
cmd = """" & pythonw & """ """ & root & "\frontend\main.py" & """"
shell.Run cmd, 0, False
