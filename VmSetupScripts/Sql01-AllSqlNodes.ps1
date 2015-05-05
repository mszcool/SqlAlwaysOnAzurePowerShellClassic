#
# SQL Server Basic Configuration
# - Basic Setup (Firewall Rules etc.)
# - Cluster Creation
# - SQL Cluster (Enable AlwaysOn)
#

Param
(
    [Parameter(Mandatory)]
    [String]
    $scriptsBaseDirectory, 
    
    [Parameter(Mandatory)]
    [String]
    $certNamePwdEnc,

    [Parameter(Mandatory = $True)]
    [string]
    $domainNameShort, 

    [Parameter(Mandatory = $True)]
    [string]
    $domainNameLong,

    [Parameter(Mandatory = $True)]
    [string]
    $localAdminUser,

    [Parameter(Mandatory = $true)]
    [string]
    $localAdminPwdEnc,

    [Parameter(Mandatory = $True)]
    [string]
    $domainAdminUser,

    [Parameter(Mandatory = $true)]
    [string]
    $domainAdminPwdEnc,

    [Parameter(Mandatory)]
    [string]
    $dataDriveLetter,

    [Parameter(Mandatory)]
    [string]
    $dataDirectoryName,

    [Parameter(Mandatory)]
    [string]
    $logDirectoryName,

    [Parameter(Mandatory)]
    [string]
    $backupDirectoryName,

    [Parameter(Mandatory = $true)]
    [string]
    $paramClusterName,

    [Parameter(Mandatory = $true)]
    [string]
    $paramAzureVirtualClusterName,

    [Parameter(Mandatory = $true)]
    [string]
    $paramClusterIPAddress,

    [switch]
    $paramSetupNewCluster,

    [Parameter(Mandatory)]
    [string]
    $paramSqlInstanceName, 

    [Parameter(Mandatory)]
    [string]
    $paramSqlServiceUser,

    [Parameter(Mandatory)]
    [string]
    $paramSqlServicePasswordEnc,

    [Parameter(Mandatory)]
    [string]
    $paramSqlEndpointName,

    [Parameter(Mandatory)]
    [ValidateRange(1000,9999)]
    [UInt32]
    $paramSqlEndpointPort
)

Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "Basic SQL Server Setup and Cluster Setup on all nodes..." -ForegroundColor Green
Write-Host "---" -ForegroundColor Green
Write-Host ""

$IsVerbosePresent = ($PSBoundParameters["Verbose"] -eq $true)

#
# Change to the scripts directory to find the modules
#
cd $scriptsBaseDirectory

#
# Import the module that allows running PowerShell scripts easily as different user
#
Import-Module .\Util-PowerShellRunAs.psm1 -Force
Import-Module .\Util-CertsPasswords.psm1 -Force

#
# Make sure DNS caches are up2date
#
Write-Verbose -Message "Making sure DNS caches are up2date!"
Clear-DnsClientCache
Register-DnsClient

#
# Decrypt encrypted passwords using the passed certificate
#
Write-Verbose "Decrypting Password with Password Utility Module..."
$localAdminPwd = Get-DecryptedPassword -certName $certNamePwdEnc -encryptedBase64Password $localAdminPwdEnc 
$domainAdminPwd = Get-DecryptedPassword -certName $certNamePwdEnc -encryptedBase64Password $domainAdminPwdEnc 
Write-Verbose "Successfully decrypted VM Extension passed password"

#
# Preparing credentials object for later use
#
$usrDom = $domainNameShort + "\" + $domainAdminUser
$pwdSec = ConvertTo-SecureString $domainAdminPwd -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential($usrDom, $pwdSec)

$usrLocal = $env:COMPUTERNAME + "\" + $localAdminUser
$pwdSecLocal = ConvertTo-SecureString $localAdminPwd -AsPlainText -Force
$credsLocal = New-Object System.Management.Automation.PSCredential($usrLocal, $pwdSecLocal)

#
# SQL Server Node - Basic Setup
#
$scriptName = [System.IO.Path]::Combine($scriptsBaseDirectory, "Sql-Basic01-SqlBasic.ps1") 
Write-Host "Calling into $scriptName"
try {
    $arguments = "-domainNameShort $domainNameShort " + `
                 "-domainNameLong $domainNameLong " +  `
                 "-domainAdminUser $usrDom " +  `
                 "-dataDriveLetter $dataDriveLetter " +  `
                 "-dataDirectoryName $dataDirectoryName " +  `
                 "-logDirectoryName $logDirectoryName " +  `
                 "-backupDirectoryName $backupDirectoryName " 
    Invoke-PoSHRunAs -FileName $scriptName -Arguments $arguments -Credential $credsLocal -Verbose:($IsVerbosePresent) -LogPath ".\LogFiles" -NeedsToRunAsProcess
} catch {
    Write-Error $_.Exception.Message
    Write-Error $_.Exception.ItemName
    Write-Error ("Failed executing script " + $scriptName + "! Stopping Execution!")
    Exit
}

#
# SQL Server Node - Cluster Setup
# Note: Requires to run as domain account
#
$scriptName = [System.IO.Path]::Combine($scriptsBaseDirectory, "Sql-Basic02-ClusterSetup.ps1")
Write-Host "Calling into $scriptName (under the domain admin user)"
try {
    $arguments = " -paramClusterName $paramClusterName " + `
                 " -paramAzureVirtualClusterName $paramAzureVirtualClusterName " +  `
                 " -paramClusterIPAddress $paramClusterIPAddress "
    if($paramSetupNewCluster) {
        $arguments += " -paramSetupNewCluster"
    }
    Invoke-PoSHRunAs -FileName $scriptName -Arguments $arguments -Credential $creds -Verbose:($IsVerbosePresent) -LogPath ".\LogFiles" -NeedsToRunAsProcess
} catch {
    Write-Error $_.Exception.Message
    Write-Error $_.Exception.ItemName
    Write-Error ("Failed executing " + $scriptName + "! Stopping Execution!")
    Exit    
}

#
# Script for enabling AlwaysOn on the SQL Server Nodes and configuring the sql service to run under a domain account
#
try {
    $scriptName = [System.IO.Path]::Combine($scriptsBaseDirectory, "Sql-Basic03-ClusterSqlAlwaysOnSetup.ps1") 
    Write-Host "Calling into $scriptName"
    $arguments = "-paramSqlInstanceName `"$paramSqlInstanceName`" " + `
                 "-paramSqlServiceUser `"$paramSqlServiceUser`" " + `
                 "-paramSqlServicePasswordEnc `"$paramSqlServicePasswordEnc`" " + `
                 "-paramSqlPwdEncCertName $certNamePwdEnc " + `
                 "-paramSqlEndpointName `"$paramSqlEndpointName`" " + `
                 "-paramSqlEndpointPort `"$paramSqlEndpointPort`" "
    Invoke-PoSHRunAs -FileName $scriptName -Arguments $arguments -Credential $creds -Verbose:($IsVerbosePresent) -LogPath ".\LogFiles" -NeedsToRunAsProcess
} catch {
    Write-Error $_.Exception.Message
    Write-Error $_.Exception.ItemName
    Write-Error ("Failed executing script " + $scriptName + "! Stopping Execution!")
    Exit
}

Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "Basic SQL Server Setup Completed!" -ForegroundColor Green
Write-Host "---" -ForegroundColor Green
Write-Host ""

#
# END OF SCRIPT
#
