#ifndef PackageVersion
  #error PackageVersion is required
#endif
#ifndef StageRoot
  #error StageRoot is required
#endif
#ifndef ReleaseRoot
  #error ReleaseRoot is required
#endif

[Setup]
AppId={{F412770B-CBCB-42D7-854B-63604883235A}
AppName=Codex Monitor HUD
AppVersion={#PackageVersion}
AppPublisher=Codex Monitor HUD Contributors / wassamriehlei
AppPublisherURL=https://github.com/wassamriehlei/codex-monitor-hud
AppSupportURL=https://github.com/wassamriehlei/codex-monitor-hud/issues
AppUpdatesURL=https://github.com/wassamriehlei/codex-monitor-hud/releases
DefaultDirName={localappdata}\Programs\CodexMonitorHUDInstaller
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#ReleaseRoot}
OutputBaseFilename=CodexMonitorHUD-Setup-{#PackageVersion}-windows-x64
SetupIconFile={#StageRoot}\assets\codex-monitor-hud.ico
UninstallDisplayIcon={app}\codex-monitor-hud.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
LicenseFile={#StageRoot}\LICENSE
CloseApplications=no
RestartApplications=no

[Files]
Source: "{#StageRoot}\*"; DestDir: "{tmp}\payload"; Flags: recursesubdirs createallsubdirs dontcopy
Source: "{#StageRoot}\assets\codex-monitor-hud.ico"; DestDir: "{app}"
Source: "{#StageRoot}\scripts\uninstall.ps1"; DestDir: "{app}\scripts"
Source: "{#StageRoot}\src\MonitorHud.Startup.psm1"; DestDir: "{app}\src"

[Run]
Filename: "{%USERPROFILE}\plugins\codex-monitor-hud\CodexMonitorHUD-Settings.exe"; Parameters: "--plugin-root ""{%USERPROFILE}\plugins\codex-monitor-hud"""; Description: "Open Codex Monitor HUD"; Flags: postinstall nowait skipifsilent

[Code]
var
  PayloadInstalled: Boolean;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  if PayloadInstalled then exit;
  WizardForm.StatusLabel.Caption := 'Validating and installing Codex Monitor HUD...';
  ExtractTemporaryFiles('{tmp}\payload\*');
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\payload\scripts\install-exe.ps1') + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Result := 'Installation process did not start.'
  else if ResultCode <> 0 then
    Result := 'Installation validation failed. See %LOCALAPPDATA%\CodexMonitorHUD\installer.log.'
  else
    PayloadInstalled := True;
end;

function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\scripts\uninstall.ps1') + '"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := Result and (ResultCode = 0);
  if not Result then MsgBox('Please close Codex Monitor HUD and retry uninstalling. Settings are preserved.', mbError, MB_OK);
end;
