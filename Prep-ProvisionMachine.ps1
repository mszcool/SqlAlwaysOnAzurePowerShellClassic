##############################################################################
# Prepares a machine used for provisioning a SQL AlwaysOn Availability Group #
# - Installs Powershell Modules into the local Directory                     #
# - Creates a new certificate or imports the default certificate             #
##############################################################################
Param
(
	[Switch]
	$importDefaultCertificate,
	
	[Switch]
	$overwriteExistingCerts
)

Write-Host "First copy PowerShell modules to documents folder..."
$targetPowershellModulesFolder = [System.IO.Path]::Combine(([Environment]::GetFolderPath("MyDocuments")), "WindowsPowerShell", "Modules")
if(-not (Test-Path $targetPowershellModulesFolder)) {
	Write-Host "Creating PowerShell Modules folder since it does not exist!"
	New-Item -ItemType Directory $targetPowershellModulesFolder
}
Copy-Item ".\Util-AzureProvision" $targetPowershellModulesFolder -Recurse -Force
Copy-Item ".\Util-CertsPasswords" $targetPowershellModulesFolder -Recurse -Force
Copy-Item ".\AzureNetworking" $targetPowershellModulesFolder -Recurse -Force
Write-Host "Done copying PowerShell Modules!"
	
Write-Host ""
Write-Host "Creating a Certificate for password encryption with Azure VM Extensions if requested, otherwise import default certificate in store..."
Import-Module Util-CertsPasswords -Force
if($importDefaultCertificate) {
	Write-Host "Importing default certificate for password encryption..."
	$pfxFile = ".\sqlagcert.default.pfx"
	$pfxPassword = (ConvertTo-SecureString -String "pass@word1" -AsPlainText -Force)
	$pfxCred = New-Object System.Management.Automation.PSCredential("no user name needed", $pfxPassword)
	Add-SelfSignedCertificateToStore -pfxFileToImport ".\sqlagcert.default.pfx" -pfxFilePassword $pfxCred 
	
	$certNameToUse = "sqlagcert.default"
} else {
	Write-Host "Creating new certificate and importing it into the store..."
	Write-Host "Please enter now a certificate name and a password to protect the exported private key!"
	$certNameAndPassword = Get-Credential -Message "Please enter now a certificate name and a password to protect the exported private key!"
	if($overwriteExistingCerts) {
		New-SelfSignedCertificateWithExport -certNameAndExportPassword $certNameAndPassword -deleteExistingCert
	} else {
		New-SelfSignedCertificateWithExport -certNameAndExportPassword $certNameAndPassword
	}
	
	$certNameToUse = ($certNameAndPassword.UserName)
}

try {
	Write-Host ""
	Write-Host "Testing the certificate for encryption/decryption with the phrase 'test@phrase1'..."
	$decryptedContent = "test@phrase1"
	$encryptedContent = Get-EncryptedPassword -certName $certNameToUse -passwordToEncrypt $decryptedContent
	Write-Host "Encrypted Content:"
	Write-Host $encryptedContent
	Write-Host "Decryptinng Content again..."
	$newDecryptedContent = Get-DecryptedPassword -certName $certNameToUse -encryptedBase64Password $encryptedContent
	Write-Host "Decrypted Content:"
	Write-Host $newDecryptedContent
} catch {
	Write-Error "Failed encrypting/decrypting content. Please check your certificate stores and make sure the certificate is really there!"
}