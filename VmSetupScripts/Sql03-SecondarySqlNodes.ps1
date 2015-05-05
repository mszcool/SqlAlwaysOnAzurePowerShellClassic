#
# SQL Server Secondary Node Configuration (after Primary Node is done)
# - Joins the AlwaysOn Availability Group
# - Restores the databases and synchronizes them with Primary
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

    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramHaGroupName,

    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramClusterName,

    [parameter(Mandatory)]
    [ValidateNotNull()]
    [string]
    $paramDatabaseNames,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramBackupStorageAccountName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramBackupStorageAccountBackupContainer,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramSqlInstanceToAdd,

    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramSqlAlwaysOnLocalEndpoint,
        
    [Parameter()]
    [string]
    $paramCommitMode = "Synchronous_Commit",
        
    [Parameter()]
    [string]
    $paramFailoverMode = "Automatic"
)

Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "SQL Server SECONDARY Node Configuration..." -ForegroundColor Green
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
# Joining Database AlwaysOn Setup...
# Note: this needs to run under a domain account since it needs access to other sql servers as well
#
try {
    $scriptName = [System.IO.Path]::Combine($scriptsBaseDirectory, "Sql-AgJoin01-JoinDBAlwaysOnSetup.ps1")
    Write-Host "Calling into $scriptName (under the domain admin user)"
    $arguments =  "-paramHaGroupName `"$paramHaGroupName`" " + `
                  "-paramDatabaseNames `"$paramDatabaseNames`" " + `
                  "-paramClusterName `"$paramClusterName`" " +  `
                  "-paramBackupStorageAccountName `"$paramBackupStorageAccountName`" " + `
                  "-paramBackupStorageAccountBackupContainer `"$paramBackupStorageAccountBackupContainer`" " + `
                  "-paramSqlInstanceToAdd `"$paramSqlInstanceToAdd`" " + `
                  "-paramSqlAlwaysOnLocalEndPoint `"$paramSqlAlwaysOnLocalEndPoint`" " + `
                  "-paramCommitMode `"$paramCommitMode`" " + `
                  "-paramFailoverMode `"$paramFailoverMode`" " 
    Invoke-PoSHRunAs -FileName $scriptName -Arguments $arguments -Credential $creds -Verbose:($IsVerbosePresent) -LogPath ".\LogFiles" -NeedsToRunAsProcess
} catch {
    Write-Error $_.Exception.Message
    Write-Error $_.Exception.ItemName
    Write-Error "Failed executing " + $scriptName + "! Stopping Execution!"
    Exit
}


Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "SQL Server SECONDARY NODE Configuration Completed!" -ForegroundColor Green
Write-Host "---" -ForegroundColor Green
Write-Host ""

#
# END OF SCRIPT
#
