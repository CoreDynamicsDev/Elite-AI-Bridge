#define MyAppName "Elite AI Bridge"
#define MyAppVersion "1.0"
#define MyAppPublisher "Elite AI Bridge"
#define MyAppURL "https://ko-fi.com/eliteaibridge"
#define MyAppExeName "Launch_Elite_AI_Bridge.vbs"

[Setup]
AppId={{9B47A62E-90D8-4A19-A838-EFAB10000001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\Elite AI Bridge
DefaultGroupName=Elite AI Bridge
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=Output
OutputBaseFilename=Elite_AI_Bridge_Setup_1.0
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
SetupIconFile=Elite AI Bridge\assets\Elite_AI_Bridge.ico
UninstallDisplayIcon={app}\assets\Elite_AI_Bridge.ico
UninstallDisplayName=Elite AI Bridge
CreateUninstallRegKey=yes
ChangesEnvironment=no
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
LicenseFile=LICENSE.txt
InfoBeforeFile=README_FIRST.txt

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
; The proven RC1 payload is installed intact. The .venv is created after file copy.
Source: "Elite AI Bridge\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "requirements.txt"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{localappdata}\EliteAIBridge"

[Icons]
Name: "{autoprograms}\Elite AI Bridge"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\Launch_Elite_AI_Bridge.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\Elite_AI_Bridge.ico"
Name: "{autoprograms}\Elite AI Bridge Documentation"; Filename: "{app}\docs\README.md"; WorkingDir: "{app}\docs"
Name: "{autoprograms}\Privacy and API Keys"; Filename: "{app}\docs\PRIVACY_AND_API_KEYS.md"; WorkingDir: "{app}\docs"
Name: "{autodesktop}\Elite AI Bridge"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\Launch_Elite_AI_Bridge.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\Elite_AI_Bridge.ico"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Run]
; Prepare the private runtime using the same tested PowerShell bootstrap logic,
; but skip its file-copy/shortcut phase because Inno has already installed files.
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Installer_Runtime_Setup.ps1"""; StatusMsg: "Preparing Elite AI Bridge runtime..."; Flags: runhidden waituntilterminated
Filename: "{sys}\wscript.exe"; Parameters: """{app}\Launch_Elite_AI_Bridge.vbs"""; Description: "Launch Elite AI Bridge"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\.venv"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
