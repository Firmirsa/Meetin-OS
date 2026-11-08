Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"

!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Meetin-OS"
!define APP_VERSION "0.1.1"

Name "Meetin-OS"
OutFile "../web/public/downloads/Meetin-OS-Windows.exe"
InstallDir "$LOCALAPPDATA\Programs\Meetin-OS"
RequestExecutionLevel user
SetCompressor /SOLID lzma
!define MUI_ICON "Meetin-OS.ico"
!define MUI_UNICON "Meetin-OS.ico"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "French"

VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey /LANG=${LANG_FRENCH} "ProductName" "Meetin-OS"
VIAddVersionKey /LANG=${LANG_FRENCH} "FileDescription" "Installation de Meetin-OS"
VIAddVersionKey /LANG=${LANG_FRENCH} "FileVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=${LANG_FRENCH} "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=${LANG_FRENCH} "LegalCopyright" "Meetin-OS"

Function .onInit
  ${IfNot} ${RunningX64}
  ${OrIfNot} ${AtLeastWin10}
    MessageBox MB_OK|MB_ICONSTOP "Meetin-OS nécessite Windows 10 ou 11 sur un PC x64." /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
  SetRegView 64
  ReadRegDWORD $0 HKLM "SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" "Release"
  ${If} $0 < 528040
    MessageBox MB_OK|MB_ICONSTOP "Meetin-OS nécessite .NET Framework 4.8, disponible sur le site de Microsoft." /SD IDOK
    SetErrorLevel 1
    Abort
  ${EndIf}
FunctionEnd

Section "Meetin-OS"
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  File ".build\payload\Meetin-OS.exe"
  File ".build\payload\Meetin-OS.exe.config"
  File ".build\payload\NAudio.Core.dll"
  File ".build\payload\NAudio.Wasapi.dll"
  File "NAudio-LICENSE.txt"
  SetOutPath "$INSTDIR\Fonts"
  File "Fonts\EBGaramond.ttf"
  File "Fonts\Figtree.ttf"
  File "Fonts\OFL-EBGaramond.txt"
  File "Fonts\OFL-Figtree.txt"
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\Meetin-OS.lnk" "$INSTDIR\Meetin-OS.exe"

  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "Meetin-OS"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\Meetin-OS.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  SetRegView 64
  SetShellVarContext current
  Delete "$SMPROGRAMS\Meetin-OS.lnk"
  Delete "$INSTDIR\Meetin-OS.exe"
  Delete "$INSTDIR\Meetin-OS.exe.config"
  Delete "$INSTDIR\BuildSource.json"
  Delete "$INSTDIR\NAudio.Core.dll"
  Delete "$INSTDIR\NAudio.Wasapi.dll"
  Delete "$INSTDIR\NAudio-LICENSE.txt"
  Delete "$INSTDIR\Fonts\EBGaramond.ttf"
  Delete "$INSTDIR\Fonts\Figtree.ttf"
  Delete "$INSTDIR\Fonts\OFL-EBGaramond.txt"
  Delete "$INSTDIR\Fonts\OFL-Figtree.txt"
  RMDir "$INSTDIR\Fonts"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
SectionEnd
