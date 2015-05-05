######################################################################
# Utility functions encrypting/decryping passwords with Certificates #
######################################################################

$makeCertPaths = @(
	"C:\Program Files (x86)\Windows Kits\10\bin\x64\makecert.exe",
	"C:\Program Files (x86)\Windows Kits\10\bin\x86\makecert.exe",
	"C:\Program Files (x86)\Windows Kits\8.1\bin\x64\makecert.exe",
	"C:\Program Files (x86)\Windows Kits\8.1\bin\x86\makecert.exe",
	"C:\Program Files (x86)\Windows Kits\8.0\bin\x64\makecert.exe",
	"C:\Program Files (x86)\Windows Kits\8.0\bin\x86\makecert.exe",
	"C:\Program Files (x86)\Microsoft SDKs\Windows\v7.1A\Bin\x64\makecert.exe", 
	"C:\Program Files (x86)\Microsoft SDKs\Windows\v7.1A\Bin\makecert.exe"
)

#
# Imports a PFX File into the certificate store
#
function Add-SelfSignedCertificateToStore {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[string]
		$pfxFileToImport,
		
		[Parameter(Mandatory)]
		[PSCredential]
		$pfxFilePassword
	)
	
	$certUtilExe = "certutil.exe"
	$certImportPassword = ($pfxFilePassword.GetNetworkCredential().Password) 
	& $certUtilExe -f -p $certImportPassword -importpfx $pfxFileToImport
}

