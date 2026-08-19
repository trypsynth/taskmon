!ifndef MyAppVersion
	!define MyAppVersion "0.2.1"
!endif
!ifndef MyAppArch
	!define MyAppArch "x64"
!endif
!ifndef SourceExeDir
	!define SourceExeDir "..\zig-out\bin"
!endif
!ifndef MyOutputDir
	!define MyOutputDir "..\zig-out\bin"
!endif

!define MyAppName "Taskmon"
!define MyAppPublisher "Quin Gillespie"
!define UninstallRegKey "Software\Microsoft\Windows\CurrentVersion\Uninstall\Taskmon"
!define TaskmgrIfeoKey "SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\Taskmgr.exe"

Unicode true
Name "${MyAppName}"
OutFile "${MyOutputDir}\taskmon-setup-${MyAppArch}.exe"
InstallDir "$PROGRAMFILES64\${MyAppName}"
InstallDirRegKey HKLM "Software\${MyAppName}" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma

!include "MUI2.nsh"
!include "x64.nsh"
!include "LogicLib.nsh"

!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\taskmon.exe"
!define MUI_FINISHPAGE_RUN_NOTCHECKED
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onInit
	SetRegView 64
!if "${MyAppArch}" == "arm64"
	${IfNot} ${IsNativeARM64}
		MessageBox MB_OK|MB_ICONSTOP "This is the ARM64 build of ${MyAppName}, but this PC isn't running ARM64 Windows."
		Quit
	${EndIf}
!else
	${IfNot} ${RunningX64}
		MessageBox MB_OK|MB_ICONSTOP "${MyAppName} requires 64-bit Windows."
		Quit
	${EndIf}
!endif
FunctionEnd

Section "${MyAppName}" SecMain
	SectionIn RO
	SetRegView 64
	SetOutPath "$INSTDIR"
	File "${SourceExeDir}\taskmon.exe"
	File /oname=LICENSE.txt "..\LICENSE"

	WriteRegStr HKLM "Software\${MyAppName}" "InstallDir" "$INSTDIR"
	WriteUninstaller "$INSTDIR\Uninstall.exe"

	CreateDirectory "$SMPROGRAMS\${MyAppName}"
	CreateShortCut "$SMPROGRAMS\${MyAppName}\${MyAppName}.lnk" "$INSTDIR\taskmon.exe"
	CreateShortCut "$SMPROGRAMS\${MyAppName}\Uninstall ${MyAppName}.lnk" "$INSTDIR\Uninstall.exe"

	WriteRegStr HKLM "${UninstallRegKey}" "DisplayName" "${MyAppName}"
	WriteRegStr HKLM "${UninstallRegKey}" "DisplayVersion" "${MyAppVersion}"
	WriteRegStr HKLM "${UninstallRegKey}" "Publisher" "${MyAppPublisher}"
	WriteRegStr HKLM "${UninstallRegKey}" "DisplayIcon" "$INSTDIR\taskmon.exe"
	WriteRegStr HKLM "${UninstallRegKey}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
	WriteRegStr HKLM "${UninstallRegKey}" "InstallLocation" "$INSTDIR"
	WriteRegDWORD HKLM "${UninstallRegKey}" "NoModify" 1
	WriteRegDWORD HKLM "${UninstallRegKey}" "NoRepair" 1
SectionEnd

Section "Create a &desktop icon" SecDesktopIcon
	CreateShortCut "$DESKTOP\${MyAppName}.lnk" "$INSTDIR\taskmon.exe"
SectionEnd

Section /o "Replace Windows Task Manager (Ctrl+Shift+Esc / taskbar) with ${MyAppName}" SecReplaceTaskmgr
	SetRegView 64
	WriteRegStr HKLM "${TaskmgrIfeoKey}" "Debugger" '"$INSTDIR\taskmon.exe"'
SectionEnd

Section "Uninstall"
	SetRegView 64
	Delete "$INSTDIR\taskmon.exe"
	Delete "$INSTDIR\LICENSE.txt"
	Delete "$INSTDIR\Uninstall.exe"
	RMDir "$INSTDIR"

	Delete "$SMPROGRAMS\${MyAppName}\${MyAppName}.lnk"
	Delete "$SMPROGRAMS\${MyAppName}\Uninstall ${MyAppName}.lnk"
	RMDir "$SMPROGRAMS\${MyAppName}"
	Delete "$DESKTOP\${MyAppName}.lnk"

	; Only remove the Taskmgr redirect if it still points at us - leave it
	; alone if the user has since repointed it at something else.
	ReadRegStr $0 HKLM "${TaskmgrIfeoKey}" "Debugger"
	${If} $0 == '"$INSTDIR\taskmon.exe"'
		DeleteRegValue HKLM "${TaskmgrIfeoKey}" "Debugger"
	${EndIf}

	DeleteRegKey HKLM "${UninstallRegKey}"
	DeleteRegKey HKLM "Software\${MyAppName}"
SectionEnd

LangString DESC_SecMain ${LANG_ENGLISH} "${MyAppName} itself. Required."
LangString DESC_SecDesktopIcon ${LANG_ENGLISH} "Adds a shortcut to your desktop."
LangString DESC_SecReplaceTaskmgr ${LANG_ENGLISH} "Redirects Task Manager's usual launch points to ${MyAppName} instead."

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
	!insertmacro MUI_DESCRIPTION_TEXT ${SecMain} $(DESC_SecMain)
	!insertmacro MUI_DESCRIPTION_TEXT ${SecDesktopIcon} $(DESC_SecDesktopIcon)
	!insertmacro MUI_DESCRIPTION_TEXT ${SecReplaceTaskmgr} $(DESC_SecReplaceTaskmgr)
!insertmacro MUI_FUNCTION_DESCRIPTION_END
