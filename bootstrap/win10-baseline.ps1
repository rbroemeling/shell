#
# Windows 10 Initial Setup Script
#
# Primary Author: Remi Broemeling
#
# Reference Source: "Windows 10 Decrapifier"
#                   https://gist.github.com/csandattack/fcf046447154cb01c66726493889dbf9
#
# Reference Source: "Reclaim Windows 10" by Disassembler <disassembler@dasm.cz>
#                   https://gist.github.com/alirobe/7f3b34ad89a159e6daa1
#
# This script will reboot your machine when completed.
#
# General Process
# ---------------
# - Temporarily enable script execution with: `Set-ExecutionPolicy RemoteSigned`.
# - Execute this script.
# - Wait for system to reboot.
# - Audit installed packages with: `Get-AppxPackage | Select Name, PackageFullName | Format-List`.
# - Language > Advanced settings > Check "Use the desktop language bar when it's available", and then click "Save".
# - Region > Administrative > Copy Settings > Check "Welcome screen and system accounts", and then click "OK".
# - Enable BitLocker, if necessary.
# - Re-disable script execution with: `Set-ExecutionPolicy Restricted`.
#

# Ask for elevated permissions, if we don't already have them.
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# Enable Telemetry, but lock it to "Basic"-level information only (Feedback privacy settings > Send your device data to Microsoft).
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Type DWord -Value 1

# Enable SmartScreen Filter (Change SmartScreen settings > Security > Windows SmartScreen)
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Type String -Value "RequireAdmin"
# Privacy settings > Turn on SmartScreen Filter to check web content (URLs) that Windows Store apps use.
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost" -Name "EnableWebContentEvaluation" -Type DWord -Value 1

# Disable Bing Search in Start Menu (Cortana & Search settings > Search online and include web results).
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Type DWord -Value 0

# Disable Location Tracking
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}" -Name "SensorPermissionState" -Type DWord -Value 0
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -Type DWord -Value 0

# Disable Advertising ID (Privacy settings > Let apps use my advertising ID for experiences across apps).
If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo")) {
  New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" | Out-Null
}
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Type DWord -Value 0

