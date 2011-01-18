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
  InstallDir "C:\RCSCollector\"

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
  ;!insertmacro MUI_PAGE_LICENSE "license.rtf"
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

  ${If} $serviceRLD == ${BST_CHECKED}
    DetailPrint ""
    DetailPrint "Stopping RLD..."
    nsExec::ExecToLog 'net stop RLD'
    nsExec::ExecToLog '"$INSTDIR\RCSASP" uninstall RLD'
  ${EndIf}

  ${If} $serviceRSS == ${BST_CHECKED}    
    DetailPrint ""
    DetailPrint "Stopping RSS..."
    nsExec::ExecToLog 'net stop RSS'
    nsExec::ExecToLog '"$INSTDIR\RCSASP" uninstall RSS'
  ${EndIf}

  ${If} $serviceRNC == ${BST_CHECKED}    
    DetailPrint ""
    DetailPrint "Stopping RNC..."
    nsExec::ExecToLog 'net stop RNC'
    nsExec::ExecToLog '"$INSTDIR\RCSASP" uninstall RNC'
  ${EndIf}

  ${If} $serviceRSSM == ${BST_CHECKED}
    DetailPrint ""
    DetailPrint "Killing MobileGui..."
    nsExec::ExecToLog 'taskkill /F /IM MobileGui.exe'
    DetailPrint ""
    DetailPrint "Stopping RSSM..."
    nsExec::ExecToLog 'net stop RSSM'
    nsExec::ExecToLog '"$INSTDIR\RCSASP" uninstall RSSM'
  ${EndIf}

  DetailPrint "Migrating data..."
  SetDetailsPrint "textonly"
  SetOutPath "$INSTDIR\setup"
  File "..\setup\migrate.bat"
  nsExec::Exec 'C:\RCSASP\setup\migrate.bat'
  SetDetailsPrint "both"
  DetailPrint "done"

SectionEnd

