#define MyAppName "Taskmon"
#ifndef MyAppVersion
	#define MyAppVersion "0.2.1"
#endif
#ifndef MyAppArch
	#define MyAppArch "x64"
#endif
#ifndef SourceExeDir
	#define SourceExeDir "..\build\Release"
#endif
#ifndef MyOutputDir
	#define MyOutputDir "..\build"
#endif

[Setup]
AppId={{C4944DB1-F1BC-4827-BCE2-4B281E6F9DCD}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Quin Gillespie
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\taskmon.exe
OutputDir={#MyOutputDir}
OutputBaseFilename=taskmon-setup-{#MyAppArch}
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=admin
WizardStyle=modern
#if MyAppArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"
Name: "replacetaskmgr"; Description: "Replace Windows Task Manager (Ctrl+Shift+Esc / taskbar) with {#MyAppName}"; Flags: unchecked

[Files]
Source: "{#SourceExeDir}\taskmon.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\taskmon.exe"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\taskmon.exe"; Tasks: desktopicon

[Registry]
; When checked, Windows launches Taskmon instead of Taskmgr.exe whenever Task Manager
; is invoked (Ctrl+Shift+Esc, Ctrl+Alt+Del screen, taskbar right-click), via the standard
; Image File Execution Options debugger-redirect mechanism.
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Taskmgr.exe"; ValueType: string; ValueName: "Debugger"; ValueData: """{app}\taskmon.exe"""; Tasks: replacetaskmgr; Flags: uninsdeletevalue
; Clean up the redirect if the task is left unchecked on a repair/modify install.
Root: HKLM; Subkey: "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Taskmgr.exe"; ValueType: none; ValueName: "Debugger"; Tasks: not replacetaskmgr; Flags: deletevalue

[Run]
Filename: "{app}\taskmon.exe"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent unchecked
