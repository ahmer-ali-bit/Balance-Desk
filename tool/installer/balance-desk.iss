[Setup]
AppName=Balance Desk
AppVersion=1.0.0
AppPublisher=Balance Desk
AppPublisherURL=
AppSupportURL=
AppUpdatesURL=
DefaultDirName={autopf}\Balance Desk
DefaultGroupName=Balance Desk
DisableProgramGroupPage=no
OutputDir=..\..\build\windows\installer
OutputBaseFilename=BalanceDeskSetup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
UninstallDisplayIcon={app}\shop.exe

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Balance Desk"; Filename: "{app}\shop.exe"
Name: "{commondesktop}\Balance Desk"; Filename: "{app}\shop.exe"; Tasks: desktopicon

; Registers the `balancedesk://` protocol so Linked Devices invite links
; (balancedesk://link-device?w=<workspaceId>&t=<token>) open the app on
; Windows. Without this, deep links are silently ignored by the OS.
[Registry]
Root: HKA; Subkey: "Software\Classes\balancedesk"; ValueType: string; ValueName: ""; ValueData: "URL:Balance Desk Invite Link"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\balancedesk"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\balancedesk\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\shop.exe,0"
Root: HKA; Subkey: "Software\Classes\balancedesk\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\shop.exe"" ""%1"""

[Run]
Filename: "{app}\shop.exe"; Description: "Launch Balance Desk"; Flags: nowait postinstall skipifsilent
