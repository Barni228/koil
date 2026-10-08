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
Name: "openinkoil"; Description: "Add ""Open in Koil"" to folders' right-click menu"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Koil shows in Open With for text files, like vim-edit: a ProgID, listed in
; each extension's OpenWithProgids (which the Open With menu shows), and the
; same extensions as the app's SupportedTypes (so "Choose another app" offers
; it only for those). It opens any UTF-8 text, but no extension says a file is
; that, so these are the usual text and source code ones (the same as
; packaging/macos/Info.plist's), and "." for a file with no extension (like
; Makefile, LICENSE or an empty file), which Windows looks up under the
; key ".". A dotfile's name (.gitignore) is its extension here. No
; extension's default is set, so Koil is never the default app. HKA is the
; current user's keys, or the machine's in an all-users install. A `\` ends
; a line that goes on.
#dim Exts[378] { \
  ".", ".txt", ".text", ".md", ".markdown", ".mdown", ".mkd", ".mdx", \
  ".rst", ".adoc", ".asciidoc", ".org", ".tex", ".ltx", ".sty", ".cls", \
  ".bib", ".typ", ".log", ".nfo", ".srt", ".vtt", ".ics", ".vcf", ".po", \
  ".pot", ".diff", ".patch", ".rej", ".ipynb", ".http", ".pem", ".json", \
  ".jsonc", ".json5", ".jsonl", ".ndjson", ".geojson", ".webmanifest", \
  ".toml", ".yaml", ".yml", ".xml", ".ini", ".cfg", ".conf", ".config", \
  ".cnf", ".env", ".properties", ".lock", ".ron", ".kdl", ".hcl", ".tf", \
  ".tfvars", ".nix", ".csv", ".tsv", ".sql", ".graphql", ".gql", ".proto", \
  ".thrift", ".avsc", ".prisma", ".puml", ".plantuml", ".mmd", ".mermaid", \
  ".gv", ".html", ".htm", ".xhtml", ".xsd", ".xsl", ".xslt", ".dtd", ".rss", \
  ".atom", ".svg", ".xaml", ".resx", ".xlf", ".xliff", ".nuspec", \
  ".manifest", ".sln", ".csproj", ".vcxproj", ".fsproj", ".vbproj", \
  ".props", ".targets", ".filters", ".reg", ".inf", ".rc", ".gitignore", \
  ".gitattributes", ".gitmodules", ".gitconfig", ".gitkeep", ".mailmap", \
  ".editorconfig", ".envrc", ".bashrc", ".bash_profile", ".bash_logout", \
  ".zshrc", ".zprofile", ".zshenv", ".profile", ".inputrc", ".vimrc", \
  ".npmrc", ".nvmrc", ".yarnrc", ".prettierrc", ".eslintrc", ".babelrc", \
  ".dockerignore", ".npmignore", ".prettierignore", ".eslintignore", \
  ".clang-format", ".clang-tidy", ".clangd", ".tool-versions", ".htaccess", \
  ".flake8", ".pylintrc", ".coveragerc", ".desktop", ".service", \
  ".xcconfig", ".pbxproj", ".rs", ".c", ".h", ".cc", ".cpp", ".cxx", ".c++", \
  ".hpp", ".hh", ".hxx", ".h++", ".inl", ".ipp", ".tpp", ".ixx", ".cppm", \
  ".cu", ".cuh", ".m", ".mm", ".def", ".cs", ".csx", ".vb", ".fs", ".fsi", \
  ".fsx", ".java", ".kt", ".kts", ".scala", ".sc", ".sbt", ".groovy", \
  ".gvy", ".gradle", ".clj", ".cljs", ".cljc", ".edn", ".go", ".mod", \
  ".sum", ".zig", ".zon", ".nim", ".nims", ".nimble", ".d", ".di", ".odin", \
  ".v", ".vsh", ".hare", ".cr", ".gleam", ".swift", ".dart", ".jl", ".r", \
  ".rmd", ".qmd", ".lua", ".luau", ".fnl", ".tcl", ".awk", ".sed", ".pl", \
  ".pm", ".raku", ".php", ".phtml", ".py", ".pyi", ".pyw", ".pyx", ".pxd", \
  ".rb", ".rbs", ".rake", ".gemspec", ".ru", ".erl", ".hrl", ".ex", ".exs", \
  ".eex", ".heex", ".leex", ".hs", ".lhs", ".cabal", ".elm", ".purs", ".ml", \
  ".mli", ".mll", ".mly", ".re", ".rei", ".res", ".resi", ".sml", ".lisp", \
  ".lsp", ".el", ".scm", ".ss", ".rkt", ".hy", ".janet", ".lean", ".agda", \
  ".idr", ".pas", ".pp", ".dpr", ".lpr", ".f", ".f90", ".f95", ".f03", \
  ".for", ".ada", ".adb", ".ads", ".cob", ".cbl", ".asm", ".s", ".nasm", \
  ".ll", ".wat", ".wast", ".sol", ".move", ".vala", ".vapi", ".hx", ".as", \
  ".coffee", ".litcoffee", ".ahk", ".vbs", ".applescript", ".sh", ".bash", \
  ".zsh", ".fish", ".ksh", ".csh", ".tcsh", ".nu", ".xsh", ".ps1", ".psm1", \
  ".psd1", ".bat", ".cmd", ".command", ".js", ".mjs", ".cjs", ".jsx", ".ts", \
  ".mts", ".cts", ".tsx", ".vue", ".svelte", ".astro", ".ejs", ".hbs", \
  ".handlebars", ".mustache", ".jinja", ".jinja2", ".j2", ".njk", ".liquid", \
  ".twig", ".haml", ".slim", ".pug", ".jade", ".erb", ".css", ".scss", \
  ".sass", ".less", ".styl", ".pcss", ".glsl", ".vert", ".frag", ".geom", \
  ".comp", ".tesc", ".tese", ".hlsl", ".wgsl", ".metal", ".shader", \
  ".gdshader", ".gd", ".tscn", ".tres", ".sv", ".svh", ".vh", ".vhd", \
  ".vhdl", ".cmake", ".mk", ".mak", ".make", ".ninja", ".gn", ".gni", \
  ".bzl", ".bazel", ".star", ".build", ".just", ".pro", ".pri", ".prf", \
  ".qbs", ".qrc", ".qml", ".ui", ".iss", ".nsi", ".nsh", ".wxs", ".spec", \
  ".ebuild", ".dockerfile", ".containerfile", ".vim" \
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
; "Open in Koil" on a folder's right-click menu, a folder window's
; background's (the folder it shows) and a drive's, which lists it. On
; Windows 11 it's under "Show more options": its own menu takes only
; packaged apps' commands. Koil reads a drive's root, "C:\" quoted, which
; comes as C:" (see command_line_path in src/document.rs). Reinstalling
; without the task takes it away.
Root: HKA; Subkey: "Software\Classes\Directory\shell\Koil"; ValueType: string; ValueData: "Open in Koil"; Flags: uninsdeletekey; Tasks: openinkoil
Root: HKA; Subkey: "Software\Classes\Directory\shell\Koil"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#AppExe},0"; Tasks: openinkoil
Root: HKA; Subkey: "Software\Classes\Directory\shell\Koil\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: openinkoil
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\Koil"; ValueType: string; ValueData: "Open in Koil"; Flags: uninsdeletekey; Tasks: openinkoil
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\Koil"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#AppExe},0"; Tasks: openinkoil
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\Koil\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%V"""; Tasks: openinkoil
Root: HKA; Subkey: "Software\Classes\Drive\shell\Koil"; ValueType: string; ValueData: "Open in Koil"; Flags: uninsdeletekey; Tasks: openinkoil
Root: HKA; Subkey: "Software\Classes\Drive\shell\Koil"; ValueType: string; ValueName: "Icon"; ValueData: "{app}\{#AppExe},0"; Tasks: openinkoil
Root: HKA; Subkey: "Software\Classes\Drive\shell\Koil\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""; Tasks: openinkoil
Root: HKA; Subkey: "Software\Classes\Directory\shell\Koil"; ValueType: none; Flags: deletekey; Tasks: not openinkoil
Root: HKA; Subkey: "Software\Classes\Directory\Background\shell\Koil"; ValueType: none; Flags: deletekey; Tasks: not openinkoil
Root: HKA; Subkey: "Software\Classes\Drive\shell\Koil"; ValueType: none; Flags: deletekey; Tasks: not openinkoil

[Icons]
Name: "{autoprograms}\Koil"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\Koil"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,Koil}"; Flags: nowait postinstall skipifsilent
