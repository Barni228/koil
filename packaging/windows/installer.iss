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
SetupIconFile=koil.ico
; Tells Explorer about the Open With entries below.
ChangesAssociations=yes
OutputDir={#OutputDir}
OutputBaseFilename=Koil-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Koil shows in Open With for every file (it opens any that is UTF-8 text,
; which no extension says), but no file type is given to it, so it's never
; the default app. HKA is the current user's keys, or the machine's in an
; all-users install.
[Registry]
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "Koil"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\*\OpenWithList\{#AppExe}"; Flags: uninsdeletekey

[Icons]
Name: "{autoprograms}\Koil"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\Koil"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,Koil}"; Flags: nowait postinstall skipifsilent
