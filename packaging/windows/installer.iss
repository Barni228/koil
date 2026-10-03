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

; Koil shows in Open With for text files, like vim-edit: a ProgID, listed in
; each extension's OpenWithProgids (which the Open With menu shows), and the
; same extensions as the app's SupportedTypes (so "Choose another app" offers
; it only for those). It opens any UTF-8 text, but no extension says a file is
; that, so these are the usual text and source code ones. No extension's
; default is set, so Koil is never the default app. HKA is the current user's
; keys, or the machine's in an all-users install. A `\` ends a line that goes
; on.
#dim Exts[107] { \
  ".txt", ".text", ".md", ".markdown", ".rst", ".adoc", ".org", ".tex", \
  ".log", ".csv", ".tsv", ".json", ".jsonc", ".json5", ".toml", ".yaml", \
  ".yml", ".xml", ".ini", ".cfg", ".conf", ".config", ".env", ".properties", \
  ".editorconfig", ".gitignore", ".gitattributes", ".rs", ".c", ".h", ".cc", \
  ".cpp", ".cxx", ".hpp", ".hh", ".hxx", ".cs", ".fs", ".java", ".kt", \
  ".kts", ".scala", ".go", ".swift", ".m", ".mm", ".zig", ".nim", ".d", \
  ".py", ".pyi", ".rb", ".pl", ".pm", ".php", ".lua", ".r", ".jl", ".dart", \
  ".ex", ".exs", ".erl", ".hs", ".ml", ".mli", ".clj", ".lisp", ".el", \
  ".vim", ".js", ".mjs", ".cjs", ".ts", ".mts", ".cts", ".jsx", ".tsx", \
  ".vue", ".svelte", ".html", ".htm", ".css", ".scss", ".sass", ".less", \
  ".sh", ".bash", ".zsh", ".fish", ".ps1", ".psm1", ".psd1", ".bat", ".cmd", \
  ".sql", ".graphql", ".proto", ".cmake", ".mk", ".gradle", ".qml", ".qrc", \
  ".ui", ".iss", ".nsi", ".diff", ".patch" \
}
#define I
#sub ExtEntries
Root: HKA; Subkey: "Software\Classes\{#Exts[I]}\OpenWithProgids"; ValueType: string; ValueName: "Koil.Text"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: "{#Exts[I]}"; ValueData: ""
#endsub

[Registry]
Root: HKA; Subkey: "Software\Classes\Koil.Text"; ValueType: string; ValueData: "Text Document"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Koil.Text\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"
Root: HKA; Subkey: "Software\Classes\Koil.Text\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "Koil"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""
#for {I = 0; I < DimOf(Exts); I++} ExtEntries

[Icons]
Name: "{autoprograms}\Koil"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\Koil"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,Koil}"; Flags: nowait postinstall skipifsilent
