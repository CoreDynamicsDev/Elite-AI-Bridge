#define MyAppName "Elite AI Bridge"
#define MyAppVersion "2.0.0"
#define MyAppPublisher "Elite AI Bridge"
#define MyAppURL "https://ko-fi.com/eliteaibridge"
; 2.0.0: shortcuts run the runtime's own pythonw.exe (signed by the Python Software Foundation)
; with frontend\main.py. No launcher program of ours: a .vbs is being phased out of Windows,
; and a small custom launcher EXE was flagged by antivirus heuristics.
#define RuntimePythonW "{localappdata}\EliteAIBridge\runtime\.venv\Scripts\pythonw.exe"

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
OutputBaseFilename=Elite_AI_Bridge_Setup_2.0.0
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
; The tested 2.0.0 payload is installed intact. The .venv is created after file copy.
Source: "Elite AI Bridge\*"; DestDir: "{app}"; Excludes: "__pycache__,*.pyc,Launch_Elite_AI_Bridge.vbs,Elite AI Bridge.exe"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "requirements.txt"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{localappdata}\EliteAIBridge"

[Icons]
; AppUserModelID matches main.py so a pinned shortcut and the running Bridge share one taskbar button.
Name: "{autoprograms}\Elite AI Bridge"; Filename: "{#RuntimePythonW}"; Parameters: """{app}\frontend\main.py"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\Elite_AI_Bridge.ico"; AppUserModelID: "CoreDynamicsDev.EliteAIBridge"
Name: "{autoprograms}\Elite AI Bridge Documentation"; Filename: "{app}\docs\README.md"; WorkingDir: "{app}\docs"
Name: "{autoprograms}\Privacy and API Keys"; Filename: "{app}\docs\PRIVACY_AND_API_KEYS.md"; WorkingDir: "{app}\docs"
Name: "{autodesktop}\Elite AI Bridge"; Filename: "{#RuntimePythonW}"; Parameters: """{app}\frontend\main.py"""; WorkingDir: "{app}"; IconFilename: "{app}\assets\Elite_AI_Bridge.ico"; AppUserModelID: "CoreDynamicsDev.EliteAIBridge"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: checkedonce

[Run]
; The private runtime is prepared by PrepareRuntime in the Code section (ssPostInstall)
; so the setup window can show live progress from Installer_Runtime_Setup.ps1 (2.0.0).
Filename: "{#RuntimePythonW}"; Parameters: """{app}\frontend\main.py"""; WorkingDir: "{app}"; Description: "Launch Elite AI Bridge"; Flags: nowait postinstall skipifsilent; Check: RuntimeReady

[InstallDelete]
; older launchers (1.x .vbs, and the test EXE), replaced by shortcuts to pythonw.exe
Type: files; Name: "{app}\Launch_Elite_AI_Bridge.vbs"
Type: files; Name: "{app}\Elite AI Bridge.exe"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\.venv"

[Code]
// 2.0.0: live progress while the runtime is prepared. Installer_Runtime_Setup.ps1 writes one
// status line ("Step N of 4: detail", "All set...", "Setup failed: ...") to runtime_status.txt
// and "OK" / "FAIL ..." to runtime_done.txt. Exec waits for PowerShell while keeping the window
// responsive; a timer turns the status line into a four-item checklist with a detail line
// under it, and shows the elapsed time, every half second.
function SetTimer(hWnd: LongWord; nIDEvent: LongWord; uElapse: LongWord; lpTimerFunc: LongWord): LongWord;
  external 'SetTimer@user32.dll stdcall';
function KillTimer(hWnd: LongWord; uIDEvent: LongWord): Boolean;
  external 'KillTimer@user32.dll stdcall';
function GetTickCount: LongWord;
  external 'GetTickCount@kernel32.dll stdcall';

var
  RuntimeStartTick: LongWord;
  RuntimeStatusFile: String;
  CheckLabels: array[0..3] of TNewStaticText;
  CheckNames: array[0..3] of String;
  DetailLabel: TNewStaticText;
  TimeLabel: TNewStaticText;
  CurrentStep: Integer;

function InitializeSetup(): Boolean;
begin
  Result := True;
end;

// the "Launch Elite AI Bridge" box only shows when the runtime finished setting up
function RuntimeReady(): Boolean;
begin
  Result := FileExists(ExpandConstant('{localappdata}\EliteAIBridge\runtime\.ready')) and
            FileExists(ExpandConstant('{#RuntimePythonW}'));
end;

// 1..4 = that step is running (the ones before it are done); 5 = all done; 0 = not started
procedure ShowStep(N: Integer);
var
  I: Integer;
begin
  CurrentStep := N;
  for I := 0 to 3 do
  begin
    if I < N - 1 then
    begin
      CheckLabels[I].Caption := #$2713 + '   ' + CheckNames[I];
      CheckLabels[I].Font.Style := [];
      CheckLabels[I].Font.Color := $00238C23;
    end
    else if I = N - 1 then
    begin
      CheckLabels[I].Caption := #$25BA + '   ' + CheckNames[I];
      CheckLabels[I].Font.Style := [fsBold];
      CheckLabels[I].Font.Color := clWindowText;
    end
    else
    begin
      CheckLabels[I].Caption := #$25CB + '   ' + CheckNames[I];
      CheckLabels[I].Font.Style := [];
      CheckLabels[I].Font.Color := clGrayText;
    end;
  end;
end;

procedure BuildChecklist();
var
  I, Y: Integer;
  Page: TWinControl;
begin
  CheckNames[0] := 'Python';
  CheckNames[1] := 'Bridge components (about 300 MB)';
  CheckNames[2] := 'Checking the components';
  CheckNames[3] := 'The ship''s voice';
  Page := WizardForm.InstallingPage;
  Y := WizardForm.StatusLabel.Top;
  WizardForm.StatusLabel.Visible := False;
  WizardForm.FilenameLabel.Visible := False;
  for I := 0 to 3 do
  begin
    CheckLabels[I] := TNewStaticText.Create(WizardForm);
    CheckLabels[I].Parent := Page;
    CheckLabels[I].Left := WizardForm.StatusLabel.Left + ScaleX(4);
    CheckLabels[I].Top := Y;
    CheckLabels[I].Width := WizardForm.StatusLabel.Width - ScaleX(4);
    CheckLabels[I].AutoSize := False;
    CheckLabels[I].Height := ScaleY(20);
    Y := Y + ScaleY(24);
  end;
  DetailLabel := TNewStaticText.Create(WizardForm);
  DetailLabel.Parent := Page;
  DetailLabel.Left := WizardForm.StatusLabel.Left + ScaleX(24);
  DetailLabel.Top := Y + ScaleY(4);
  DetailLabel.Width := WizardForm.StatusLabel.Width - ScaleX(24);
  DetailLabel.AutoSize := False;
  DetailLabel.WordWrap := True;
  DetailLabel.Height := ScaleY(32);
  DetailLabel.Font.Color := clGrayText;
  WizardForm.ProgressGauge.Top := DetailLabel.Top + DetailLabel.Height + ScaleY(8);
  TimeLabel := TNewStaticText.Create(WizardForm);
  TimeLabel.Parent := Page;
  TimeLabel.Left := WizardForm.StatusLabel.Left;
  TimeLabel.Top := WizardForm.ProgressGauge.Top + WizardForm.ProgressGauge.Height + ScaleY(8);
  TimeLabel.Width := WizardForm.StatusLabel.Width;
  TimeLabel.AutoSize := False;
  TimeLabel.WordWrap := True;
  TimeLabel.Height := ScaleY(32);
  ShowStep(1);
  DetailLabel.Caption := 'Getting ready...';
end;

procedure RuntimeProgressTick(Wnd: LongWord; Msg: LongWord; TimerID: LongWord; Time: LongWord);
var
  S: AnsiString;
  Line: String;
  N, P: Integer;
  Secs: LongWord;
begin
  if LoadStringFromFile(RuntimeStatusFile, S) then
  begin
    Line := Trim(String(S));
    if Line <> '' then
    begin
      if Copy(Line, 1, 5) = 'Step ' then
      begin
        N := StrToIntDef(Copy(Line, 6, 1), CurrentStep);
        if (N >= 1) and (N <= 4) and (N <> CurrentStep) then ShowStep(N);
        P := Pos(': ', Line);
        if P > 0 then Line := Copy(Line, P + 2, Length(Line));
        DetailLabel.Caption := Line;
      end
      else if Copy(Line, 1, 7) = 'All set' then
      begin
        ShowStep(5);
        DetailLabel.Caption := Line;
      end
      else
        DetailLabel.Caption := Line;
    end;
  end;
  Secs := (GetTickCount - RuntimeStartTick) div 1000;
  TimeLabel.Caption := Format('%d:%.2d elapsed. The first install takes about 3 to 10 minutes. Please keep this window open.', [Secs div 60, Secs mod 60]);
end;

procedure PrepareRuntime();
var
  LogDir, DoneFile, Params, Msg: String;
  Done: AnsiString;
  ResultCode: Integer;
  TimerID: LongWord;
  Ok: Boolean;
begin
  LogDir := ExpandConstant('{localappdata}\EliteAIBridge\logs');
  ForceDirectories(LogDir);
  RuntimeStatusFile := LogDir + '\runtime_status.txt';
  DoneFile := LogDir + '\runtime_done.txt';
  DeleteFile(RuntimeStatusFile);
  DeleteFile(DoneFile);

  BuildChecklist();
  WizardForm.ProgressGauge.Style := npbstMarquee;
  RuntimeStartTick := GetTickCount;
  TimerID := SetTimer(0, 0, 500, CreateCallback(@RuntimeProgressTick));

  Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\Installer_Runtime_Setup.ps1') + '"';
  Ok := Exec('powershell.exe', Params, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, ResultCode);

  KillTimer(0, TimerID);
  WizardForm.ProgressGauge.Style := npbstNormal;
  WizardForm.ProgressGauge.Position := WizardForm.ProgressGauge.Max;

  Done := '';
  LoadStringFromFile(DoneFile, Done);
  if Ok and (ResultCode = 0) and (Pos('OK', String(Done)) = 1) then
  begin
    ShowStep(5);
    DetailLabel.Caption := 'All set. Elite AI Bridge is ready.';
    TimeLabel.Caption := '';
  end
  else
  begin
    Msg := Trim(String(Done));
    if Pos('FAIL ', Msg) = 1 then Msg := Copy(Msg, 6, Length(Msg));
    if Msg = '' then Msg := 'The setup step stopped unexpectedly (code ' + IntToStr(ResultCode) + ').';
    DetailLabel.Caption := 'Setup did not finish: ' + Msg;
    DetailLabel.Font.Color := clRed;
    MsgBox('Elite AI Bridge is installed, but its first-time setup did not finish:' + #13#10#13#10 + Msg + #13#10#13#10 +
      'Check your internet connection, then run this installer again to finish the setup.' + #13#10#13#10 +
      'Details: ' + LogDir + '\runtime_setup.log', mbError, MB_OK);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    PrepareRuntime();
end;
