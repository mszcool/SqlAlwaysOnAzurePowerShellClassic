#
# AD DC Secondary DC Setup
# - Target:  All Secondary DCs in the Forest
# - Tasks:   Installs Active Directory Domain Services Feature
#            Provisions the member server as a secondary AD DC in the forest
#

Param
(
    [Parameter(Mandatory)]
    $domainName,

    [Parameter(Mandatory)]
    $domainAdminName,

    [Parameter(Mandatory)]
    $domainAdminPwdEnc,
    
    [Parameter(Mandatory)]
    $certNamePwdEnc,

    [Parameter(Mandatory = $false)]
    $findDomainRetryCount = 20, 

    [Parameter(Mandatory = $false)]
    $findDomainRetryIntervalSecs = 60
)

Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "Secondary AD Domain Controller Setup..." -ForegroundColor Green
Write-Host "---" -ForegroundColor Green
Write-Host ""

Write-Verbose "Decrypting Password with Password Utility Module..."
Import-Module .\Util-CertsPasswords.psm1
$domainAdminPwd = Get-DecryptedPassword -certName $certNamePwdEnc -encryptedBase64Password $domainAdminPwdEnc 
Write-Verbose "Successfully decrypted VM Extension passed password"
    
Write-Verbose -Message "Reset DNS Cache..."
Clear-DnsClientCache
Register-DnsClient

Write-Verbose -Message "Setting Up AD-Domain-Services feature..."
Install-WindowsFeature AD-Domain-Services
Import-Module -Name ADDSDeployment  

Write-Verbose -Message "Parameters for Domain Setup:"
Write-Host "- domainName = $domainName"
Write-Host "- domainAdmin = $domainAdminName"
$domainAdminPwdSec = (ConvertTo-SecureString $domainAdminPwd -AsPlainText -Force)
$domainAdminCreds = New-Object System.Management.Automation.PSCredential($domainAdminName, $domainAdminPwdSec)

Write-Host "Waiting for the Domain to become accessible (e.g. updating DNS Records etc.)..."
$domainFound = $false
Write-Verbose -Message "Checking for domain $domainName ..."
for($count = 0; $count -lt $findDomainRetryCount; $count++)
{
    try
    {
        $domain = Get-ADDomain -Identity $domainName -Credential $domainAdminCreds
        Write-Verbose -Message "Found domain $domainName"
        $domainPrimaryDC = Get-ADDomainController -Discover -Domain $domainName -Service "PrimaryDC","TimeService"
        Write-Verbose -Message "Found primary domain controller!"
        $domainFound = $true
        break;
    }
    Catch
    {
        Write-Verbose -Message "Domain $DomainName not found. Will retry again after $findDomainRetryIntervalSecs sec"
        Start-Sleep -Seconds $findDomainRetryIntervalSecs
    }
}
if(-not $domainFound) {
    throw "Was unable to find the domain $domainName after $findDomainRetryCount attempts with an interval of $findDomainRetryIntervalSecs seconds. Stopping!"
}

Write-Host "Checking if machine is a domain controller, already..."
$dcMachine = Get-WmiObject -Class Win32_ComputerSystem
$dcMachineController = $null
try {
    $dcMachineController = (Get-ADDomainController -Credential $domainAdminCreds | Where-Object { $_.Name -eq $dcMachine.Name})
} catch { 
    Write-Verbose -Message "Failed getting ADDC machine. Indicates setup is not done on this machine!"
}
if($dcMachineController -ne $null) {
    Write-Host "-- Skipping promotion to AD Domain Controller as machine is a DC, already!"
} else {
    Write-Host "-- Promoting VM to a domain controller"
    Install-ADDSDomainController -DomainName $domainName `
            -Force:$true `
            -SafeModeAdministratorPassword $domainAdminPwdSec `
            -Credential $domainAdminCreds `
            -Verbose:($isVerbose)        

    Write-Host "-- Restarting Computer"
}

Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "Done Primary AD Forest Setup!" -ForegroundColor Green
Write-Host "---" -ForegroundColor Green
Write-Host ""

#
# END OF SCRIPT
#
