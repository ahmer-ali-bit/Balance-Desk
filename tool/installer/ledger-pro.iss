[Setup]
AppName=Ledger Pro
AppVersion=1.0.0
AppPublisher=Ledger Pro
AppPublisherURL=
AppSupportURL=
AppUpdatesURL=
DefaultDirName={autopf}\Ledger Pro
DefaultGroupName=Ledger Pro
DisableProgramGroupPage=no
OutputDir=..\..\build\windows\installer
OutputBaseFilename=LedgerProSetup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
UninstallDisplayIcon={app}\ledger_pro.exe

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Ledger Pro"; Filename: "{app}\ledger_pro.exe"
Name: "{commondesktop}\Ledger Pro"; Filename: "{app}\ledger_pro.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\ledger_pro.exe"; Description: "Launch Ledger Pro"; Flags: nowait postinstall skipifsilent
