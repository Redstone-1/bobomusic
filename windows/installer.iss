; 所有者先构建并签名 BundleDir，再用 Inno Setup 6 编译此脚本。
#ifndef BundleDir
  #define BundleDir "..\build\windows\x64\runner\Release"
#endif
#ifndef AppVersion
  #error "请通过 /DAppVersion=版本名 传入与 pubspec.yaml 一致的版本名"
#endif
#ifndef OutputDir
  #define OutputDir "..\build\windows-distribution"
#endif

[Setup]
AppId={{283CB667-2FC0-43E5-9CC8-35D7CF1ED236}
AppName=啵啵音乐
AppVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\Bobomusic
DefaultGroupName=啵啵音乐
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=bobomusic-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\bobomusic.exe
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\啵啵音乐"; Filename: "{app}\bobomusic.exe"
Name: "{autodesktop}\啵啵音乐"; Filename: "{app}\bobomusic.exe"; Tasks: desktopicon

; 不添加数据目录的卸载删除项；用户库、偏好和下载文件在升级与卸载时保留。
[Run]
Filename: "{app}\bobomusic.exe"; Description: "启动啵啵音乐"; Flags: nowait postinstall skipifsilent
