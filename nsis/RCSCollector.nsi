;NSIS Modern User Interface

;--------------------------------
;Include Modern UI
  !include "MUI2.nsh"
;--------------------------------
;General
	
  !define PACKAGE_NAME "RCSCollector"
  !Define /file PACKAGE_VERSION "..\config\version.txt"

  ;Variables
  Var insttype
  Var addrctrl
  Var addr
  Var signctrl
  Var sign
  Var certctrl
  Var cert
  Var serviceCollectorctrl
  Var serviceCollector
  Var serviceNetworkctrl
  Var serviceNetwork

  ;Name and file
  Name "RCSCollector"
  OutFile "RCSCollector-${PACKAGE_VERSION}.exe"

  ;Default installation folder
  InstallDir "C:\RCS\"

  ShowInstDetails "show"
  ShowUnInstDetails "show"
  
;--------------------------------
;Install types
   InstType "install"
   InstType "update"

;--------------------------------

;--------------------------------
;Interface Settings

  !define MUI_ABORTWARNING
  !define MUI_WELCOMEFINISHPAGE_BITMAP "HT.bmp"
  !define MUI_WELCOMEFINISHPAGE_BITMAP_NOSTRETCH
  !define MUI_ICON "RCS.ico"
  !define MUI_UNICON "RCS.ico"
  ;!define MUI_LICENSEPAGE_CHECKBOX
  BrandingText "Nullsoft Install System - ${PACKAGE_NAME} (${PACKAGE_VERSION})"

;--------------------------------
;Pages

  !insertmacro MUI_PAGE_WELCOME
  Page custom FuncConfigureService FuncConfigureServiceLeave
  Page custom FuncConfigureConnection FuncConfigureConnectionLeave
  !insertmacro MUI_PAGE_INSTFILES

  !insertmacro MUI_UNPAGE_WELCOME
  !insertmacro MUI_UNPAGE_INSTFILES

;--------------------------------
;Languages

  !insertmacro MUI_LANGUAGE "English"

;--------------------------------
;Installer Sections

Section "Update Section" SecUpdate
   SectionIn 2

   DetailPrint ""
   DetailPrint "Uninstalling RCSCollector Service..."
   SimpleSC::StopService "RCSCollector" 1
   SimpleSC::RemoveService "RCSCollector"
   DetailPrint "done"
SectionEnd

