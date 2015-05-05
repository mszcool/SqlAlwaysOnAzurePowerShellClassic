#
# SQL Server Primary Node Configuration (before all others)
# - Creates a file share on the Witness node
# - Adds the Witness to the cluster configuration
# - Updates the cluster quorum settings
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
    $domainAdminUser,

    [Parameter(Mandatory = $true)]
    [string]
    $domainAdminPwdEnc,

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

Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "SQL Server WITNESS Node Configuration..." -ForegroundColor Green
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
# Decrypt encrypted passwords using the passed certificate
#
Write-Verbose "Decrypting Password with Password Utility Module..."
$domainAdminPwd = Get-DecryptedPassword -certName $certNamePwdEnc -encryptedBase64Password $domainAdminPwdEnc 
Write-Verbose "Successfully decrypted VM Extension passed password"
    
#
# Preparing credentials object for later use
#
$usrDom = $domainNameShort + "\" + $domainAdminUser
$pwdSec = ConvertTo-SecureString $domainAdminPwd -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential($usrDom, $pwdSec)

#
# Setting up Witness and Cluster Quorum...
# Note: this needs to run under a domain account since it needs access to other sql servers as well
#
try {
    $scriptName = [System.IO.Path]::Combine($scriptsBaseDirectory, "Sql-Witness01-Prepare.ps1")
    Write-Host "Calling into $scriptName (under the domain admin user)"
    $arguments =  "-paramWitnessFolderName `"$paramWitnessFolderName`" " + `
                  "-paramWitnessShareName `"$paramWitnessShareName`" " + `
                  "-paramSqlServiceAccount `"$paramSqlServiceAccount`" " +  `
                  "-paramAzureVirtualClusterName `"$paramAzureVirtualClusterName`" " + `
                  "-paramSqlAvailabilityGroupName `"$paramSqlAvailabilityGroupName`" "
    Invoke-PoSHRunAs -FileName $scriptName -Arguments $arguments -Credential $creds -Verbose:($IsVerbosePresent) -LogPath ".\LogFiles" -NeedsToRunAsProcess
} catch {
    Write-Error $_.Exception.Message
    Write-Error $_.Exception.ItemName
    Write-Error ("Failed executing " + $scriptName + "! Stopping Execution!")
    Exit
}


Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "SQL Server WITNESS NODE Configuration Completed!" -ForegroundColor Green
Write-Host "---" -ForegroundColor Green
Write-Host ""

#
# END OF SCRIPT
#
