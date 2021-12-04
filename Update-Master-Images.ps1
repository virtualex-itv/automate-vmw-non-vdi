# This script requires a Task Scheduler instance setup to do the download and install of Windows patches. This is due to security policies
# in place that you cannot download anything while in a remote session.  So for each new Master Image be sure to create this which can be done 
# once then export it to a file share and run this command so it's the same in each VM.
#
# schtasks /create /xml "\\192.168.1.95\share\Scripts\Download Windows Updates.xml" /tn "Windows Download and Install Updates" /ru "Administrator" /rp "yourpassword"
# 
# For Windows 10 make sure Windows Remote Management is running as a service, set start automatically in each Master Image VM.
#
# Also change the default web operation timeout from the 300 seconds to -1 to be infinite or to another larger timeout. In my case my home lab NUCs are slow disks so 
# the default 5 mins wasn't long enough and would throw an error but the task would complete within vCenter.  
# Set-PowerCLIConfiguration -WebOperationTimeoutSeconds -1 and then restart the powershell window.
#

#region Variables that you can change to whatever is the use case in your environment.  In mine I have two 2019 editions and one Windows 10 template.
$vc = "vcenter.fqdn.whatever"  # Enter in your vCenter fully qualified domain name
$Server2019DC = "Server2019-DC"  # Content Library Item Name
$Server2019DCVM = "Server2019-DataCenter" # VM Name
$Server2019STD = "Server2019-STD"  # Content Library Item Name
$Server2019STDVM = "Server2019-Standard" # VM Name
$Win10GI = "Win10-Gold-Image"  # Content Library Item Name
$Win10GIVM = "Win10-IC-Parent" # VM Name
$contentlibrary = "NUC-ContentLibrary" # Change to the name of your cluster's Content Library in vCenter
$cluster = "vSAN-Cluster" # Change to your Host cluster name
$vmhost = "esx01.fqdn.whatever" # Change to one of your Hosts name in the above cluster
$vmfolder = "Template-Masters" # Change to the name of a VM folder that you want the templates to reside in vCenter


# I leave these process in my scripts so I can create the credential file when needed on new PS host but keep the lines commented out except for import line that is needed.
#$localcred = get-credential
#$localcred | Export-Clixml -path <driveletter>:\<path>\<filename-local>.cred
$localcred = Import-Clixml -path <driveletter>:\<path>\<filename-local>.cred
# The beginning of each script I always include how to create the credential file and how to import it for each script I use.
# Save vCenter credentials - Only needs to be ran once to create .cred file.
# $credentials = Get-Credential
# $credentials | Export-Clixml -path <driveletter>:\<path>\<filename-vcenter>.cred
$credentials = import-clixml -path <driveletter>:\<path>\<filename-vcenter>.cred

# It's also assumed that the file server that you'll use throughout this script will have read access from this Powershell host or locally stored

#region Modules Load - uncomment and run if you do not have these modules already installed and haven't unblocked the scripts/modules before
# Get-Module -Name VMware* -ListAvailable | Install-Module -Confirm:$false -Force  # Uncomment and run if you do not already have the VMware modules installed
# Find-Module -Name *Hostfile* | Install-Module -Confirm:$false -Force  # Uncomment and run if you do not already have the Host File module installed
# Get-ChildItem -Path 'C:\Program Files\WindowsPowerShell\Modules\VMware*' -Recurse | Unblock-File  # Uncomment and run if you just installed the above modules 
# Get-ChildItem -Path <driveletter>:\<path>\* -Recurse | Unblock-File # Uncomment and run if you just installed this script and the others but also change the path to where those are located
#endregion


# Connect to vCenter with saved creds
connect-viserver -Server $vc -Credential $credentials

# Get list of VMs based upon folders in vCenter
$vmservers=get-vm -location (Get-Folder -Name Template-Masters)
$vmservers | select Name | export-csv s:\scripts\templates-masters.csv -NoTypeInformation
$servers = import-csv S:\scripts\templates-masters.csv | Select -ExpandProperty name
Write-Host "Starting $servers on $vc"
Start-VM -VM $servers

