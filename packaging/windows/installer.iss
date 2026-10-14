#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef OutputPath
  #error OutputPath is required
#endif

[Setup]
AppId={{DBF988C5-81A8-4D96-8386-A391044EF965}
AppName=Burrow Brigade
AppVersion={#AppVersion}
AppPublisher=Burrow Brigade contributors
AppPublisherURL=https://github.com/AliOsm/scarpe-worms
DefaultDirName={localappdata}\Programs\Burrow Brigade
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.18362
OutputDir={#OutputPath}
OutputBaseFilename=Burrow-Brigade-{#AppVersion}-windows-x64-setup
SetupIconFile={#BundleDir}\resources\Burrow Brigade.ico
UninstallDisplayIcon={app}\Burrow Brigade.exe
UninstallDisplayName=Burrow Brigade
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Only managed application files. Saves and logs live outside the installation.
Type: filesandordirs; Name: "{app}\resources"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Burrow Brigade"; Filename: "{app}\Burrow Brigade.exe"
Name: "{autodesktop}\Burrow Brigade"; Filename: "{app}\Burrow Brigade.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Burrow Brigade.exe"; Description: "Open Burrow Brigade"; Flags: nowait postinstall skipifsilent
