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
  Var serviceRLDctrl
  Var serviceRLD
  Var serviceRSSctrl
  Var serviceRSS
  Var serviceRSSMctrl
  Var serviceRSSM
  Var serviceRNCctrl
  Var serviceRNC

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
   DetailPrint "Uninstalling RCSCollector..."
   SimpleSC::StopService "RCSCollector" 1
   SimpleSC::RemoveService "RCSCollector"
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

  SetOutPath "$INSTDIR\Collector"

  File /r "bin\*.*"
  DetailPrint "done"
  
  SetDetailsPrint "both"

     ; fresh install
     ${If} $insttype == 0
       DetailPrint ""
	   DetailPrint "Writing the registry..."
	   SetDetailsPrint "textonly"
       CopyFiles /SILENT $cert "$INSTDIR\rcs-client.pem"
       CopyFiles /SILENT $sign "$INSTDIR\rcs-db.sig"
       ; TODO: write the yaml
       SetDetailsPrint "both"
       DetailPrint "done"
     ${Else}
     ; upgrade
	   IfFileExists "C:\RCSASP\rcs-db.sig" +5 0
	      CopyFiles /SILENT $cert "$INSTDIR\rcs-client.pem"
          CopyFiles /SILENT $sign "$INSTDIR\rcs-db.sig"
          ; TODO: write the yaml
     ${EndIf}
          
  DetailPrint ""

  DetailPrint "Adding firewall rule for port 80/tcp..."
  nsExec::ExecToLog 'netsh firewall add portopening TCP 80 "RCSCollector"'

  DetailPrint "Starting RCSCollector..."
  SimpleSC::InstallService "RCSCollector" "RCSCollector" "16" "2" "$INSTDIR\Collector\bin\srvany" "" "" ""
  SimpleSC::SetServiceFailure "RCSCollector" "0" "" "" "1" "60000" "1" "60000" "1" "60000"
  WriteRegStr HKLM "SYSTEM\CurrentControlSet\Services\RCSCollector\Parameters" "Application" "$INSTDIR\Ruby\bin\ruby.exe $INSTDIR\Collector\bin\rcs-collector"
  SimpleSC::StartService "RCSCollector" ""
   
  DetailPrint "Writing uninstall informations..."
  SetDetailsPrint "textonly"
  WriteUninstaller "$INSTDIR\setup\RCSCollector-uninstall.exe"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "DisplayName" "RCS Collector"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "DisplayIcon" "C:\RCS\Collector\setup\RCS.ico"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "DisplayVersion" "${PACKAGE_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "UninstallString" "C:\RCS\Collector\setup\RCSCollector-uninstall.exe"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "NoModify" 0x00000001
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector" "NoRepair" 0x00000001

  SetDetailsPrint "both"
 
SectionEnd

Section Uninstall

  DetailPrint "Removing firewall rule for 80/tcp..."
  nsExec::ExecToLog 'netsh firewall delete portopening TCP 80'

  DetailPrint "Stopping RCSCollector..."
  SimpleSC::StopService "RCSCollector" 1
  SimpleSC::RemoveService "RCSCollector"

  DetailPrint ""
  DetailPrint "Deleting files..."
  SetDetailsPrint "textonly"
  RMDir /r "C:\RCS\Collector"
  ; TODO: delete ruby if not rcsdb
  SetDetailsPrint "both"
  DetailPrint "done"

  DetailPrint ""
  DetailPrint "Removing registry keys..."
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSCollector"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Run\RCSCollector"

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
  ${NSD_CreateCheckBox} 20u 15u 200u 12u "RLD (RCS Log Decryptor)"
  Pop $serviceRLDctrl
  ${NSD_CreateCheckBox} 20u 30u 200u 12u "RSS (RCS Sync Server)"
  Pop $serviceRSSctrl
  ${NSD_CreateCheckBox} 20u 45u 200u 12u "RSSM (RCS Sync Server Mobile)"
  Pop $serviceRSSMctrl
  ${NSD_CreateCheckBox} 20u 60u 200u 12u "RNC (RCS Network Controller)"
  Pop $serviceRNCctrl

  ${NSD_Check} $serviceRLDctrl
  ${NSD_Check} $serviceRSSctrl
  ${NSD_Check} $serviceRSSMctrl
  ${NSD_Check} $serviceRNCctrl

  nsDialogs::Show

  Return

FunctionEnd

Function FuncConfigureServiceLeave

  ${NSD_GetState} $serviceRLDctrl $serviceRLD
  ${NSD_GetState} $serviceRSSctrl $serviceRSS
  ${NSD_GetState} $serviceRSSMctrl $serviceRSSM
  ${NSD_GetState} $serviceRNCctrl $serviceRNC

  Return

FunctionEnd

Function FuncConfigureConnection
   
   ${If} $insttype == 1
      IfFileExists "C:\RCSASP\rcs-db.sig" 0 +2
		Abort
   ${EndIf}
   
  ; Se non ho selezionato almeno RSS o RLD, non chiedere le credenziali di accesso al DB.
  ${IfNot} $serviceRLD == ${BST_CHECKED} 
  ${AndIfNot} $serviceRSS == ${BST_CHECKED}
  ${AndIfNot} $serviceRNC == ${BST_CHECKED}
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