Section "Install Section" SecInstall
 
  SectionIn 1 2
 
  SetDetailsPrint "textonly"
  DetailPrint "Extracting common files..."

  !cd '..\..'
  SetOutPath "$INSTDIR\Ruby"
  File /r "Ruby\*.*"

  !cd 'Collector'
  SetOutPath "$INSTDIR\Collector\setup"
  File "nsis\RCS.ico"

  SetOutPath "$INSTDIR\Collector\bin"
  File /r "bin\*.*"
  
  SetOutPath "$INSTDIR\Collector\lib"
  File "lib\rcs-collector.rb"
  
  SetOutPath "$INSTDIR\Collector\lib\rcs-collector-release"
  File /r "lib\rcs-collector-release\*.*"
  
  SetOutPath "$INSTDIR\Collector\config"
  File "config\decoy.html"
  File "config\trace.yaml"
  File "config\version.txt"
  DetailPrint "done"
  
  SetDetailsPrint "both"

     ; fresh install
     ${If} $insttype == 0
       DetailPrint ""
	   DetailPrint "Writing the configuration..."
	   SetDetailsPrint "textonly"
       CopyFiles /SILENT $cert "$INSTDIR\Collector\config\rcs-client.pem"
       CopyFiles /SILENT $sign "$INSTDIR\Collector\config\rcs-db.sig"
       ; TODO: write the yaml
       SetDetailsPrint "both"
       DetailPrint "done"
     ${Else}
     ; upgrade
	   IfFileExists "$INSTDIR\Collector\config\rcs-db.sig" +5 0
	      CopyFiles /SILENT $cert "$INSTDIR\Collector\config\rcs-client.pem"
          CopyFiles /SILENT $sign "$INSTDIR\Collector\config\rcs-db.sig"
          ; TODO: write the yaml
     ${EndIf}
          
  DetailPrint ""

  DetailPrint "Adding firewall rule for port 80/tcp..."
  nsExec::ExecToLog 'netsh firewall add portopening TCP 80 "RCSCollector"'

  DetailPrint "Starting RCSCollector..."
  SimpleSC::InstallService "RCSCollector" "RCS Collector" "16" "2" "$INSTDIR\Collector\bin\srvany" "" "" ""
  SimpleSC::SetServiceFailure "RCSCollector" "0" "" "" "1" "60000" "1" "60000" "1" "60000"
  WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\RCSCollector\Parameters" "Application" "$INSTDIR\Ruby\bin\ruby.exe $INSTDIR\Collector\bin\rcs-collector"
  SimpleSC::StartService "RCSCollector" ""
   
  DetailPrint "Writing uninstall informations..."
  SetDetailsPrint "textonly"
  WriteUninstaller "$INSTDIR\Collector\setup\RCSCollector-uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "DisplayName" "RCS Collector"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "DisplayIcon" "$INSTDIR\Collector\setup\RCS.ico"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "DisplayVersion" "${PACKAGE_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "UninstallString" "$INSTDIR\Collector\setup\RCSCollector-uninstall.exe"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "NoModify" 0x00000001
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "NoRepair" 0x00000001
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "InstDir" "$INSTDIR"

  SetDetailsPrint "both"
 
SectionEnd

Section Uninstall

  DetailPrint "Removing firewall rule for 80/tcp..."
  nsExec::ExecToLog 'netsh firewall delete portopening TCP 80'
	DetailPrint "done"

  DetailPrint "Stopping RCSCollector Service..."
  SimpleSC::StopService "RCSCollector" 1
  SimpleSC::RemoveService "RCSCollector"
  DetailPrint "done"

  DetailPrint ""
  DetailPrint "Deleting files..."
  SetDetailsPrint "textonly"
  ReadRegStr $R0 HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "InstDir"
  RMDir /r "$R0\Collector"
  ; #TODO: delete ruby if not rcsdb
  RMDir /r "$R0\Ruby"
  RMDir /r "$R0"
  SetDetailsPrint "both"
  DetailPrint "done"

  DetailPrint ""
  DetailPrint "Removing registry keys..."
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Run\RCSCollector"
	DetailPrint "done"

SectionEnd

;--------------------------------
;Installer Functions

Function .onInit
   IfFileExists "$INSTDIR\Collector\config\version.txt" 0 +4
      SetCurInstType 1
      MessageBox MB_YESNO|MB_ICONQUESTION "RCSCollector is already installed.$\nDo you want to update?" IDYES +2 IDNO 0
         Quit
   
   GetCurInstType $insttype
   Return
FunctionEnd

Function FuncConfigureService
	
  !insertmacro MUI_HEADER_TEXT "Configuration settings: Services" "Please enter configuration settings."

  nsDialogs::Create /NOUNLOAD 1018

  ${NSD_CreateLabel} 0 5u 100% 10u "Select services you want to run at startup:"
  ${NSD_CreateCheckBox} 20u 15u 200u 12u "Collector"
  Pop $serviceCollectorctrl
  ${NSD_CreateCheckBox} 20u 30u 200u 12u "Network Controller"
  Pop $serviceNetworkctrl

  ${NSD_Check} $serviceCollectorctrl
  ${NSD_Check} $serviceNetworkctrl

  nsDialogs::Show

  Return

FunctionEnd

Function FuncConfigureServiceLeave

  ${NSD_GetState} $serviceCollectorctrl $serviceCollector
  ${NSD_GetState} $serviceNetworkctrl $serviceNetwork

  Return

FunctionEnd

Function FuncConfigureConnection
   
   ; se e' un upgrade non richiedere le credenziali
   ${If} $insttype == 1
      IfFileExists "$INSTDIR\Collector\config\rcs-db.sig" 0 +2
		Abort
   ${EndIf}
   
  ; Se non ho selezionato almeno un componente, non chiedere le credenziali di accesso al DB.
  ${IfNot} $serviceCollector == ${BST_CHECKED} 
  ${AndIfNot} $serviceNetwork == ${BST_CHECKED}
    Abort
  ${EndIf}

  !insertmacro MUI_HEADER_TEXT "Configuration settings: RCSDB connection" "Please enter configuration settings."

  nsDialogs::Create /NOUNLOAD 1018

  ${NSD_CreateLabel} 0 5u 100% 10u "Hostname or IP address of RCSDB:"
  ${NSD_CreateLabel} 5u 17u 40u 10u "Hostname:"
  ${NSD_CreateText} 50u 15u 200u 12u "localhost"
  Pop $addrctrl

  ${NSD_CreateLabel} 0 35u 100% 10u "Certificate file:"
  ${NSD_CreateLabel} 5u 47u 40u 10u "Certificate:"
  ${NSD_CreateFileRequest} 50u 45u 145u 12u ""
  Pop $certctrl
  ${NSD_CreateBrowseButton} 200u 45u 50u 12u "Browse..."
  Pop $0
  GetFunctionAddress $1 BrowseClickFunctionCert
  nsDialogs::OnClick /NOUNLOAD $0 $1

  ${NSD_CreateLabel} 0 65u 100% 10u "Signature file:"
  ${NSD_CreateLabel} 5u 77u 40u 10u "Signature:"
  ${NSD_CreateFileRequest} 50u 75u 145u 12u ""
  Pop $signctrl
  ${NSD_CreateBrowseButton} 200u 75u 50u 12u "Browse..."
  Pop $0
  GetFunctionAddress $1 BrowseClickFunctionSign
  nsDialogs::OnClick /NOUNLOAD $0 $1

  nsDialogs::Show

  Return

FunctionEnd

Function FuncConfigureConnectionLeave

  ${NSD_GetText} $addrctrl $addr

  StrCmp $addr "" 0 +3
    MessageBox MB_ICONSTOP "IP address cannot be empty"
    Abort

  ${NSD_GetText} $certctrl $cert

  StrCmp $cert "" 0 +3
    MessageBox MB_ICONSTOP "Certificate file cannot be empty"
    Abort

  ${NSD_GetText} $signctrl $sign

  StrCmp $sign "" 0 +3
    MessageBox MB_ICONSTOP "Signature file cannot be empty"
    Abort

  Return

FunctionEnd



Function BrowseClickFunctionCert

  nsDialogs::SelectFileDialog /NOUNLOAD open "" "Certificate files (*.pem)|*.pem"
  Pop $0

  SendMessage $certctrl ${WM_SETTEXT} 0 STR:$0

  Return

FunctionEnd


Function BrowseClickFunctionSign

  nsDialogs::SelectFileDialog /NOUNLOAD open "" "Signature files (*.sig)|*.sig"
  Pop $0

  SendMessage $signctrl ${WM_SETTEXT} 0 STR:$0

  Return

FunctionEnd