# Disable Cortana
If (!(Test-Path "HKCU:\Software\Microsoft\Personalization\Settings")) {
  New-Item -Path "HKCU:\Software\Microsoft\Personalization\Settings" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Type DWord -Value 0
If (!(Test-Path "HKCU:\Software\Microsoft\InputPersonalization")) {
  New-Item -Path "HKCU:\Software\Microsoft\InputPersonalization" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Type DWord -Value 1
Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Type DWord -Value 1
If (!(Test-Path "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore")) {
  New-Item -Path "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore" -Name "HarvestContacts" -Type DWord -Value 0

# Restrict Windows Update P2P to only operate over the local network (Windows Update settings > Advanced options > Choose how updates are delivered > PCs on my local network)
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" -Name "DODownloadMode" -Type DWord -Value 1

# Disable automatic reboot after update installation.
# Windows will automatically re-enable this task unless we forbid the OS from modifying it, but we need to modify it to start with.
$File = "C:\Windows\System32\Tasks\Microsoft\Windows\UpdateOrchestrator\Reboot"
$Account = New-Object System.Security.Principal.NTAccount($env:computername, $env:username)
$Owner = New-Object System.Security.Principal.NTAccount((Get-Acl $File).owner)
if (-Not $Owner.Equals($Account)) {
  # (Task Scheduler > Task Scheduler Library > Microsoft > Windows > UpdateOrchestrator > Reboot).
  Get-ScheduledTask -TaskPath "\Microsoft\Windows\UpdateOrchestrator\" -TaskName "Reboot" | % {$_.Settings.WakeToRun = $false; Set-ScheduledTask $_} | Disable-ScheduledTask | Out-Null
  $FileSecurity = New-Object System.Security.AccessControl.FileSecurity
  $FileSecurity.SetOwner($Account)
  [System.IO.File]::SetAccessControl($File, $FileSecurity)  
}
$Acl = New-Object System.Security.AccessControl.FileSecurity
$Rights = [System.Security.AccessControl.FileSystemRights]"Read, ReadAndExecute, Synchronize"
$InheritanceFlag = [System.Security.AccessControl.InheritanceFlags]::None 
$PropagationFlag = [System.Security.AccessControl.PropagationFlags]::None 
$Rule = New-Object System.Security.AccessControl.FilesystemAccessRule("SYSTEM", $Rights, $InheritanceFlag, $PropagationFlag, "Allow")
$Acl.SetAccessRule($Rule)
$Rule = New-Object System.Security.AccessControl.FilesystemAccessRule("LOCAL SERVICE", $Rights, $InheritanceFlag, $PropagationFlag, "Allow")
$Acl.SetAccessRule($Rule)
$Rule = New-Object System.Security.AccessControl.FilesystemAccessRule($env:username, $Rights, $InheritanceFlag, $PropagationFlag, "Allow")
$Acl.SetAccessRule($Rule)
$Rule = New-Object System.Security.AccessControl.FilesystemAccessRule("Administrators", $Rights, $InheritanceFlag, $PropagationFlag, "Allow")
$Acl.SetAccessRule($Rule)
$Acl.SetAccessRuleProtection($True, $True)
Set-Acl $File $Acl

# Hide the Language Bar (Language > Advanced settings > Change language bar hot keys > Language Bar > Hidden)
If (!(Test-Path "HKCU:\Software\Microsoft\CTF\LangBar")) {
  New-Item -Path "HKCU:\Software\Microsoft\CTF\LangBar" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\Software\Microsoft\CTF\LangBar" -Name "ShowStatus" -Type DWord -Value 3

# Disable input language switching hot key (Language > Advanced settings > Change language bar hot keys > Advanced Key Settings > Between input languages)
Set-ItemProperty -Path "HKCU:\Keyboard Layout\Toggle" -Name "HotKey" -Type DWord -Value 3

# Disable Start Menu "Suggestions" (Settings > Personalization > Start > Occasionally show suggestions in Start)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SystemPaneSuggestionsEnabled" -Type DWord -Value 0

# Hide the Search button and Search box on the Taskbar (Right-click taskbar > Search > Hidden).
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Type DWord -Value 0

# Show file extensions for known file types (File Explorer Options > View > Hide extensions for known file types).
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Type DWord -Value 0

# Show hidden files and folders (File Explorer Options > View > Show hidden files, folders, and drives).
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Type DWord -Value 1

# Change default Explorer view to "Computer" (File Explorer Options > Open File Explorer to).
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Type DWord -Value 1

# Enable use of sign in information to automatically complete windows update installation after reboot.
# (Windows Update Settings > Advanced Options > Use my sign in info to automatically finish setting up my device after an update).
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "ARSOUserConsent" -Type DWord -Value 1

# Disable prompting for sticky keys (Ease of Access Center > Make the keyboard easier to use > Set up Sticky Keys)
Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Type String -Value "506"

# Enable updates to all Microsoft products, not just Windows.
# (Windows Update Settings > Advanced Options > Give me updates for other Microsoft products when I update Windows).
$servicemanager = New-Object -ComObject Microsoft.Update.ServiceManager -Strict
$servicemanager.AddService2("7971f918-a847-4430-9279-4a52d1efe18d",7,"")

# Disable SMBv2 and SMBv3 for the SMB client, requiring it to use SMB v1 in order to increase compatibility with SAMBA.
# Ref: https://lists.samba.org/archive/samba/2015-September/193886.html
# Ref: https://support.microsoft.com/en-us/kb/2696547
sc.exe config lanmanworkstation depend= bowser/mrxsmb10/nsi
sc.exe config mrxsmb20 start= disabled

# Iterate through all non-system applications and then uninstall anything that hasn't been explicitly whitelisted.
$whitelisted_packages = @()
$whitelisted_packages += "AD2F1837.HPPrinterControl"
$whitelisted_packages += "Microsoft.Microsoft3DViewer"
$whitelisted_packages += "Microsoft.DesktopAppInstaller"
$whitelisted_packages += "Microsoft.HEIFImageExtension"
$whitelisted_packages += "Microsoft.VP9VideoExtensions"
$whitelisted_packages += "Microsoft.WebMediaExtensions"
$whitelisted_packages += "Microsoft.WebpImageExtension"
$whitelisted_packages += "Microsoft.Windows.Photos"
$whitelisted_packages += "Microsoft.WindowsStore"
$whitelisted_packages += "Microsoft.WindowsFeedbackHub"
$whitelisted_packages += "Microsoft.Xbox.TCUI"
$whitelisted_packages += "Microsoft.XboxApp"
$whitelisted_packages += "Microsoft.XboxGameOverlay"
$whitelisted_packages += "Microsoft.XboxGamingOverlay"
$whitelisted_packages += "Microsoft.XboxIdentityProvider"
$whitelisted_packages += "Microsoft.XboxSpeechToTextOverlay"
[System.Collections.ArrayList]$installed_packages = Get-AppxPackage -PackageTypeFilter Main | ? { $_.SignatureKind -ne "System" } | Sort Name
foreach ($package in $installed_packages) {
	if ($whitelisted_packages.Contains($package.Name)) {
		Continue
	} else {
		Get-AppxPackage "$($package.Name)" | Remove-AppxPackage
	}
}

# Reboot
Write-Host
Write-Host "Press any key to restart your system..." -ForegroundColor Black -BackgroundColor White
$key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Restart-Computer
