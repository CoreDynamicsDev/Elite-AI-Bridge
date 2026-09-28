Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = """" & root & "\.venv\Scripts\pythonw.exe"" """ & root & "\frontend\main.py"""
shell.CurrentDirectory = root
shell.Run cmd, 0, False
