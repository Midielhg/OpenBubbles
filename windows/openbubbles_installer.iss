; Installer for this fork's Windows desktop app (Inno Setup 6).
; Build the app first (bash scripts/build-windows-local.sh), then:
;   ISCC.exe /DMyAppVersion=1.15.0 windows\openbubbles_installer.iss
; The installer lands in build\installer\.

#define MyAppName "OpenBubbles Desktop"
#ifndef MyAppVersion
  #define MyAppVersion "1.15.0"
#endif
#define MyAppPublisher "Midielhg"
#define MyAppURL "https://github.com/Midielhg/OpenBubbles"
#define MyAppExeName "bluebubbles_app.exe"
#define ProjectRoot ".."

#include "CodeDependencies.iss"

[Setup]
; Unique to this fork, so it never upgrades or removes an upstream BlueBubbles/OpenBubbles install.
AppId={{43E95C50-9DA6-4A84-8172-8BB112A95F3F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
; per-user install by default (no admin prompt); the dialog still offers all-users
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#ProjectRoot}\build\installer
OutputBaseFilename=OpenBubbles-Desktop-Setup-{#MyAppVersion}
SetupIconFile={#ProjectRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Code]
function InitializeSetup: Boolean;
begin
  if not IsMsiProductInstalled('{36F68A90-239C-34DF-B58C-64B30153CE35}', PackVersionComponents(14, 40, 33810, 0)) then begin
    Dependency_Add('vcredist2022 (x64).exe',
      '/passive /norestart',
      'Visual C++ 2015-2022 Redistributable (x64)',
      'https://aka.ms/vs/17/release/vc_redist.x64.exe',
      '', False, False);
  end;
  Result := True;
end;

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#ProjectRoot}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Classes\imessage"; ValueType: "string"; ValueData: "URL:iMessage Protocol"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\imessage"; ValueType: "string"; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\imessage\DefaultIcon"; ValueType: "string"; ValueData: "{app}\{#MyAppExeName},0"
Root: HKA; Subkey: "Software\Classes\imessage\shell\open\command"; ValueType: "string"; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
