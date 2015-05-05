#
# SQL Server AlwaysOn Availability - Witness Setup
# - Target:  Only the SQL Witness Node
# - Tasks:   Creates a Witness Fileshare
#            Grants Permission to those file shares for the SQL Server Domain Account
#
Param(
    [Parameter(Mandatory)]
    [string]
    $paramWitnessFolderName,

    [Parameter(Mandatory)]
    [string]
    $paramWitnessShareName,

    [Parameter(Mandatory)]
    [string]
    $paramSqlServiceAccount,

    [Parameter(Mandatory)]
    [string]
    $paramAzureVirtualClusterName,
    
    [Parameter(Mandatory)]
    [string]
    $paramSqlAvailabilityGroupName
)

#
# Module Imports
#
Import-Module .\Util-CredSSP.psm1


#
# Setting up Credential Service Provider (for file share witness access)
#
Write-Output "---"
Write-Output "Setting up CredSSP for file share witness trusted access..."
Write-Output "---"

Set-CredSSP -paramPresent -paramIsServer -Verbose:($PSBoundParameters['Verbose'] -eq $true)
Set-CredSSP -paramPresent -paramDelegateComputers ("*." + $domainNameLong) -Verbose:($PSBoundParameters['Verbose'] -eq $true)


Write-Output "---"
Write-Output "Creating the Witness folder and File Share..."
Write-Output "---"

Write-Output ("Creating directory " + $paramWitnessFolderName + "...")
$existingDirectory = Get-Item $paramWitnessFolderName -ErrorAction SilentlyContinue
if($existingDirectory -eq $null) {
    Write-Output "Directory does not exist, creating it..."
    New-Item -Path $paramWitnessFolderName -ItemType Directory
} else {
    Write-Output "Directory does exist, already. Skipping creation!"
}

Write-Output ("Creating file share '" + $paramWitnessShareName + "'...")
$smbShare = Get-SmbShare -Name $paramWitnessShareName -ErrorAction SilentlyContinue
if($smbShare -eq $null)
{
    New-SmbShare -Name $paramWitnessShareName `
                 -Path $paramWitnessFolderName `
                 -Description "Share used for SQL Server AlwaysOn Witness Functionality" `
                 -FullAccess $paramSqlServiceAccount
}
else
{
    Write-Output "Witness Share does exist, already, skipping creation!"
}

Write-Output "---"
Write-Output "Now that the Witness share is available, update the cluster quorum settings..."
Write-Output "---"

Write-Output "Installing Clustering command line interfaces..."
$existingClusterCliFeature = Get-WindowsFeature -Name RSAT-Clustering-PowerShell 
if( $existingClusterCliFeature.Installed -ne $True)
{
    Install-WindowsFeature -Name RSAT-Clustering-PowerShell
    Install-WindowsFeature -Name RSAT-Clustering-CmdInterface
}
else
{
    Write-Output "Clustering CLI Features installed, already... skipping installation"
}

Write-Output "Getting full details about current computer with WMI..."
$computerDetails = Get-WmiObject -Class Win32_ComputerSystem
if($computerDetails -eq $null)
{
    throw "Failed retrieving computer details from witness machine; stopping!"
}
$computerName = $computerDetails.Name

Write-Output ("Getting cluster " + $paramAzureVirtualClusterName + "...")
$cluster = Get-Cluster -Name $paramAzureVirtualClusterName
if($cluster -eq $null)
{
    throw "Cluster " + $paramAzureVirtualClusterName + " not found! Stopping Execution!"
}

Write-Output "Add the Witness Share to the cluster quorum..."
Set-ClusterQuorum -InputObject $cluster -FileShareWitness "\\$computerName\$paramWitnessShareName"
$fileWitnessRes = (Get-ClusterResource -cluster sql1 | Where { $_.ResourceType -eq "File Share Witness" })
Move-ClusterResource -InputObject $cluster -Name ($fileWitnessRes.Name) -Group $paramSqlAvailabilityGroupName
Start-ClusterGroup -Name $paramSqlAvailabilityGroupName -InputObject $cluster

#
# END OF SCRIPT
# No further scripts to execute
#