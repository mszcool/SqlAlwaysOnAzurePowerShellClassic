#
# SQL Server Primary Node Configuration (before all others)
# - Create AlwaysOn Availability Group
# - Prepare Databases for joining the AG on secondary nodes (i.e. backup, backup log)
# - Setup the AG Listener on the Azure Load Balancer
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

    [Parameter()]
    [string]
    $paramCommitMode = "Synchronous_Commit",
        
    [Parameter()]
    [string]
    $paramFailoverMode = "Automatic",
    
    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramSqlAlwaysOnLocalEndPoint,

    [Parameter(Mandatory)]
    [string]
    $paramDatabaseNames,

    [Parameter(Mandatory)]
    [string]
    $paramPrimarySqlNode,

    [Parameter(Mandatory)]
    [string]
    $paramSecondarySqlNodes,

    [switch]
    $paramCreateDatabases,

    [Parameter(Mandatory=$false)]
    [string]
    $paramCreateDatabasesSqlScriptFileNames,

    [Parameter(Mandatory)]
    [string]
    $paramStorageAccountName,

    [Parameter(Mandatory)]
    [string]
    $paramStorageAccountKeyEnc,

    [Parameter(Mandatory)]
    [string]
    $paramStorageAccountBackupContainer,

    [Parameter(Mandatory)]
    [string]
    $paramPrimaryILBIP,

    [Parameter(Mandatory)]
    [string]
    $paramPrimaryILBIPSubnetMask,

    [Parameter(Mandatory)]
    [string]
    $paramSecondaryILBIP,

    [Parameter(Mandatory)]
    [string]
    $paramSecondaryILBIPSubnetMask,

    [Parameter(Mandatory)]
    [string]
    $paramProbePort,

    [Parameter(Mandatory)]
    [string]
    $paramAGListenerName,

    [Parameter(Mandatory)]
    [string]
    $paramPrimaryClusterNetworkName,

    [Parameter(Mandatory)]
    [string]
    $paramSecondaryClusterNetworkName
)

Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "SQL Server Primary Node Configuration..." -ForegroundColor Green
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
$paramStorageAccountKey = Get-DecryptedPassword -certName $certNamePwdEnc -encryptedBase64Password $paramStorageAccountKeyEnc 
Write-Verbose "Successfully decrypted VM Extension passed password"
    
#
# Preparing credentials object for later use
#
$usrDom = $domainNameShort + "\" + $domainAdminUser
$pwdSec = ConvertTo-SecureString $domainAdminPwd -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential($usrDom, $pwdSec)

#
# Creating Database AlwaysOn Setup...
# Note: this needs to run under a domain account since it needs access to other sql servers as well
#
try {
    $scriptName = [System.IO.Path]::Combine($scriptsBaseDirectory, "Sql-Ag01-CreateDBAlwaysOnSetup.ps1")
    Write-Host "Calling into $scriptName (under the domain admin user)"
    $arguments =  "-paramHaGroupName `"$paramHaGroupName`" " + `
                  "-paramClusterName `"$paramClusterName`" " +  `
                  "-paramSqlAlwaysOnLocalEndPoint `"$paramSqlAlwaysOnLocalEndPoint`" " + `
                  "-paramDatabaseNames `"$paramDatabaseNames`" " + `
                  "-paramPrimarySqlNode `"$paramPrimarySqlNode`" " + `
                  "-paramSecondarySqlNodes `"$paramSecondarySqlNodes`" " + `
                  "-paramCreateDatabasesSqlScriptFileNames `"$paramCreateDatabasesSqlScriptFileNames`" " + `
                  "-paramStorageAccountName `"$paramStorageAccountName`" " + `
                  "-paramStorageAccountKey `"$paramStorageAccountKey`" " + `
                  "-paramStorageAccountBackupContainer `"$paramStorageAccountBackupContainer`""
    if($paramCreateDatabases) {
        $arguments += " -paramCreateDatabases "
    }
    Invoke-PoSHRunAs -FileName $scriptName -Arguments $arguments -Credential $creds -Verbose:($IsVerbosePresent) -LogPath ".\LogFiles" -NeedsToRunAsProcess
} catch {
    Write-Error $_.Exception.Message
    Write-Error $_.Exception.ItemName
    Write-Error ("Failed executing " + $scriptName + "! Stopping Execution!")
    Exit
}


#
# Configuring the AlwaysOn Availability Group Listener
#
try {
    $scriptName = [System.IO.Path]::Combine($scriptsBaseDirectory, "Sql-Ag02-DatabaseSetupAGListener.ps1")
    Write-Host "Calling into $scriptName (under the domain admin user)"
    $arguments =  "-paramHaGroupName `"$paramHaGroupName`" " + `
                  "-paramClusterName `"$paramClusterName`" " +  `
                  "-paramPrimarySqlNode `"$paramPrimarySqlNode`" " + `
                  "-paramPrimaryILBIP $paramPrimaryILBIP " + `
                  "-paramPrimaryILBIPSubnetMask $paramPrimaryILBIPSubnetMask " + `
                  "-paramSecondaryILBIP $paramSecondaryILBIP " + `
                  "-paramSecondaryILBIPSubnetMask $paramSecondaryILBIPSubnetMask " + `
                  "-paramProbePort $paramProbePort " + `
                  "-paramAGListenerName `"$paramAGListenerName`" " + `
                  "-paramPrimaryClusterNetworkName `"$paramPrimaryClusterNetworkName`" " + `
                  "-paramSecondaryClusterNetworkName `"$paramSecondaryClusterNetworkName`" "
    if($IsVerbosePresent) {
        $arguments += " -Verbose "
    }
    Invoke-PoSHRunAs -FileName $scriptName -Arguments $arguments -Credential $creds -Verbose:($IsVerbosePresent) -LogPath ".\LogFiles" -NeedsToRunAsProcess
} catch {
    Write-Error $_.Exception.Message
    Write-Error $_.Exception.ItemName
    Write-Error ("Failed executing " + $scriptName + "! Stopping Execution!")
    Exit
}

Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "SQL Server PRIMARY NODE Configuration Completed!" -ForegroundColor Green
Write-Host "---" -ForegroundColor Green
Write-Host ""

#
# END OF SCRIPT
#