#
# Creates a self-signed certificate and exports the certificate including the private key
#
function New-SelfSignedCertificateWithExport {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[PSCredential]
		$certNameAndExportPassword, 
		
		[Parameter(Mandatory=$false)]
		[String]
		$exportFileLocation = ".\",
		
		[Switch]
		$deleteExistingCert
	)
	
	try {
		Write-Verbose -Message "Extracting DNS name from user name property of credential..."
		$certName = $certNameAndExportPassword.UserName
		Write-Verbose -Message "Using DNS name $certName for certificate!"
		
		Write-Verbose -Message "Checking if Certificate with DNS name exists, already..."
		$cert = (Get-ChildItem -Path Cert:\LocalMachine\My | Where { $_.Subject -eq "CN=$certName" }) 
		if($cert -ne $null) 
		{
			if(-not $deleteExistingCert) {
				throw ("Existing Certificate with the following DnsName exists, already! Delete the existing certificate with the DNS Name = '" + $certName + "'!")
			} else {
				Write-Verbose -Message "Removing existing certificate!"
				$cert | Remove-Item
			}
		}
		
		Write-Verbose -Message "Creating new self-signed certificate..."
		Write-Verbose -Message "- Finding makecert.exe on your machine..."
		$makecertExe = ""
		foreach($mp in $makeCertPaths) {
			if(Test-Path $mp) {
				Write-Verbose -Message "- Found makecert.exe at $mp..."
				$makecertExe = $mp
				break
			}
		}
		if([String]::IsNullOrEmpty($makecertExe)) {
			throw "makecert.exe was not found in one of the typical locations on your machine. Make sure you have one of the Windows SDKs (7.0, 8.x, 10) installed so that makecert.exe is available on your machine!"
		} else {
			Write-Verbose -Message "- Using $makecertExe"
		}
		Write-Verbose -Message "- Executing makecert -sky exchange -r -n `"CN=$certName`" -pe -a sha1 -len 2048 -sr LocalMachine -ss My"
		& $makecertExe -sky exchange -r -n "CN=$certName" -pe -a sha1 -len 2048 -sr LocalMachine -ss My
		
		Write-Verbose -Message "Exporting certificate..."
		if(-not (Test-Path $exportFileLocation)) {
			Write-Verbose -Message "Creating target directory for certificate export..."
			New-Item -ItemType Directory $exportFileLocation
		}
		
		Write-Verbose -Message "Retrieving the created certificate from the store..."
		$cert = (Get-ChildItem -Path Cert:\LocalMachine\My | Where { $_.Subject -eq "CN=$certName" })
		if($cert -eq $null) {
			throw "Failed finding certificate in store after it should have been created!"
		}
		
		if([System.IO.Path]::IsPathRooted($exportFileLocation)) {
			$exportCertFileName = [System.IO.Path]::Combine($exportFileLocation, "$certName.pfx")
		} else {
			$exportCertFileName = [System.IO.Path]::Combine((Get-Location), $exportFileLocation, "$certName.pfx")
		}
		Write-Verbose -Message "Exporting Certificate with file name $exportCertFileName..."
		[System.IO.File]::WriteAllBytes( `
			                 $exportCertFileName, `
							 $cert.Export('PFX', $certNameAndExportPassword.GetNetworkCredential().Password))
		if(-not (Test-Path $exportCertFileName)) {
			throw "Failed exporting the certificate File!!"
		}
		
		Write-Verbose -Message "Successfully exported certificate file!"
	} catch {
	    Write-Error $_.Exception.Message
	    Write-Error $_.Exception.ItemName
	    throw "Failed loading configuration file! Please see if you have any errors or if the file does not exist!"    
	}
}


#
# Gets a self-signed certificate by its domain name prefix as created with the previous function
#
function Get-SelfSignedCertificateByName
{
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory)]
		[string]
		$certName
	)
	
	Write-Verbose -Message "Retrieving certificate for DNS Name CN=$certName..."
	$cert = (Get-ChildItem -Path Cert:\LocalMachine\My | Where { $_.Subject -eq "CN=$certName" })
	if($cert -eq $null) {
		Write-Verbose -Message "Certificate CN=$certName does not exist!"
	}
	return $cert
}


#
# Encrypts the password with a self-signed certificate and returns the encrypted password
#
function Get-EncryptedPassword {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $false)]
		[String]
		$certName, 
		
		[Parameter(Mandatory = $false)]
		$certificate,
		
		[Parameter(Mandatory)]
		[String]
		$passwordToEncrypt
	)
	
	#
	# If the certificate has been passed in, we do not need to retrieve one
	#
	Write-Verbose -Message "Validating parameters..."
	if($certificate -eq $null) {
		if([String]::IsNullOrEmpty($certName)) {
			throw "You need to either pass -certificate <X509Certificate2> or -certName <string> into the function!"
		}
		$certToUse = Get-SelfSignedCertificateByName -certName $certName
	} else {
		$certToUse = $certificate
	}

	if($certToUse -eq $null) {
		throw "Certificate cannot be null or Certificate cannot be found in Certificate Store!"
	}
	
	#
	# Next let's encrypt the data
	#
	Write-Verbose -Message "Encrypting password with Certificate..."
	$passwordBytes = [Text.Encoding]::UTF8.GetBytes($passwordToEncrypt)
	$encryptedPwd = $certToUse.PublicKey.Key.Encrypt($passwordBytes, $true)
	Write-Verbose -Message "Password encrypted, now converting to base64 encoded string..."
	$base64Pwd = [Convert]::ToBase64String($encryptedPwd)
	
	Write-Verbose -Message "Done, encrypted password string $base64Pwd"
	return $base64Pwd
}


#
# Decrypts a password using the private key of the certificate
#
function Get-DecryptedPassword {
	[CmdletBinding()]
	Param(
		[Parameter(Mandatory = $false)]
		[String]
		$certName, 
		
		[Parameter(Mandatory = $false)]
		$certificate,
		
		[Parameter(Mandatory)]
		[string]
		$encryptedBase64Password
	)
	
		#
	# If the certificate has been passed in, we do not need to retrieve one
	#
	Write-Verbose -Message "Validating parameters..."
	if($certificate -eq $null) {
		if([String]::IsNullOrEmpty($certName)) {
			throw "You need to either pass -certificate <X509Certificate2> or -certName <string> into the function!"
		}
		$certToUse = Get-SelfSignedCertificateByName -certName $certName
	} else {
		$certToUse = $certificate
	}

	if($certToUse -eq $null) {
		throw "Certificate cannot be null or Certificate cannot be found in Certificate Store!"
	}
	if($certToUse.PrivateKey -eq $null) {
		throw "Certificate Private key is missing. Make sure the certificate does have a private key!"
	}
	
	#
	# Next start the decryption of the password
	#
	$encryptedPwd = [Convert]::FromBase64String($encryptedBase64Password)
	$decryptedPwdBytes = $certToUse.PrivateKey.Decrypt($encryptedPwd, $true)
	$decryptedPwd = [Text.Encoding]::UTF8.GetString($decryptedPwdBytes)
	
	return $decryptedPwd
}