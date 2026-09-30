; Inno Setup script for the Koil Windows installer.
; Built by scripts/package-windows.ps1, which passes AppVersion, SourceDir
; (the windeployqt output) and OutputDir on the command line.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppExe "koil.exe"

[Setup]
AppId={{04D1D035-1651-4B8E-9EB3-03E3840BCC97}
AppName=Koil
AppVersion={#AppVersion}
AppVerName=Koil {#AppVersion}
AppPublisher=Barni228
AppPublisherURL=https://github.com/Barni228/koil
DefaultDirName={autopf}\Koil
DefaultGroupName=Koil
DisableProgramGroupPage=yes
; Install per user without admin rights; the wizard offers an all-users install.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}
OutputDir={#OutputDir}
OutputBaseFilename=Koil-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Koil"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\Koil"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,Koil}"; Flags: nowait postinstall skipifsilent
