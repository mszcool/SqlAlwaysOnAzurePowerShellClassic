#
# AD DC Forest Setup
# - Target:  The first AD Domain Controller in the forest
# - Tasks:   Installs Active Directory Domain Services Feature
#            Provisions a new AD DS Forest with the target server as the first and primary DC
#

Param
(
    [Parameter(Mandatory)]
    $domainName,

    [Parameter(Mandatory)]
    $domainNameShort,

    [Parameter(Mandatory)]
    $domainAdminPwdEnc,
    
    [Parameter(Mandatory)]
    $certNamePwdEnc
)

Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "Primary AD Forest Setup..." -ForegroundColor Green
Write-Host "---" -ForegroundColor Green
Write-Host ""

Write-Verbose "Decrypting Password with Password Utility Module..."
Import-Module .\Util-CertsPasswords.psm1
$domainAdminPwd = Get-DecryptedPassword -certName $certNamePwdEnc -encryptedBase64Password $domainAdminPwdEnc 
Write-Verbose "Successfully decrypted VM Extension passed password"

Write-Verbose -Message "Setting Up AD-Domain-Services feature..."
Install-WindowsFeature AD-Domain-Services
Import-Module -Name ADDSDeployment  

Write-Verbose -Message "Parameters for Domain Setup:"
Write-Host "- domainName = $domainName"
Write-Host "- domainNameShort = $domainNameShort"
$domainAdminPwdSec = (ConvertTo-SecureString $domainAdminPwd -AsPlainText -Force)

Write-Host "Checking if the AD Forest does exist, already..."
$existingForestCheck = $true 
try {
    Get-ADForest -Current LocalComputer -ErrorAction SilentlyContinue
} catch {
    $existingForestCheck = $false
}
if($existingForestCheck) {
    Write-Host "AD Forest exists, already. Skipping creation..."
    Write-Host "Checking if forest belongs to existing domain..."
} else {
    Write-Host "Configuring AD promotion parameters..."
    $params = @{ DomainName = $domainName; `
                 DomainNetbiosName = $domainNameShort; `
                 SafeModeAdministratorPassword = ($domainAdminPwdSec); `
                 InstallDns = $true; Force = $true }
    
    Write-Host "Provisioning the new AD forest with parameters..."
    Install-ADDSForest @params
}

Write-Host ""
Write-Host "---" -ForegroundColor Green
Write-Host "Done Primary AD Forest Setup!" -ForegroundColor Green
Write-Host "---" -ForegroundColor Green
Write-Host ""

#
# END OF SCRIPT
#
