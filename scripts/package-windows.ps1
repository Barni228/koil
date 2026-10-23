# Builds Koil, bundles the Qt runtime next to the exe (windeployqt), and
# wraps it in an Inno Setup installer:
#   dist\Koil-<version>-windows-x64-setup.exe
#
# Needs Visual Studio (or its Build Tools) with the C++ workload, Qt's bin
# directory on PATH, and Inno Setup 6.
$ErrorActionPreference = "Stop"

# Load the MSVC build environment unless we're already in a Developer shell.
if (-not $env:VCToolsRedistDir) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw "Visual Studio with the C++ workload not found" }
    & "$vs\Common7\Tools\Launch-VsDevShell.ps1" -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null
}

$root = Resolve-Path "$PSScriptRoot\.."
$version = (cargo metadata --no-deps --format-version 1 --manifest-path "$root\Cargo.toml" |
    ConvertFrom-Json).packages[0].version
$stage = "$root\target\release\deploy"
$dist = "$root\dist"

# --locked: what Cargo.lock has (koil-core's commit too), or fail.
cargo build --release --locked --manifest-path "$root\Cargo.toml"
if ($LASTEXITCODE) { throw "cargo build failed" }

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory $stage | Out-Null
Copy-Item "$root\target\release\koil.exe" $stage

# Without what Koil never loads, as bundle-macos.sh: the plugins for
# pictures (image formats, SVG icons), the network (TLS, network
# information), widgets (their style: it has no QApplication), databases,
# QML debugging and TUIO touch input; Qt's translations (Koil's text is
# English); and the shader compilers, as Windows 10 and 11 have D3D's, and
# Qt Quick uses D3D11, not the D3D12 that DXC is for.
windeployqt --release --qmldir "$root\qml" --no-compiler-runtime --no-opengl-sw `
    --no-translations --no-system-d3d-compiler --no-system-dxc-compiler `
    --skip-plugin-types imageformats,iconengines,tls,networkinformation,styles,sqldrivers,qmltooling,generic `
    "$stage\koil.exe"
if ($LASTEXITCODE) { throw "windeployqt failed" }
# The Controls styles but the Fusion main.rs sets and the Basic it falls back
# to (QtQuick.Controls imports only the style in use), NativeStyle, which
# only the native ones use, and QML modules nothing imports, with their
# DLLs: none of what Koil loads imports them (checked with objdump -p).
$unused = @(
    "qml\QtQuick\Controls\FluentWinUI3", "qml\QtQuick\Controls\Imagine", "qml\QtQuick\Controls\Material",
    "qml\QtQuick\Controls\Universal", "qml\QtQuick\Controls\Windows", "qml\QtQuick\NativeStyle",
    "qml\QtQuick\Particles", "qml\QtQuick\VectorImage", "qml\QtQuick\Shapes\DesignHelpers",
    "qml\QtQuick\LocalStorage", "qml\QtQml\XmlListModel", "qml\QtQuick\tooling",
    "Qt6QuickControls2FluentWinUI3*.dll", "Qt6QuickControls2Imagine*.dll", "Qt6QuickControls2Material*.dll",
    "Qt6QuickControls2Universal*.dll", "Qt6QuickControls2Windows*.dll", "Qt6QuickParticles.dll",
    "Qt6QuickVectorImage*.dll", "Qt6QuickShapesDesignHelpers.dll", "Qt6QmlLocalStorage.dll", "Qt6Sql.dll",
    "Qt6QmlXmlListModel.dll", "Qt6Svg*.dll"
)
foreach ($path in $unused) {
    if (Test-Path "$stage\$path") { Remove-Item "$stage\$path" -Recurse -Force }
}

# Ship the MSVC runtime DLLs app-locally so a fresh Windows install doesn't
# need the Visual C++ Redistributable.
Copy-Item "$env:VCToolsRedistDir\x64\Microsoft.VC*.CRT\*.dll" $stage

$iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
& $iscc "/DAppVersion=$version" "/DSourceDir=$stage" "/DOutputDir=$dist" "$root\packaging\windows\installer.iss"
if ($LASTEXITCODE) { throw "ISCC failed" }