function Start-Sleep($seconds) {
    $doneDT = (Get-Date).AddSeconds($seconds)
    while($doneDT -gt (Get-Date)) {
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($seconds - $secondsLeft) / $seconds * 100
        Write-Progress -Activity "Sleeping.." -Status "Powering on VMs.." -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity "Waiting.." -Status "Letting the OS boot.." -SecondsRemaining 0 -Completed
}

# Sleep for 5 minutes to give the OS time to customize.
Start-Sleep 300

Get-VM -location (Get-Folder -Name Template-Masters) | Select Name, @{N="IP Address";E={@($_.guest.IPAddress[0])}} | Format-Table -HideTableHeaders

# IPs for Master Images used for templates - you may want to reserve the IP and MAC so doesn't change in future.
$IP1 = (Get-VM -Name $Server2019DCVM | Select @{N="IP";E={@($_.guest.IPAddress[0])}} | Format-Table -HideTableHeaders | Out-String).Trim()
$HostName1 = (Get-VM -Name $Server2019DCVM | Select @{N='FQDN';E={$_.ExtensionData.Guest.IPStack[0].DnsConfig.HostName}} | Format-Table -HideTableHeaders | Out-String).Trim()
$IP2 = (Get-VM -Name $Win10GIVM | Select @{N="IP";E={@($_.guest.IPAddress[0])}} | Format-Table -HideTableHeaders | Out-String).Trim()
$HostName2 = (Get-VM -Name $Win10GIVM | Select @{N='FQDN';E={$_.ExtensionData.Guest.IPStack[0].DnsConfig.HostName}} | Format-Table -HideTableHeaders | Out-String).Trim()
$IP3 = (Get-VM -Name $Server2019STDVM | Select @{N="IP";E={@($_.guest.IPAddress[0])}} | Format-Table -HideTableHeaders | Out-String).Trim()
$HostName3 = (Get-VM -Name $Server2019STDVM | Select @{N='FQDN';E={$_.ExtensionData.Guest.IPStack[0].DnsConfig.HostName}} | Format-Table -HideTableHeaders| Out-String).Trim()

Add-HostFileEntry -hostname $Hostname1 -ipaddress $IP1
Add-HostFileEntry -hostname $Hostname2 -ipaddress $IP2
Add-HostFileEntry -hostname $Hostname3 -ipaddress $IP3

# Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
# winRM quickconfig -transport:https

#endregion This is just the beginning, we will verify there are MS Updates that need to be downloaded and installed.

invoke-command -ComputerName $Hostname1 -scriptblock {get-windowsupdate} -UseSSL -Credential $localcred
invoke-command -ComputerName $Hostname2 -scriptblock {get-windowsupdate} -UseSSL -Credential $localcred
invoke-command -ComputerName $Hostname3 -scriptblock {get-windowsupdate} -UseSSL -Credential $localcred

#region Let's update the first master image..
Write-Host "Connecting to $Server2019DCVM and running Task Scheduler to download and install recent updates.."
Invoke-Command -ComputerName $Hostname1 -ScriptBlock {
schtasks /Query /TN "Windows Download and Install Updates"
Install-Module -Name PSWindowsUpdate -Confirm:$false -Force
Get-WindowsUpdate

Start-ScheduledTask -TaskName "Windows Download and Install Updates"

function Start-Sleep($seconds) {
    $doneDT = (Get-Date).AddSeconds($seconds)
    while($doneDT -gt (Get-Date)) {
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($seconds - $secondsLeft) / $seconds * 100
        Write-Progress -Activity "Sleeping.." -Status "Waiting for Windows Updates to install.." -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity "Sleeping.." -Status "Applying new patches and updates.." -SecondsRemaining 0 -Completed
}


Start-Sleep 600
} -UseSSL -Credential $localcred
#endregion

#region Here's the second master image..
Write-Host "Connecting to $Win10GIVM and running Task Scheduler to download and install recent updates.."
Invoke-Command -ComputerName $Hostname2 -ScriptBlock {
Start-Sleep -seconds 5
schtasks /Query /TN "Windows Download and Install Updates"
Install-Module -Name PSWindowsUpdate -Confirm:$false -Force
Get-WindowsUpdate
Start-ScheduledTask -TaskName "Windows Download and Install Updates"

function Start-Sleep($seconds) {
    $doneDT = (Get-Date).AddSeconds($seconds)
    while($doneDT -gt (Get-Date)) {
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($seconds - $secondsLeft) / $seconds * 100
        Write-Progress -Activity "Sleeping.." -Status "Waiting for Windows Updates to install.." -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity "Sleeping.." -Status "Applying new patches and updates.." -SecondsRemaining 0 -Completed
}


Start-Sleep 600
} -UseSSL -Credential $localcred
#endregion

#region Last master image
Write-Host "Connecting to $Server2019STDVM and running Task Scheduler to download and install recent updates.."
Invoke-Command -ComputerName $Hostname3 -ScriptBlock {
Start-Sleep -seconds 5
schtasks /Query /TN "Windows Download and Install Updates"
Install-Module -Name PSWindowsUpdate -Confirm:$false -Force
Get-WindowsUpdate
Start-ScheduledTask -TaskName "Windows Download and Install Updates"

function Start-Sleep($seconds) {
    $doneDT = (Get-Date).AddSeconds($seconds)
    while($doneDT -gt (Get-Date)) {
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($seconds - $secondsLeft) / $seconds * 100
        Write-Progress -Activity "Sleeping.." -Status "Waiting for Windows Updates to install.." -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity "Sleeping.." -Status "Applying new patches and updates.." -SecondsRemaining 0 -Completed
}

Start-Sleep 600
} -UseSSL -Credential $localcred
#endregion

#region Now to restart the VMs..
# Restart VMs to get a clean system
Write-Host "Rebooting $servers to clear up any last update installs.."
Restart-VMGuest -VM $servers
Start-Sleep 600
#endregion

#region Now to shutdown the VMs..
# Shutdown VMs
Write-Host "Shutting down $servers on $vc.."
Shutdown-VMGuest -VM $servers -Confirm:$false

function Start-Sleep($seconds) {
    $doneDT = (Get-Date).AddSeconds($seconds)
    while($doneDT -gt (Get-Date)) {
        $secondsLeft = $doneDT.Subtract((Get-Date)).TotalSeconds
        $percent = ($seconds - $secondsLeft) / $seconds * 100
        Write-Progress -Activity "Sleeping.." -Status "Cleanly doing an OS shutdown.." -SecondsRemaining $secondsLeft -PercentComplete $percent
        [System.Threading.Thread]::Sleep(500)
    }
    Write-Progress -Activity "Sleeping.." -Status "Waiting for VMs to safely complete the shutdown process.." -SecondsRemaining 0 -Completed
}

Start-Sleep 300 # Giving the OS enough time to safely shutdown.
#endregion

#region Now to update the Content Catalog
# First we need to delete the original VM Templates since there isn't an update feature for VMs.
Remove-ContentLibraryItem -ContentLibraryItem $Server2019STD -Confirm:$false
Remove-ContentLibraryItem -ContentLibraryItem $Server2019DC -Confirm:$false
Remove-ContentLibraryItem -ContentLibraryItem $Win10GI -Confirm:$false
New-ContentLibraryItem -ContentLibrary $ContentLibrary -Name $Server2019DC -VM $Server2019DCVM -Location $vmhost -VMTemplate -InventoryLocation $vmfolder
New-ContentLibraryItem -ContentLibrary $ContentLibrary -Name $Server2019STD -VM $Server2019STDVM -VMTemplate -Location $vmhost -InventoryLocation $vmfolder
New-ContentLibraryItem -ContentLibrary $ContentLibrary -Name $Win10GI -VM $Win10GIVM -VMTemplate -Location $vmhost -InventoryLocation $vmfolder
#endregion