Section "Install Section" SecInstall
 
  SectionIn 1 2
 
  SetDetailsPrint "textonly"
  DetailPrint "Extracting common files..."
 
  SetOutPath "$INSTDIR\setup"
  File "..\setup\RCS.ico"
  
  SetOutPath "$INSTDIR\licenses"
  File "..\Licenses\LAME.license.txt"
  File "..\Licenses\CURL.license.txt"
  File "..\Licenses\OPENSSL.license.txt"
  File "..\Licenses\SPEEX.license.txt"
  File "..\Licenses\XMLRPC++.license.txt"
   
  SetOutPath "$INSTDIR"

  File "..\Release\RCSASP.exe"
  File "..\RCSASP\VERSION.txt"
  DetailPrint "done"
  
  SetDetailsPrint "both"
    
  File "vcredist_x86.exe"
  DetailPrint "Installing VC++ 2008 Runtime..."
  nsExec::ExecToLog '$INSTDIR\vcredist_x86.exe /q'
  DetailPrint "done"

  ${If} $serviceRSS == ${BST_CHECKED}
    DetailPrint ""
    DetailPrint "Installing RSS..."
    SetDetailsPrint "textonly"
    File "..\Release\RSS.dll"
    File "..\DDPH.HTML"
	File "..\zlib1.dll"
	File "..\ssleay32.dll"
	File "..\libeay32.dll"
	File "..\libcurl.dll"
	SetDetailsPrint "both"
	DetailPrint "done"
  ${Endif}
    
  ${If} $serviceRLD == ${BST_CHECKED}
    DetailPrint ""
	DetailPrint "Installing RLD..."
	SetDetailsPrint "textonly"
    File "..\Release\RLD.dll"
	File "..\lame_enc.dll"
	File "..\wav2mp3.dll"
	File "..\libspeex.dll"
	File "..\libamr.dll"
	File "..\zlib1.dll"
	File "..\ssleay32.dll"
	File "..\libeay32.dll"
	File "..\libcurl.dll"
	SetDetailsPrint "both"
	DetailPrint "done"
  ${Endif}

  ${If} $serviceRNC == ${BST_CHECKED}
    DetailPrint ""
	DetailPrint "Installing RNC..."
	SetDetailsPrint "textonly"
    File "..\Release\RNC.dll"
	File "..\zlib1.dll"
	File "..\ssleay32.dll"
	File "..\libeay32.dll"
	File "..\libcurl.dll"
	SetDetailsPrint "both"
	DetailPrint "done"
  ${Endif}

  ${If} $serviceRSSM == ${BST_CHECKED}
    DetailPrint ""
	DetailPrint "Installing RSSM..."
	SetDetailsPrint "textonly"
    File "..\Release\RSSM.dll"
    File "..\Release\RLDM.dll"
    File "..\Release\MobileGUI.exe"
    File "..\DDPH.HTML"
	File "..\zlib1.dll"
	File "..\ssleay32.dll"
	File "..\libeay32.dll"
	File "..\libcurl.dll"
	File "..\bthprops.cpl"
	File "..\devmgr.dll"
	File "..\wlanapi.dll"
	File "..\wtsapi32.dll"
	File "..\wzcsapi.dll"
	CreateShortCut "$DESKTOP\MobileGui.lnk" "$INSTDIR\MobileGUI.exe"
	SetDetailsPrint "both"
	DetailPrint "done"
  ${Endif}

  ${If} $serviceRLD == ${BST_CHECKED} 
  ${OrIf} $serviceRSS == ${BST_CHECKED}
  ${OrIf} $serviceRNC == ${BST_CHECKED}
     ; fresh install
     ${If} $insttype == 0
       DetailPrint ""
	   DetailPrint "Writing the registry..."
	   SetDetailsPrint "textonly"
       CopyFiles /SILENT $cert "$INSTDIR\rcs-client.pem"
       CopyFiles /SILENT $sign "$INSTDIR\rcs-db.sig"
       WriteRegStr HKLM "Software\RCSASP" "Server" "https://$addr"
       WriteRegStr HKLM "Software\RCSASP" "Port" "4443"
       WriteRegStr HKLM "Software\RCSASP" "Url" "/server.php"
       SetDetailsPrint "both"
       DetailPrint "done"
     ${Else}
     ; upgrade
	   DeleteRegKey HKLM "Software\RCSASP\Username"
	   DeleteRegKey HKLM "Software\RCSASP\Password"
	   IfFileExists "C:\RCSASP\rcs-db.sig" +5 0
	      CopyFiles /SILENT $cert "$INSTDIR\rcs-client.pem"
          CopyFiles /SILENT $sign "$INSTDIR\rcs-db.sig"
          WriteRegStr HKLM "Software\RCSASP" "Server" "https://$addr"
          WriteRegStr HKLM "Software\RCSASP" "Port" "4443"
          WriteRegStr HKLM "Software\RCSASP" "Url" "/server.php"
     ${EndIf}
  ${EndIf}
          
  DetailPrint ""
     
  ${If} $serviceRLD == ${BST_CHECKED}
	DetailPrint "Starting RLD..."
    nsExec::ExecToLog '"$INSTDIR\RCSASP" install RLD'
    nsExec::ExecToLog 'net start RLD'
  ${EndIf}

  ${If} $serviceRNC == ${BST_CHECKED}
	DetailPrint "Starting RNC..."
    nsExec::ExecToLog '"$INSTDIR\RCSASP" install RNC'
    nsExec::ExecToLog 'net start RNC'
  ${EndIf}

  ${If} $serviceRSS == ${BST_CHECKED}
	DetailPrint "Starting RSS..."
    nsExec::ExecToLog '"$INSTDIR\RCSASP" install RSS'
    nsExec::ExecToLog 'net start RSS'
	DetailPrint "Adding firewall rule for port 443/tcp..."
	nsExec::ExecToLog 'netsh firewall add portopening TCP 443 "RCSASP - RSS"'
  ${EndIf}

  ${If} $serviceRSSM == ${BST_CHECKED}
	DetailPrint "Starting RSSM..."
    nsExec::ExecToLog '"$INSTDIR\RCSASP" install RSSM'
    nsExec::ExecToLog 'net start RSSM'
	DetailPrint "Adding firewall rule for port 80/tcp..."
    nsExec::ExecToLog 'netsh firewall add portopening TCP 80 "RCSASP - RSSM"'
  ${EndIf}

  DetailPrint "Writing uninstall informations..."
  SetDetailsPrint "textonly"
	
  WriteUninstaller "$INSTDIR\setup\RCSASP-uninstall.exe"

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSASP" "DisplayName" "RCSASP"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSASP" "DisplayIcon" "C:\RCSASP\setup\RCS.ico"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSASP" "DisplayVersion" "${PACKAGE_VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSASP" "UninstallString" "C:\RCSASP\setup\RCSASP-uninstall.exe"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSASP" "NoModify" 0x00000001
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSASP" "NoRepair" 0x00000001
  
  ${If} $serviceRLD == ${BST_CHECKED} 
  ${OrIf} $serviceRSS == ${BST_CHECKED}
  ${OrIf} $serviceRNC == ${BST_CHECKED}
	SetOutPath "$INSTDIR\setup"
	File "RCSASP-configure.exe"
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSASP" "NoModify" 0x00000000
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSASP" "ModifyPath" "C:\RCSASP\setup\RCSASP-configure.exe"
  ${EndIf}
 
  SetDetailsPrint "both"
 
SectionEnd

Section Uninstall

  DetailPrint "Removing firewall rule for 443/tcp..."
  nsExec::ExecToLog 'netsh firewall delete portopening TCP 443'
  DetailPrint "Removing firewall rule for 80/tcp..."
  nsExec::ExecToLog 'netsh firewall delete portopening TCP 80'


  DetailPrint "Stopping RLD..."
  nsExec::ExecToLog '"C:\RCSASP\RCSASP" uninstall RLD'

  DetailPrint ""
  DetailPrint "Stopping RSS..."
  nsExec::ExecToLog '"C:\RCSASP\RCSASP" uninstall RSS'

  DetailPrint ""
  DetailPrint "Stopping RNC..."
  nsExec::ExecToLog '"C:\RCSASP\RCSASP" uninstall RNC'

  DetailPrint ""
  DetailPrint "Stopping RSSM..."
  nsExec::ExecToLog '"C:\RCSASP\RCSASP" uninstall RSSM'

  DetailPrint ""
  DetailPrint "Killing MobileGui..."
  nsExec::ExecToLog 'taskkill /F /IM MobileGui.exe'

  DetailPrint ""
  DetailPrint "Deleting files..."
  SetDetailsPrint "textonly"
  RMDir /r "C:\RCSASP"
  Delete "$DESKTOP\MobileGui.lnk" 
  SetDetailsPrint "both"
  DetailPrint "done"

  DetailPrint ""
  DetailPrint "Removing registry keys..."
  DeleteRegKey HKLM "Software\RCSASP"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\RCSASP"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Run\RCSASP"

SectionEnd

;--------------------------------
;Installer Functions

Function .onInit

   IfFileExists "$INSTDIR\VERSION.txt" 0 +4
      SetCurInstType 1
      MessageBox MB_YESNO|MB_ICONQUESTION "RCSASP is already installed.$\nDo you want to update?" IDYES +2 IDNO 0
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