#
# Automation Workflow for 
# provisioning a multi-region SQL Server AlwaysOn Availability Group cluster
# - This script is the central provisioning workflow script
# - The script makes use of VM Extensions to execute further scripts in created VMs
# - The script creates all required dependent resources.
# Note: future versions of this will replace the main workflow with Cloud Resource Provider Templates
#
[CmdletBinding()]
Param (	
	[Switch] 
	$SetupNetwork, 
	
	[Switch] 
	$SetupADDCForest,

    [Switch]
    $SetupSecondaryADDCs,
	
	[Switch] 
	$SetupSQLVMs,

    [Switch]
    $SetupSQLAG,

    [Switch]
    $SetupAzureAccount,

    [Switch]
    $UploadSetupScripts,

    [Parameter(Mandatory=$false)]
    [String]
    $ConfigFile = ".\Main-ProvisionConfig.psd1",

    [Parameter(Mandatory=$false)] 
    [String]
    $AzureSubscriptionName = $null,

    [Parameter(Mandatory=$false)]
    [PSCredential]
    $AzureManagementCredentials,
    
    [Parameter(Mandatory=$true)] 
    [String] 
    $ServiceName,

    [Parameter(Mandatory=$true)] 
    [String] 
    $StorageAccountNamePrimaryRegion,
    
    [Parameter(Mandatory=$true)] 
    [String] 
    $StorageAccountNameSecondaryRegion,
 
	[Parameter(Mandatory=$false)] 
	[ValidateSet("North Europe",
		"West Europe","East US 2",
		"Central US","South Central US",
		"West US","North Central US",
		"East US","Southeast Asia",
		"East Asia","Japan West",
		"Japan East","Brazil South",
		"Australia Southeast","Australia East")]
	[String]
	$RegionPrimary = "",
		
	[Parameter(Mandatory=$false)] 
	[ValidateSet("North Europe",
		"West Europe","East US 2",
		"Central US","South Central US",
		"West US","North Central US",
		"East US","Southeast Asia",
		"East Asia","Japan West",
		"Japan East","Brazil South",
		"Australia Southeast","Australia East")]
	[String]
	$RegionSecondary = "",
	
	[Parameter(Mandatory=$false)] 
	[String] 
	[ValidateSet("A5","A6","A7","A8","A9","Basic_A0","Basic_A1","Basic_A2","Basic_A3","Basic_A4","ExtraLarge","ExtraSmall","Large","Medium","Small","SQLG3","Standard_D1","Standard_D11","Standard_D12","Standard_D13","Standard_D14","Standard_D2","Standard_D3","Standard_D4")]
	$VmSizeAdDc = "Medium",
	
	[Parameter(Mandatory=$false)] 
	[String] 
	[ValidateSet("A5","A6","A7","A8","A9","Basic_A0","Basic_A1","Basic_A2","Basic_A3","Basic_A4","ExtraLarge","ExtraSmall","Large","Medium","Small","SQLG3","Standard_D1","Standard_D11","Standard_D12","Standard_D13","Standard_D14","Standard_D2","Standard_D3","Standard_D4")]
	$VmSizeSql = "ExtraLarge",
	
	[Parameter(Mandatory=$false)] 
	[String] 
	[ValidateSet("A5","A6","A7","A8","A9","Basic_A0","Basic_A1","Basic_A2","Basic_A3","Basic_A4","ExtraLarge","ExtraSmall","Large","Medium","Small","SQLG3","Standard_D1","Standard_D11","Standard_D12","Standard_D13","Standard_D14","Standard_D2","Standard_D3","Standard_D4")]
	$VmSizeSqlWitness = "Small",
		
    [Parameter(Mandatory=$false)]
    [PSCredential]
    $DomainAdminCreds = $null,

    [Parameter(Mandatory=$true)]
    [String]
    $DomainName,

    [Parameter(Mandatory=$true)]
    [String]
    $DomainNameShort,
	
    [switch]
    $RemoteDesktopCreate,

	[Parameter(Mandatory=$false)] 
	[String]
	$RemoteDesktopOutputPath = ".\RemoteDesktop",
    
    [Parameter(Mandatory=$false)]
    [PSCredential]
    $certDetailsForPwdEncryption = $null,
    
    [Parameter(Mandatory=$false)]
    [string]
    $certPfxFileForPwdEncryption = ".\sqlagcert.default.pfx"
)

Write-Host ""
Write-Host "******************************************************************************" -ForegroundColor Green
Write-Host "** Cross-Region SQL Server AlwaysOn Availability Group Setup *****************" -ForegroundColor Green
Write-Host "******************************************************************************" -ForegroundColor Green

$IsVerbosePresent = ($PSBoundParameters["Verbose"] -eq $true)
Write-Verbose -Message "Running in Verbose Mode: $IsVerbosePresent"

Write-Verbose -Message "Setting default values for password encryption certificate parameter..."
if($certDetailsForPwdEncryption -eq $null) {
    Write-Verbose -Message "- No certificate passed in, using default certificate!"
    $certNameForPwdEncryption = "sqlagcert.default"
    $certPfxPwdForPwdEncryption = ConvertTo-SecureString "pass@word1" -AsPlainText -Force
    $certDetailsForPwdEncryption = New-Object System.Management.Automation.PSCredential ($certNameForPwdEncryption, $certPfxPwdForPwdEncryption)
} else {
    Write-Verbose -Message "- Reading certificate name from passed credentials!"
    $certNameForPwdEncryption = $certDetailsForPwdEncryption.UserName
    $certPfxPwdForPwdEncryption = $certDetailsForPwdEncryption.Password
}

$startTime = (Get-Date)
Write-Host "- Start Time:            $startTime"
Write-Host "- Setup Fundamentals:    ALWAYS"
Write-Host "- Upload Setup Scripts:  $UploadSetupScripts"
Write-Host "- Setup Networking:      $SetupNetwork"
Write-Host "- Setup AD Forest:       $SetupADDCForest"
Write-Host "- Setup Secondary ADDCs: $SetupSecondaryADDCs"
Write-Host "- Setup SQL VMs:         $SetupSQLVMs"
Write-Host "- Setup SQL AG:          $SetupSQLAG"
Write-Host "- Cert for PWD-Encrypt:  $certNameForPwdEncryption"
Write-Host "- Cert PFX PWD-Encrypt:  $certPfxFileForPwdEncryption"

Write-Host "******************************************************************************" -ForegroundColor Green
Write-Host ""


#
# Module Verifications and Imports
#
Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Module Imports..."
Write-Host "----------------------------------------------------------------------"

$moduleAzure = Get-Module -ListAvailable Azure
if($moduleAzure -eq $null) {
    throw "Module not found: Microsoft Azure PowerShell!"
}

$moduleNetworkingIsLocal = $false
$moduleNetworking = Get-Module -ListAvailable AzureNetworking
if($moduleNetworking -eq $null) {
    Write-Verbose -Message "Module AzureNetworking not found in global context, trying local relative path..."
    $moduleNetworkingIsLocal = $true
}

$moduleAzureUtilIsLocal = $false
$moduleAzureUtil = Get-Module -ListAvailable Util-AzureProvision
if($moduleAzureUtil -eq $null) {
    Write-Verbose -Message "Module Util-AzureProvision not found in global context, trying local relative path..."
    $moduleAzureUtilIsLocal = $true
}

$moduleCertsPwdIsLocal = $false
$moduleCertsPwd = Get-Module -ListAvailable Util-CertsPasswords
if($moduleCertsPwd -eq $null) {
    Write-Verbose -Message "Module Util-CertsPasswords not found in global context, trying local relative path..."
    $moduleCertsPwdIsLocal = $true
}

Import-Module Azure
if($moduleNetworkingIsLocal) {
    Import-Module .\AzureNetworking -Force -ErrorAction Stop
} else {
    Import-Module AzureNetworking -Force -ErrorAction Stop
}
if($moduleAzureUtilIsLocal) {
    Import-Module .\Util-AzureProvision -Force -ErrorAction Stop
} else {
    Import-Module Util-AzureProvision -Force -ErrorAction Stop
}
if($moduleCertsPwdIsLocal) {
    Import-Module .\Util-CertsPasswords -Force -ErrorAction Stop
} else {
    Import-Module Util-CertsPasswords -Force -ErrorAction Stop
}
Write-Verbose -Message "Module Imports done..."

#
# Reading configuration settings
#
Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Loading configuration data from .\$ConfigFile..."
Write-Host "----------------------------------------------------------------------"

if( (Test-Path "$ConfigFile") -eq $false) {
    throw "Configuration file not found: " + $ConfigFile   
}
try {
    $configFileContent = Get-Content $ConfigFile -Raw -ErrorAction Stop
    $configGlobal = (Invoke-Expression $configFileContent -ErrorAction Stop)
    Write-Verbose -Message $configFileContent
    Write-Verbose -Message "Done reading configuration data..."
} catch {
    Write-Error $_.Exception.Message
    Write-Error $_.Exception.ItemName
    throw "Failed loading configuration file! Please see if you have any errors or if the file does not exist!"    
}

#
# Reading the credentials
#
Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Reading credentials as required..."
Write-Host "----------------------------------------------------------------------"
Write-Verbose -Message "Credentials for Domain Admin of the ADDC domain to be created..."
if($DomainAdminCreds -eq $null) {
    $DomainAdminCreds = Get-Credential -ErrorAction Stop
} 
$DomainAdminShortUserName = ($DomainAdminCreds.UserName)
$DomainAdminNetBiosUserName = ($domainNameshort + "\" + $DomainAdminCreds.UserName)
$DomainAdminFullyQualifiedUserName = ($DomainAdminCreds.UserName + "@" + $DomainName)

# Note: this will be used later in the script. Currently for simplicity it is using 
#       the domain admin account, but for production environments you should use a separate account.
$SqlServerServiceCreds = ($DomainAdminCreds)
$SqlServerServiceDomainUserName = ($domainNameshort + "\" + $SqlServerServiceCreds.UserName)

if($SetupAzureAccount) {
    Write-Verbose -Message "Credentials for Azure Subscription Management..."
    if($AzureManagementCredentials -eq $null) {
        $AzureManagementCredentials = Get-Credential -ErrorAction Stop
        Add-AzureAccount -Credential $AzureManagementCredentials -ErrorAction Stop
    }
} else {
    Write-Verbose -Message "-- Skipping Azure Account setup due to missing switch '-SetupAzureAccount'"
}

# Read the certificate from the store
Write-Verbose -Message "-- Reading certificate from the certificate store..."
$certForPwdEncryption = Get-SelfSignedCertificateByName -certName $certNameForPwdEncryption
if($certForPwdEncryption -eq $null) {
    throw "Unable to retrieve certificate for password encryption for Azure VM Extensions..."    
}

# Creating encrypted password versions for the VMExtension calls that need passwords as parameters.
# This is required for almost all SQL Server related setup steps.
Write-Verbose -Message "-- Creating Encrypted Passwords for usage in VM Extensions that require password parameters!"
$DomainAdminEncryptedPassword = Get-EncryptedPassword -certName $certNameForPwdEncryption -passwordToEncrypt ($DomainAdminCreds.GetNetworkCredential().Password)
$SqlServerAccountEncryptedPassword = Get-EncryptedPassword -certName $certNameForPwdEncryption -passwordToEncrypt ($SqlServerServiceCreds.GetNetworkCredential().Password)


#
# Select the Azure Subscription
#
Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Selecting Azure Subscription of active account..."
Write-Host "----------------------------------------------------------------------"
if( ($AzureSubscriptionName -eq $null) -or ($AzureSubscriptionName -eq "") ) {
    Write-Verbose -Message "No Subscription Parameter passed in, using default subscription from $ConfigFile"
    $AzureSubscriptionName = $configGlobal.GeneralConfig.DefaultSubscriptionName
}
Write-Verbose -Message "Subscription Name '$AzureSubscriptionName'"
$azureSubscription = Get-AzureSubscription -Name $AzureSubscriptionName -ErrorAction Stop
Select-AzureSubscription -Current -Name $AzureSubscriptionName -ErrorAction Stop
$currentSubscription = Get-AzureSubscription -Current -ErrorAction Stop


#
# Creating required storage accounts if they do not exist, yet
#
Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Creating storage accounts if needed..."
Write-Host "----------------------------------------------------------------------"
Write-Verbose -Message "Creating storage account $StorageAccountNamePrimaryRegion in $RegionPrimary..."
New-CloudStorageAccountIfNotExists -storageAccountName $StorageAccountNamePrimaryRegion -location $RegionPrimary -Verbose:($IsVerbosePresent)
Write-Verbose -Message "Creating storage account $StorageAccountNameSecondaryRegion in $RegionSecondary..."
New-CloudStorageAccountIfNotExists -storageAccountName $StorageAccountNameSecondaryRegion -location $RegionSecondary -Verbose:($IsVerbosePresent)

Write-Host "Done creating storage accounts, reading storage account keys and creating context for uploading data..."
Write-Verbose "Reading storage account keys for primary region account $StorageAccountNamePrimaryRegion..."
$storageAccountPrimaryRegionKey = Get-AzureStorageKey -StorageAccountName $StorageAccountNamePrimaryRegion
$storageAccountPrimaryContext = New-AzureStorageContext -StorageAccountName $StorageAccountNamePrimaryRegion -StorageAccountKey $storageAccountprimaryRegionKey.Primary
Write-Verbose "Reading storage account keys for secondary region account $StorageAccountNameSecondaryRegion.."
$storageAccountSecondaryRegionKey = Get-AzureStorageKey -StorageAccountName $StorageAccountNameSecondaryRegion
$storageAccountSecondaryContext = New-AzureStorageContext -StorageAccountName $StorageAccountNameSecondaryRegion -StorageAccountKey $storageAccountSecondaryRegionKey.Primary
Write-Host "Done creating storage account contexts for both regions."

Write-Verbose "Setting primary region storage account as default storage account on subscription..."
Set-AzureSubscription -SubscriptionName $currentSubscription.SubscriptionName `
                      -CurrentStorageAccountName $StorageAccountNamePrimaryRegion `
                      -ErrorAction Stop

#
# Setting up storage for SQL Server and other stuff
#
New-StorageContainerIfNotExists -storageContext $storageAccountPrimaryContext -containerName ($configGlobal.AvailabilityGroupConfig.AGSqlDatabaseBackupContainerName) -Verbose:($IsVerbosePresent)


#
# Upload the scripts for the VM Extensions as well as the scripts to be downloaded to the VMs to blob storage
#
Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Uploading PowerShell scripts to storage container for each region..."
Write-Host "----------------------------------------------------------------------"
if(-not $UploadSetupScripts) {
    Write-Host "-- skipping upload due to missing switch '-UploadSetupScripts'"
}
else {    
    Write-Verbose -Message "Creating ZIP-Archive with Setup Script files..."
    if([System.IO.Path]::IsPathRooted($configGlobal.GeneralConfig.SetupScriptsDirectory)) {
        $setupScriptsDirectoryToPackage = $configGlobal.GeneralConfig.SetupScriptsDirectory
    } else {
        $setupScriptsDirectoryToPackage = [System.IO.Path]::Combine((Get-Location), $configGlobal.GeneralConfig.SetupScriptsDirectory)
    }
    $setupScriptsZipArchiveFullName = [System.IO.Path]::Combine((Get-Location), $configGlobal.GeneralConfig.SetupScriptsZipArchiveName)
    Write-Verbose -Message "- Source path for ZIP archive: $setupScriptsDirectoryToPackage"
    Write-Verbose -Message "- ZIP Archive full path: $setupScriptsZipArchiveFullName"
    New-ZipArchive -parentDirectory $setupScriptsDirectoryToPackage -zipFileName $setupScriptsZipArchiveFullName

    Write-Verbose -Message "Getting list of setup scripts to transfer to storage..."
    $filesToUploadToStorage = @()
    $filesToUploadToStorage += $configGlobal.GeneralConfig.SetupScriptVmExtensionClusterNode
    $filesToUploadToStorage += $configGlobal.GeneralConfig.SetupScriptsZipArchiveName
    foreach($sf in (Get-ChildItem -Path $setupScriptsDirectoryToPackage)) {
        $filesToUploadToStorage += ($sf.FullName)
    }

    Write-Verbose -Message "Creating storage container ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) in primary region..."
    New-StorageContainerIfNotExists -storageContext $storageAccountPrimaryContext -containerName $configGlobal.GeneralConfig.SetupScriptsStorageContainerName -Verbose:($IsVerbosePresent)
    Write-Verbose -Message "Creating storage container ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) in secondary region..."
    New-StorageContainerIfNotExists -storageContext $storageAccountSecondaryContext -containerName $configGlobal.GeneralConfig.SetupScriptsStorageContainerName -Verbose:($IsVerbosePresent)

    Write-Verbose -Message "Uploading scripts for VM Extensions to primary region..."
    Send-FilesToStorageContainer -storageContext $storageAccountPrimaryContext `
                                 -containerName $configGlobal.GeneralConfig.SetupScriptsStorageContainerName `
                                 -filesList $filesToUploadToStorage  `
                                 -Verbose:($IsVerbosePresent)

    Write-Verbose -Message "Uploading scripts for VM Extensions to secondary region..."
    Send-FilesToStorageContainer -storageContext $storageAccountSecondaryContext `
                                 -containerName $configGlobal.GeneralConfig.SetupScriptsStorageContainerName `
                                 -filesList $filesToUploadToStorage `
                                 -Verbose:($IsVerbosePresent)

    Write-Host "Done uploading setup scripts to storage!"
}


#
# Getting the latest VM Image versions to be used
#

Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Getting latest VM Image versions for VMs from the gallery..."
Write-Host "----------------------------------------------------------------------"
Write-Verbose -Message "Getting the latest VMImage for Standard VMs..."

$ImageFamilyDefault = $configGlobal.GeneralConfig.VMImageFamilyDefault
$ImageFamilySql = $configGlobal.GeneralConfig.VMImageFamilySql

$ImageNameDefault = (Get-LatestAzureVMImage -ImageFamily $ImageFamilyDefault -Verbose:($IsVerbosePresent)).ImageName
if([String]::IsNullOrEmpty($ImageNameDefault)) {
    throw "Failed retrieving Image from image gallery. Please review your settings and messages above!"
}
if($SetupSQLVMs)
{
    Write-Verbose -Message "Getting the latest VMImage for SQL Server VMs..."
    $ImageNameSql = (Get-LatestAzureVMImage -ImageFamily $ImageFamilySql -Verbose:($IsVerbosePresent)).ImageName
    if([String]::IsNullOrEmpty($ImageNameSql)) {
        throw "Failed retrieving Image for SQL Server VMs from gallery. Please review your settings and messages above!"
    }
}
Write-Host "Done!"


#
# Create the Azure Services for the virtual machines in all locations
#
Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Creating cloud services in both regions if needed..."
Write-Host "----------------------------------------------------------------------"

$serviceNamePrimaryRegion = ($ServiceName + "-primary")
$serviceNameSecondaryRegion = ($ServiceName + "-secondary")
Write-Verbose -Message "Primary Region Service: $serviceNamePrimaryRegion"
Write-Verbose -Message "Secondary Region Service: $serviceNameSecondaryRegion"

New-CloudServiceIfNotExists -cloudServiceName $serviceNamePrimaryRegion -location $RegionPrimary -Verbose:($IsVerbosePresent)
New-CloudServiceIfNotExists -cloudServiceName $serviceNameSecondaryRegion -location $RegionSecondary -Verbose:($IsVerbosePresent)

Write-Host "Adding certificate to cloud service (for VM Extension Password Encryption)..."
Write-Verbose -Message "-- Adding certificate to $serviceNamePrimaryRegion..."
Add-CloudServiceCertificateIfNotExists -cloudServiceName $serviceNamePrimaryRegion `
                                       -certificateCreds $certDetailsForPwdEncryption `
                                       -certPfxFile $certPfxFileForPwdEncryption
Write-Verbose -Message "-- Adding certificate to $serviceNameSecondaryRegion..."
Add-CloudServiceCertificateIfNotExists -cloudServiceName $serviceNameSecondaryRegion `
                                       -certificateCreds $certDetailsForPwdEncryption `
                                       -certPfxFile $certPfxFileForPwdEncryption

Write-Host "Done!"


#
# Create the virtual network if needed
#

Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Creating Virtual Network configuration if requested... "
Write-Host "----------------------------------------------------------------------" 

$vnetNamePrimaryRegion = ("$ServiceName" + "-Primary")
$vnetNamePrimaryRegionLocal = ("$vnetNamePrimaryRegion" + "-Local")
$vnetNameSecondaryRegion = ("$ServiceName" + "-Secondary")
$vnetNameSecondaryRegionLocal = ("$vnetNameSecondaryRegion" + "-Local")

$vnetDNSNamePrimaryRegion = ("$vnetNamePrimaryRegion" + "-DNS")
$vnetDNSNameSecondaryRegion = ("$vnetNameSecondaryRegion" + "-DNS")
$vnetDNSNameFallback = ("$ServiceName" + "-DNSFallback")

$vnetDNSFallbackIP = $configGlobal.VNetConfig.FallbackDNS

$vnetPrimaryRegionAddressSpace = $configGlobal.VNetConfig.PrimaryRegionAddressSpace
$vnetSecondaryRegionAddressSpace = $configGlobal.VNetConfig.SecondaryRegionAddressSpace

$vnetDCSubnetAddressSpacePrimary = $configGlobal.VNetConfig.DomainControllerSubnetAddressSpacePrimary
$vnetDCSubnetAddressSpaceSecondary = $configGlobal.VNetConfig.DomainControllerSubnetAddressSpaceSecondary
$vnetSQLSubnetAddressSpacePrimary = $configGlobal.VNetConfig.SQLServerSubnetAddressSpacePrimary
$vnetSQLSubnetAddressSpaceSecondary = $configGlobal.VNetConfig.SQLServerSubnetAddressSpaceSecondary
$vnetDCSubnetName = $configGlobal.VNetConfig.DomainControllerSubnetName
$vnetSQLSubnetName = $configGlobal.VNetConfig.SQLServerSubnetName

$vnetPrimaryVPNGWAddress = $configGlobal.VNetConfig.PrimaryRegionVPNGWIP
$vnetSecondaryVPNGWAddress = $configGlobal.VNetConfig.SecondaryRegionVPNGWIP
$vnetGWSubnetAddressSpacePrimary = $configGlobal.VNetConfig.PrimaryRegionVPNGWSubnet
$vnetGWSubnetAddressSpaceSecondary = $configGlobal.VNetConfig.SecondaryRegionVPNGWSubnet

$vnetVPNKey = $configGlobal.VNetConfig.VNETVPNKey

if(-not $SetupNetwork) {
    Write-Host "-- skipping creation of Virtual Network since not requested by script-parameter!"
} 
else {
    Write-Host "Creating Local Network $RegionPrimary"
    New-AzureLocalNetwork -Name $vnetNamePrimaryRegionLocal `
       -VPNGatewayAddress $vnetPrimaryVPNGWAddress `
       -addAddressSpace $vnetPrimaryRegionAddressSpace

    Write-Host "Creating Local Network $RegionSecondary"
    New-AzureLocalNetwork -Name $vnetNameSecondaryRegion-Local `
      -VPNGatewayAddress $vnetSecondaryVPNGWAddress `
      -addAddressSpace $vnetSecondaryRegionAddressSpace

    # Add DNS records for the AD DCs
    Write-Verbose -Message "Primary Region DNS Configuration..."
    $dnsIP = ((Get-NodeByRole -config $configGlobal -role "PrimaryDC" -location 1).IP)
    Write-Verbose -Message ("- PrimaryDC DNS: $vnetDNSNAmePRimaryRegion-1" + " = " + "$dnsIP")
    $dnsConfig = @(
        @{ Name="$vnetDNSNamePrimaryRegion-1"; IPAddress=$dnsIP}
    )
    $otherdcs1 = @()
    $otherdcs1 += (Get-NodeByRole -config $configGlobal -role "SecondaryDC" -location 1)
    foreach ($dc in $otherdcs1)
    {
        Write-Verbose -Message ("- SecondayDC DNS: $vnetDNSNamePrimaryRegion-$idx" + " = " + $dc.IP)
        $idx = $otherdcs1.IndexOf($dc) + 2
        $dnsConfig += @{Name="$vnetDNSNamePrimaryRegion-$idx";IPAddress=$dc.IP}
    }
    # Add fall-back DNS for the first AD
    Write-Verbose -Message "- Fallback DNS: $vnetDNSNameFallback = $vnetDNSFallbackIP"
    $dnsConfig += @{Name="$vnetDNSNameFallback";IPAddress="$vnetDNSFallbackIP"} 

    # Start creating the virtual networks
    Write-Host "Creating VNET $vnetNamePrimaryRegion in $RegionPrimary"
    New-AzureVirtualNetwork -Location "$RegionPrimary" -VNetName "$vnetNamePrimaryRegion" `
      -AddressSpaces "$vnetPrimaryRegionAddressSpace" `
      -Subnets @{Name="$vnetDCSubnetName";Prefix="$vnetDCSubnetAddressSpacePrimary"},@{Name="$vnetSQLSubnetName";Prefix="$vnetSQLSubnetAddressSpacePrimary"} `
      -newDNSServerConfig $dnsConfig `
      -addLocalNetwork $vnetNameSecondaryRegionLocal `
      -EnableS2S `
      -GatewaySubnet $vnetGWSubnetAddressSpacePrimary

    # Add DNS records for the AD DCs to be added to the secondary location
    Write-Verbose -Message "Secondary Region DNS Configuration: "
    Write-Verbose -Message "- Adding Primary DC DNS: $vnetDNSNamePrimaryRegion-1"
    $primaryRegionDnsConfigs = @("$vnetDNSNamePrimaryRegion-1")
    foreach ($dc in $otherdcs1)
    {
        $idx = $otherdcs1.IndexOf($dc) + 2
        Write-Verbose -Message "- Adding Secondary DC DNS: $vnetDNSNamePrimaryRegion-$idx"
        $primaryRegionDnsConfigs += "$vnetDNSNamePrimaryRegion-$idx"
    }
    # Add fall-back DNS for the first AD
    Write-Verbose -Message "- Adding Fallback DNS: $vnetDNSNameFallback"
    $primaryRegionDnsConfigs += "$vnetDNSNameFallback"
    # Add the AD DCs in the secondary location also as DNS servers
    $dnsConfig = @()
    $otherdcs2 = @()
    $otherdcs2 += (Get-NodeByRole -config $configGlobal -role "SecondaryDC" -location 2)
    foreach ($dc in $otherdcs2)
    {
        $idx = $otherdcs2.IndexOf($dc) + 1
        Write-Verbose -Message ("- Adding secondary region DC DNS: $vnetDNSNameSecondaryRegion-$idx = "+ $dc.IP)
        $dnsConfig += @{Name="$vnetDNSNameSecondaryRegion-$idx";IPAddress=$dc.IP}
    }

    Write-Host "Creating VNET $vnetNameSecondaryRegion in $RegionSecondary"
    New-AzureVirtualNetwork -Location "$RegionSecondary" -VNetName "$vnetNameSecondaryRegion" `
      -AddressSpaces "$vnetSecondaryRegionAddressSpace" `
      -Subnets @{Name="$vnetDCSubnetName";Prefix="$vnetDCSubnetAddressSpaceSecondary"},@{Name="$vnetSQLSubnetName";Prefix="$vnetSQLSubnetAddressSpaceSecondary"} `
      -newDNSServerConfig $dnsConfig `
      -addDNSServer $primaryRegionDnsConfigs `
      -addLocalNetwork $vnetNamePrimaryRegionLocal `
      -EnableS2S `
      -GatewaySubnet $vnetGWSubnetAddressSpaceSecondary

    Write-Host "Starting VNET Gateway creation..."
    Write-Verbose -Message "  VNET Gateway $vnetNamePrimaryRegion"
    $gw1Job = Start-Job -ScriptBlock { `
                    New-AzureVNetGateway -GatewayType DynamicRouting `
                            -VNetName $Using:vnetNamePrimaryRegion -GatewaySKU HighPerformance }

    Write-Verbose -Message "  VNET Gateway $vnetNameSecondaryRegion"
    $gw2Job = Start-Job -ScriptBlock { `
                    New-AzureVNetGateway -GatewayType DynamicRouting `
                            -VNetName $Using:vnetNameSecondaryRegion -GatewaySKU HighPerformance }

    Write-Host "Waiting for both VNET Gateways to be ready. This can take up to 30 mins..."
    
    do
    {
        $gw1 = Get-AzureVNetGateway -VNetName $vnetNamePrimaryRegion
        $gw2 = Get-AzureVNetGateway -VNetName $vnetNameSecondaryRegion
        
        Write-Verbose -Message ("GW1 State: " + $gw1.State + " / GW1 Job Status: " + $gw1Job.State)
        Write-Verbose -Message ("GW2 State: " + $gw2.State + " / GW2 Job Status: " + $gw2Job.State)

        if($gw1Job.State -eq "Failed") {
            Write-Error -Message "Gateway 1 Creation Job Failed!"
            $gw1JobResults = Receive-Job -Job $gw1Job
            Write-Error -Message "Job Output: $gw1JobResults"
            throw "Gateway job creation failed, please review error messages above!"
        }
        if($gw2Job.State -eq "Failed") {
            Write-Error -Message "Gateway 2 Creation Job Failed!"
            $gw2JobResults = Receive-Job -Job $gw2Job
            Write-Error -Message "Job Output: $gw2JobResults"
            throw "Gateway job creation failed, please review error messages above!"
        }

        Start-Sleep ($configGlobal.GeneralConfig.RetryIntervalSec)
    }while(($gw1.State -eq "NotProvisioned") -or ($gw2.State -eq "NotProvisioned") -or ($gw1.State -eq "Provisioning") -or ($gw2.State -eq "Provisioning"))
    
    Write-Host "Setting VNET Gateway keys"
    Set-AzureVNetGatewayKey -VNetName $vnetNamePrimaryRegion `
        -LocalNetworkSiteName $vnetNameSecondaryRegionLocal -SharedKey $vnetVPNKey

    Set-AzureVNetGatewayKey -VNetName $vnetNameSecondaryRegion `
        -LocalNetworkSiteName $vnetNamePrimaryRegionLocal -SharedKey $vnetVPNKey

    Write-Host "Setting VNET Gateway IP Addresses"
    Set-AzureLocalNetwork -Name $vnetNameSecondaryRegionLocal -VPNGatewayAddress $gw2.VIPAddress
    Set-AzureLocalNetwork -Name $vnetNamePrimaryRegionLocal -VPNGatewayAddress $gw1.VIPAddress

    Write-Host "Done!"
}


#
# Creating the Primary Active Directory Domain Controller and provision the AD Forest
#
Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Provisioning Primary Domain Controller and AD Forest if requested"
Write-Host "----------------------------------------------------------------------"

Write-Verbose -Message "Reading AD Primary DC Node configuration..."
$addcVmPrimaryConfig = Get-NodeByRole -config $configGlobal -role "PrimaryDC" -location 1
Write-VerboseNodeConfiguration -node $addcVmPrimaryConfig -Verbose:($IsVerbosePresent)

Write-Verbose -Message "Checking if Primary Domain Controller VM does exist, already..."
$addcVmPrimary = Get-AzureVM -ServiceName $serviceNamePrimaryRegion -Name ($addcVmPrimaryConfig.NodeName) -ErrorAction SilentlyContinue
$addcPrimaryAzureVMExists = ($addcVmPrimary -ne $null)
if($addcPrimaryAzureVMExists) {
    Write-Host "Skipping Primary AD DC VM Creation since the Virtual Machine does exist, already!"
} else {
    if(-not $SetupADDCForest) {
        throw "Primary AD Domain Controller does not exist, yet. AD Forest and PrimaryDC needs to exist before next steps can be taken. Please specify switch '-SetupADDCForest' to fix this issue!"
    } else {
        Write-Host "Creating Azure VM for the ADDC Primary Controller and setting up ADDC forest!"
    }
}

# Create the Primary ADDC forest VM if requested and if it does not exist, yet
if($SetupADDCForest -and (-not $addcPrimaryAzureVMExists)) 
{
    Write-Verbose -Message "Creating Azure VM for ADDC Forest Setup..."
    try {
        $addcAvailabilitySet = $configGlobal.GeneralConfig.DefaultAdDcAvailabilitySetName
        $scriptsBaseDirectory = ($configGlobal.GeneralConfig.SetupScriptsVmTargetDirectory)
        
        Write-Verbose -Message "Creating primary ADDC VM configuration"
        Write-Verbose -Message "- Availability Set: $addcAvailabilitySet"
        Write-Verbose -Message ("- Node Name: " + ($addcVmPrimaryConfig.NodeName))
        $addcVmPrimary = New-PrimaryADVMConfig -adVms $addcVmPrimaryConfig `
                                               -vmSize $VmSizeAdDc `
                                               -imageName $ImageNameDefault `
                                               -availabilitySetName $addcAvailabilitySet `
                                               -adminUser ($DomainAdminCreds.UserName) `
                                               -adminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                               -storageAccountName $StorageAccountNamePrimaryRegion `
                                               -vhdContainerName ($configGlobal.GeneralConfig.VMVHDADContainerName) `
                                               -certToDeploy $certForPwdEncryption `
                                               -custInstContainerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                               -custInstFileName ($configGlobal.GeneralConfig.SetupADForest) `
                                               -customVmExtArguments (" -domainName $DomainName" + `
                                                                      " -domainNameShort $DomainNameShort" + `
                                                                      " -domainAdminPwdEnc `"$DomainAdminEncryptedPassword`"" + `
                                                                      " -certNamePwdEnc $certNameForPwdEncryption") `
                                               -Verbose:($IsVerbosePresent)

        Write-Host "Provisioning Primary Domain Controller..."
        New-AzureVM -ServiceName $serviceNamePrimaryRegion -VMs $addcVmPrimary `
                    -VNetName $vnetNamePrimaryRegion -Location "$RegionPrimary" `
                    -Verbose:($IsVerbosePresent) `
                    -WaitForBoot `
                    -ErrorAction Stop
        Write-Verbose -Message ("Done setting up VM " + ($addcVmPrimaryConfig.NodeName) + "in service $serviceNamePrimaryRegion!")

        Write-Host "Waiting for the VM custom script extension to complete provisioning the ADDC Forest..."
        Wait-AzureVmForCustomScriptExtension -vmTargetName  ($addcVmPrimary.RoleName) `
                                             -vmTargetService $serviceNamePrimaryRegion `
                                             -vmPreviousScriptTimestamp "" `
                                             -WaitMaxAttempts ($configGlobal.GeneralConfig.RetryCount) `
                                             -WaitIntervalInSec ($configGlobal.GeneralConfig.RetryIntervalSec) `
                                             -Verbose:($IsVerbosePresent)

        Write-Host "Restarting the Primary Domain Controller..."
        Restart-AzureVM -ServiceName $serviceNamePrimaryRegion -Name ($addcVmPrimary.RoleName)

        Write-Host "Done with Primary ADDC Setup!!"
    } catch {
        Write-Error $_.Exception.Message
        Write-Error $_.Exception.ItemName
        throw "Failed Creating Azure VM for Primary ADDC Controller. Please review earlier error messages for details!"
    }
}

# At this time the ADDC Primary VM must be available
Write-Verbose -Message "Getting Primary DC Azure Virtual Machine for further processing and validation..."
$addcVmPrimary = Get-AzureVM -ServiceName $serviceNamePrimaryRegion -Name $addcVmPrimaryConfig.NodeName -ErrorAction Stop


#
# Creating the secondary Domain Controllers after the first one has been provisioned successfully
#
Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Provisioning additional ADDC servers to the forest if requested..."
Write-Host "----------------------------------------------------------------------"
if(-not $SetupSecondaryADDCs) {
    Write-Host "-- Skipping Setup of additional AD DCs due to missing switch '-SetupSecondaryADDCs'..."
} else {
    try {
        Write-Host "-- Provisioning additional domain controllers into the service..."
            
        Write-Verbose -Message "Getting availability set name for ADDCs..."
        $addcAvailabilitySet = $configGlobal.GeneralConfig.DefaultAdDcAvailabilitySetName
        $scriptsBaseDirectory = ($configGlobal.GeneralConfig.SetupScriptsVmTargetDirectory)
        Write-Verbose -Message "- Availabilty Set: $addcAvailabilitySet"

        Write-Verbose -Message "Creating secondary ADDC VM configurations for Primary Region..."        
        $addcVmSecondaryConfigPrimaryRegion = @()
        $addcVmSecondaryConfigPrimaryRegion += Get-NodeByRole -config $configGlobal -role "SecondaryDC" -location 1
        foreach($n in $addcVmSecondaryConfigPrimaryRegion) {
            Write-VerboseNodeConfiguration -node $n -Verbose:$IsVerbosePresent
        }
        $addcVmExtArguments = ( " -domainName $DomainName" `
                              + " -domainAdminName $DomainAdminFullyQualifiedUserName" `
                              + " -domainAdminPwdEnc `"" + $DomainAdminEncryptedPassword + "`"" `
                              + " -certNamePwdEnc $certNameForPwdEncryption" `
                              + " -findDomainRetryCount " + ($configGlobal.GeneralConfig.RetryCount) `
                              + " -findDomainRetryIntervalSecs " + ($configGlobal.GeneralConfig.RetryIntervalSec))
        $addcVmSecondary = New-AdditionalADVMsConfig -adVms $addcVmSecondaryConfigPrimaryRegion `
                                                     -vmSize $VmSizeAdDc `
                                                     -imageName $ImageNameDefault `
                                                     -availabilitySetName $addcAvailabilitySet `
                                                     -adminUser ($DomainAdminCreds.UserName) `
                                                     -adminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                                     -domain $DomainName `
                                                     -shortDomain $DomainNameShort `
                                                     -domainAdminName ($DomainAdminCreds.UserName) `
                                                     -domainAdminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                                     -storageAccountName $StorageAccountNamePrimaryRegion `
                                                     -vhdContainerName ($configGlobal.GeneralConfig.VMVHDADContainerName) `
                                                     -certToDeploy $certForPwdEncryption `
                                                     -custInstContainerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                                     -custInstFileName ($configGlobal.GeneralConfig.SetupADSecondaryDC) `
                                                     -customVmExtArguments $addcVmExtArguments `
                                                     -Verbose:($IsVerbosePresent)

        Write-Verbose -Message "Creating secondary ADDC VM configurations for Secondary Region..."
        $addcVmSecondaryConfigSecondaryRegion = @()
        $addcVmSecondaryConfigSecondaryRegion += Get-NodeByRole -config $configGlobal -role "SecondaryDC" -location 2
        foreach($n in $addcVmSecondaryConfigSecondaryRegion) {
            Write-VerboseNodeConfiguration -node $n -Verbose:$IsVerbosePresent
        }
        $addcVmExtArguments = ( " -domainName $DomainName" `
                              + " -domainAdminName $DomainAdminFullyQualifiedUserName" `
                              + " -domainAdminPwdEnc `"" + $DomainAdminEncryptedPassword + "`"" `
                              + " -certNamePwdEnc $certNameForPwdEncryption" `
                              + " -findDomainRetryCount " +  ($configGlobal.GeneralConfig.RetryCount) `
                              + " -findDomainRetryIntervalSecs " + ($configGlobal.GeneralConfig.RetryIntervalSec))
        $addcVmSecondarySecondaryRegion = New-AdditionalADVMsConfig -adVms $addcVmSecondaryConfigSecondaryRegion `
                                                                    -vmSize $VmSizeAdDc `
                                                                    -imageName $ImageNameDefault `
                                                                    -availabilitySetName $addcAvailabilitySet `
                                                                    -adminUser ($DomainAdminCreds.UserName) `
                                                                    -adminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                                                    -domain $DomainName `
                                                                    -shortDomain $DomainNameShort `
                                                                    -domainAdminName ($DomainAdminCreds.UserName) `
                                                                    -domainAdminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                                                    -storageAccountName $StorageAccountNameSecondaryRegion `
                                                                    -vhdContainerName ($configGlobal.GeneralConfig.VMVHDADContainerName) `
                                                                    -certToDeploy $certForPwdEncryption `
                                                                    -custInstContainerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                                                    -custInstFileName ($configGlobal.GeneralConfig.SetupADSecondaryDC) `
                                                                    -customVmExtArguments $addcVmExtArguments `
                                                                    -Verbose:($IsVerbosePresent)


        Write-Host "Creating ADDC Virtual Machines in Primary Region..."
        Write-Verbose -Message "Determining which VMs have been created, already..."
        $addcVmPrimaryRegionEffectiveToCreate = @()
        $addcVmSecondaryRegionEffectiveToCreate = @()
        foreach($vmCfg in $addcVmSecondary) {
            $vm = Get-AzureVM -ServiceName $serviceNamePrimaryRegion -Name ($vmCfg.RoleName)
            if($vm -eq $null) {
                $addcVmPrimaryRegionEffectiveToCreate += $vmCfg
            } else {
                Write-Verbose -Message ("- Skipping creation of '" + ($vmCfg.RoleName) + "' as it exists!")
            }
        }
        foreach($vmCfg in $addcVmSecondarySecondaryRegion) {
            $vm = Get-AzureVM -ServiceName $serviceNameSecondaryRegion -Name ($vmCfg.RoleName)
            if($vm -eq $null) {
                $addcVmSecondaryRegionEffectiveToCreate += $vmCfg
            } else {
                Write-Verbose -Message ("- Skipping creation of '" + ($vmCfg.RoleName) + "' as it exists!")
            }
        }

        Write-Host "Creating ADDC Secondary Controller Virtual Machines in Primary Region..."
        if($addcVmPrimaryRegionEffectiveToCreate.Count -gt 0) {
            New-AzureVM -ServiceName $serviceNamePrimaryRegion `
                        -VMs $addcVmPrimaryRegionEffectiveToCreate `
                        -VNetName $vnetNamePrimaryRegion `
                        -Location "$RegionPrimary" `
                        -Verbose:($IsVerbosePresent) `
                        -WaitForBoot
            foreach($vm in $addcVmPrimaryRegionEffectiveToCreate) {
                $addcVmToWaitFor = ($vm.RoleName)
                Write-Host "-- Waiting for VM custom script extension of $addcVmToWaitFor to complete!"
                Wait-AzureVmForCustomScriptExtension -vmTargetName  (($vm).RoleName) `
                             -vmTargetService $serviceNamePrimaryRegion `
                             -vmPreviousScriptTimestamp "" `
                             -WaitMaxAttempts (($configGlobal).GeneralConfig.RetryCount) `
                             -WaitIntervalInSec (($configGlobal).GeneralConfig.RetryIntervalSec) `
                             -Verbose:($IsVerbosePresent) 
                Write-Host "Restarting Domain Controller " + $vm.RoleName + "..."
                Restart-AzureVM -ServiceName $serviceNamePrimaryRegion -Name ($vm.RoleName)
            }
        } else {
            Write-Host "-- All VMs exist, already - nothing to create!"
        }

        Write-Host "Creating ADDC Secondary Controller Virtual Machines in Secondary Region..."
        if($addcVmSecondaryRegionEffectiveToCreate.Count -gt 0) {
            New-AzureVM -ServiceName $serviceNameSecondaryRegion `
                -VMs $addcVmSecondaryRegionEffectiveToCreate `
                -VNetName $vnetNameSecondaryRegion `
                -Location "$RegionSecondary" `
                -Verbose:($IsVerbosePresent) `
                -WaitForBoot
            foreach($vm in $addcVmSecondaryRegionEffectiveToCreate) {
                $addcVmToWaitFor = ($vm.RoleName)
                Write-Host "-- Waiting for VM custom script extension of $addcVmToWaitFor to complete!"
                Wait-AzureVmForCustomScriptExtension -vmTargetName  (($vm).RoleName) `
                            -vmTargetService $serviceNameSecondaryRegion `
                            -vmPreviousScriptTimestamp "" `
                            -WaitMaxAttempts (($configGlobal).GeneralConfig.RetryCount) `
                            -WaitIntervalInSec (($configGlobal).GeneralConfig.RetryIntervalSec) `
                            -Verbose:($IsVerbosePresent) 
                Write-Host "Restarting Domain Controller " + $vm.RoleName + "..."
                Restart-AzureVM -ServiceName $serviceNameSecondaryRegion -Name ($vm.RoleName)
            }
        } else {
            Write-Host "-- All VMs exist, already - nothing to create!"
        }
    } catch {
        Write-Error $_.Exception.Message
        Write-Error $_.Exception.ItemName
        throw "Failed setting up additional domain controllers to network. Please review earlier error messages for details!"
    }
}


Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Provisioning SQL Server AlwaysOn Availability Group VMs..."
Write-Host "----------------------------------------------------------------------"
if(-not $SetupSQLVMs) {
    Write-Host "-- Skipping creation of SQL Server Virtual Machines due to missing switch '-SetupSQLVMs'!"
} else {
    try {
        Write-Host "Reading configuration for SQL Server VMs of both locations..."
        Write-Verbose -Message "Reading configuration for SQL Server VMs in primary location..."
        $sqlVmConfigsPrimaryRegion = @()
        $sqlVmConfigsPrimaryRegion += (Get-NodeByRole -config $configGlobal -role "PrimarySqlNode" -location 1)
        $sqlVmConfigsPrimaryRegion += (Get-NodeByRole -config $configGlobal -role "SecondarySqlNode" -location 1)
        Write-Verbose -Message "Reading configuration for SQL Server Witness VMs in primary location..."
        $sqlVmConfigsPrimaryRegionWitness = @()
        $sqlVmConfigsPrimaryRegionWitness += (Get-NodeByRole -config $configGlobal -role "SqlWitness" -location 1)
        Write-Verbose -Message "Reading configuration for SQL Server VMs in secondary location..."
        $sqlVmConfigsSecondaryRegion = @()
        $sqlVmConfigsSecondaryRegion += (Get-NodeByRole -config $configGlobal -role "SecondarySqlNode" -location 2)

        Write-Host "Generating SAS URL for ZIP with setup scripts..."
        Write-Host "Creating a Shared Access Signature Link for the ZIP-File with the setup scripts for the SQL Server VMs..."
        $zipFileDownloadLinkPrimaryRegion = Get-SharedAccessBlobUrl -storageContext $storageAccountPrimaryContext `
                                                                    -containerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                                                    -fileName ($configGlobal.GeneralConfig.SetupScriptsZipArchiveName) `
																	-expiresInMinutes (60*10)
        $zipFileDownloadLinkSecondaryRegion = Get-SharedAccessBlobUrl -storageContext $storageAccountSecondaryContext `
                                                                      -containerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                                                      -fileName ($configGlobal.GeneralConfig.SetupScriptsZipArchiveName) `
																	  -expiresInMinutes (60*10)
        Write-Verbose -Message "- $zipFileDownloadLinkPrimaryRegion"
        Write-Verbose -Message "- $zipFileDownloadLinkSecondaryRegion"

        Write-Host "Creating Azure VM Configurations for Provisioning..."
        Write-Verbose -Message "Creating Azure VM Configurations for the creation of SQL Nodes in Primary Region..."
        $sqlVmPrimaryRegionVmDefinitions = New-SQLVMsConfig -sqlVms $sqlVmConfigsPrimaryRegion `
                                                            -vmSize ($VmSizeSql) `
                                                            -imageName $ImageNameSql `
                                                            -availabilitySetName ($configGlobal.GeneralConfig.DefaultSQLAvailablitySetName) `
                                                            -adminUser ($DomainAdminCreds.UserName) `
                                                            -adminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                                            -domain $DomainName `
                                                            -shortDomain $DomainNameShort `
                                                            -domainAdminName ($DomainAdminCreds.UserName) `
                                                            -domainAdminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                                            -certToDeploy $certForPwdEncryption `
                                                            -custInstContainerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                                            -custInstFileName ($configGlobal.GeneralConfig.SetupScriptVmExtensionClusterNode) `
                                                            -custInstClusterFeature $true `
                                                            -custInstDownloadFiles $true `
                                                            -custInstZipFileLink $zipFileDownloadLinkPrimaryRegion `
                                                            -custInstLocalScriptsDir ($configGlobal.GeneralConfig.SetupScriptsVmTargetDirectory) `
                                                            -storageAccountName $StorageAccountNamePrimaryRegion `
                                                            -vhdContainerName ($configGlobal.GeneralConfig.VMVHDSQLContainerName) `
                                                            -Verbose:($IsVerbosePresent)

        Write-Verbose -Message "Creating Azure VM Configurations for the creation of the SqlWitness nodes in Primary Region..."
        $sqlVmPrimaryRegionWitnessVmDefinitions = New-SQLVMsConfig -sqlVms $sqlVmConfigsPrimaryRegionWitness `
                                                                   -vmSize ($VmSizeSql) `
                                                                   -imageName $ImageNameSql `
                                                                   -availabilitySetName ($configGlobal.GeneralConfig.DefaultSQLAvailablitySetName) `
                                                                   -adminUser ($DomainAdminCreds.UserName) `
                                                                   -adminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                                                   -domain $DomainName `
                                                                   -shortDomain $DomainNameShort `
                                                                   -domainAdminName ($DomainAdminCreds.UserName) `
                                                                   -domainAdminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                                                   -certToDeploy $certForPwdEncryption `
                                                                   -custInstContainerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                                                   -custInstFileName ($configGlobal.GeneralConfig.SetupScriptVmExtensionClusterNode) `
                                                                   -custInstClusterFeature $false `
                                                                   -custInstDownloadFiles $true `
                                                                   -custInstZipFileLink $zipFileDownloadLinkPrimaryRegion `
                                                                   -custInstLocalScriptsDir ($configGlobal.GeneralConfig.SetupScriptsVmTargetDirectory) `
                                                                   -storageAccountName $StorageAccountNamePrimaryRegion `
                                                                   -vhdContainerName ($configGlobal.GeneralConfig.VMVHDSQLContainerName) `
                                                                   -Verbose:($IsVerbosePresent)

        Write-Verbose -Message "Creating Azure VM Configurations for the creation of SQL Nodes in Secondary Region..."
        $sqlVmSecondaryRegionVmDefinitions = New-SQLVMsConfig -sqlVms $sqlVmConfigsSecondaryRegion `
                                                              -vmSize ($VmSizeSql) `
                                                              -imageName $ImageNameSql `
                                                              -availabilitySetName ($configGlobal.GeneralConfig.DefaultSQLAvailablitySetName) `
                                                              -adminUser ($DomainAdminCreds.UserName) `
                                                              -adminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                                              -domain $DomainName `
                                                              -shortDomain $DomainNameShort `
                                                              -domainAdminName ($DomainAdminCreds.UserName) `
                                                              -domainAdminPwd ($DomainAdminCreds.GetNetworkCredential().Password) `
                                                              -certToDeploy $certForPwdEncryption `
                                                              -custInstContainerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                                              -custInstFileName ($configGlobal.GeneralConfig.SetupScriptVmExtensionClusterNode) `
                                                              -custInstClusterFeature $true `
                                                              -custInstDownloadFiles $true `
                                                              -custInstZipFileLink $zipFileDownloadLinkSecondaryRegion `
                                                              -custInstLocalScriptsDir ($configGlobal.GeneralConfig.SetupScriptsVmTargetDirectory) `
                                                              -storageAccountName $StorageAccountNameSecondaryRegion `
                                                              -vhdContainerName ($configGlobal.GeneralConfig.VMVHDSQLContainerName) `
                                                              -Verbose:($IsVerbosePresent)                                                             

        Write-Verbose -Message "Detecting which Azure SQL VMs have been created, already..."
        $sqlVmPrimaryRegionEffectiveToCreate = @()
        $sqlVmPrimaryRegionEffectiveToCreate += (Get-VmDefsNonExistingAzureVms -vmDefsArray $sqlVmPrimaryRegionVmDefinitions -serviceName $serviceNamePrimaryRegion -Verbose:($IsVerbosePresent))
        $sqlVmPrimaryRegionWitnessEffectiveToCreate = @()
        $sqlVmPrimaryRegionWitnessEffectiveToCreate += (Get-VmDefsNonExistingAzureVms -vmDefsArray $sqlVmPrimaryRegionWitnessVmDefinitions -serviceName $serviceNamePrimaryRegion -Verbose:($IsVerbosePresent))
        $sqlVmSecondaryRegionEffectiveToCreate = @()
        $sqlVmSecondaryRegionEffectiveToCreate += (Get-VmDefsNonExistingAzureVms -vmDefsArray $sqlVmSecondaryRegionVmDefinitions -serviceName $serviceNameSecondaryRegion -Verbose:($IsVerbosePresent))

        Write-Host "Creating SQL Server VMs that do not exist, yet..."
        if($sqlVmPrimaryRegionEffectiveToCreate.Count -gt 0) {
            New-AzureVM -ServiceName $serviceNamePrimaryRegion `
                        -VMs $sqlVmPrimaryRegionEffectiveToCreate `
                        -VNetName $vnetNamePrimaryRegion `
                        -Location $RegionPrimary `
                        -WaitForBoot `
                        -Verbose:($IsVerbosePresent)
        } else {
            Write-Host "-- No SQL VMs to create in primary region!"
        }

        if($sqlVmSecondaryRegionEffectiveToCreate.Count -gt 0) {
            New-AzureVM -ServiceName $serviceNameSecondaryRegion `
                        -VMs $sqlVmSecondaryRegionEffectiveToCreate `
                        -VNetName $vnetNameSecondaryRegion `
                        -Location $RegionSecondary `
                        -WaitForBoot `
                        -Verbose:($IsVerbosePresent)
        } else {
            Write-Host "-- No SQL VMs to create in secondary region!"
        }

        if($sqlVmPrimaryRegionWitnessEffectiveToCreate.Count -gt 0) {
            New-AzureVM -ServiceName $serviceNamePrimaryRegion `
                        -VMs $sqlVmPrimaryRegionWitnessEffectiveToCreate `
                        -VNetName $vnetNamePrimaryRegion `
                        -Location $RegionPrimary `
                        -WaitForBoot `
                        -Verbose:($IsVerbosePresent)
        } else {
            Write-Host "-- No SQL Witness VMs to create in primary region!"
        }

        Write-Host "Waiting for VMs and VM Extensions to complete!"
        Wait-AzureVmsReady -vmServiceNamesToMonitor @($serviceNamePrimaryRegion, $serviceNameSecondaryRegion) `
                           -sleepInSecondsInterval ($configGlobal.GeneralConfig.RetryIntervalSec) `
                           -Verbose:($IsVerbosePresent)

        Write-Host "Setting up internal Load Balancer for SQL AlwaysOn Availability Group Listener..."
        $ILBIPPrimaryRegion = ($configGlobal.AvailabilityGroupConfig.AGListenerPrimaryRegionIP)
        $ILBNamePrimaryRegion = ($configGlobal.AvailabilityGroupConfig.AGName) + "sql-ilb-primary"
        $ILBIPSecondaryRegion = ($configGlobal.AvailabilityGroupConfig.AGListenerSecondaryRegionIP)
        $ILBNameSecondaryRegion = ($configGlobal.AvailabilityGroupConfig.AGName) + "sql-ilb-secondary"
        $sqlNetEndpointName = ($configGlobal.AvailabilityGroupConfig.AGSqlEndpointName)
        $sqlNetEndpointPort = ($configGlobal.AvailabilityGroupConfig.AGSqlPort)
        $sqlNetProbePort = ($configGlobal.AvailabilityGroupConfig.AGProbePort)
        Write-Verbose -Message "Additional Endpoint Parameters for Internal Load Balancer with EndPoint=$sqlNetEndpointName, Port=$sqlNetEndpointPort, ProbePort=$sqlNetProbePort"        

        $existingILB = Get-AzureInternalLoadBalancer -ServiceName $serviceNamePrimaryRegion
        if($existingILB -eq $null) {
            Write-Verbose "Creating Internal Load Balancer ($ILBNamePrimaryRegion, $ILBIPPrimaryRegion) for SQL in location $RegionPrimary"
            Add-AzureInternalLoadBalancer -InternalLoadBalancerName $ILBNamePrimaryRegion -SubnetName $vnetSQLSubnetName -ServiceName $serviceNamePrimaryRegion -StaticVNetIPAddress $ILBIPPrimaryRegion
            $sqlVmsConfigPrimary = @((Get-NodeByRole -role "PrimarySqlNode" -location 1)) + (Get-NodeByRole -role "SecondarySqlNode" -location 1)
            Set-SQLVMsILB -svcloc $serviceNamePrimaryRegion -epName $sqlNetEndpointName -epPort $sqlNetEndpointPort -prPort $sqlNetProbePort -ilbName $ILBNamePrimaryRegion -vms $sqlVmsConfigPrimary -Verbose:($IsVerbosePresent)
        } else {
            Write-Verbose -Message "Internal Load Balancer for $serviceNamePrimaryRegion does exist, already!"
        }       

        $existingILB = Get-AzureInternalLoadBalancer -ServiceName $serviceNameSecondaryRegion
        if($existingILB -eq $null) {
            Write-Verbose "Creating Internal Load Balancer ($ilbIP2) for SQL in location $svcloc1"
            Add-AzureInternalLoadBalancer -InternalLoadBalancerName $ILBNameSecondaryRegion -SubnetName $vnetSQLSubnetName -ServiceName $serviceNameSecondaryRegion -StaticVNetIPAddress $ILBIPSecondaryRegion
            $sqlVmsConfigSecondary = @((Get-NodeByRole -role "SecondarySqlNode" -location 2))
            Set-SQLVMsILB -svcloc $serviceNameSecondaryRegion -epName $sqlNetEndpointName -epPort $sqlNetEndpointPort -prPort $sqlNetProbePort -ilbName $ILBNameSecondaryRegion -vms $sqlVmsConfigSecondary -Verbose:($IsVerbosePresent)            
        } else {
            Write-Verbose -Message "Internal Load Balancer for $serviceNameSecondaryRegion does exist, already!"
        }
    } catch {
        Write-Error $_.Exception.Message
        Write-Error $_.Exception.ItemName
        throw "Failed setting up SQL Server Virtual Machines. Please review earlier error messages for details!"        
    }
}


Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "SQL Server AlwaysOn Availability Group Setup with VM Extensions..."
Write-Host "----------------------------------------------------------------------"
if(-not $SetupSQLAG) {
    Write-Host "Skipping SQL Server AlwaysOn Availability Group Setup due to missing switch '-SetupSQLAG'!"
} else {
    try {        
        Write-Host "Running basic setup on all SQL Server Nodes using VM Extensions..."
        Write-Host "- Basic setup (firewall rules etc.)"
        Write-Host "- Cluster setup"
        Write-Host "- Enable AlwaysOn and Configure SQL Service Accounts"
        $allWaitJobs = @()
        $allSqlVmsCfg = @()
        $allSqlVmsCfg += (Get-NodeByRole -config $configGlobal -role "PrimarySqlNode")
        $allSqlVmsCfg += (Get-NodeByRole -config $configGlobal -role "SecondarySqlNode")
        foreach($sqlVmCfg in $allSqlVmsCfg) {
            # Run the SQL Basic Setup on all nodes (configures access rights to SQL Server for domain accounts etc.)
            if($sqlVmCfg.Location -eq 1) {
                $vmExtStorageAccountName = $StorageAccountNamePrimaryRegion
                $vmExtStorageAccountKey = $storageAccountPrimaryRegionKey.Primary
                $vmExtTargetServiceName = $serviceNamePrimaryRegion
            } else {
                $vmExtStorageAccountName = $StorageAccountNameSecondaryRegion
                $vmExtStorageAccountKey = $storageAccountSecondaryRegionKey.Primary
                $vmExtTargetServiceName = $serviceNameSecondaryRegion
            }
            $vmExtScriptArguments = `
                        "-scriptsBaseDirectory " + ($configGlobal.GeneralConfig.SetupScriptsVmTargetDirectory) + " " + `
                        "-certNamePwdEnc $certNameForPwdEncryption " + `
                        "-domainNameShort $DomainNameShort " + `
                        "-domainNameLong $DomainName " + `
                        "-localAdminUser $DomainAdminShortUserName " + `
                        "-localAdminPwdEnc `"$DomainAdminEncryptedPassword`" " + `
                        "-domainAdminUser $DomainAdminShortUserName " + `
                        "-domainAdminPwdEnc `"$DomainAdminEncryptedPassword`" " + ` 
                        "-dataDriveLetter " + ($configGlobal.AvailabilityGroupConfig.AGSqlDataDriveLetter) + " " + `
                        "-dataDirectoryName " + ($configGlobal.AvailabilityGroupConfig.AGSqlDataDirectoryName) + " " + `
                        "-logDirectoryName " + ($configGlobal.AvailabilityGroupConfig.AGSqlLogDirectoryName) + " " + `
                        "-backupDirectoryName " + ($configGlobal.AvailabilityGroupConfig.AGSqlBackupDirectoryName) + " " + `
                        "-paramClusterName " + ($configGlobal.ClusterConfig.ClusterName) + " " + `
                        "-paramAzureVirtualClusterName " + ($configGlobal.ClusterConfig.AzureClusterName) + " " + `
                        "-paramClusterIPAddress " + ($configGlobal.ClusterConfig.ClusterIP) + " " + `
                        "-paramSqlInstanceName " + ($sqlVmCfg.NodeName) + " " + `
                        "-paramSqlServiceUser " + ($SqlServerServiceDomainUserName) + " " + `
                        "-paramSqlServicePasswordEnc `"$SqlServerAccountEncryptedPassword`" " + `
                        "-paramSqlEndpointName " + ($configGlobal.AvailabilityGroupConfig.AGEndpointName) + " " + `
                        "-paramSqlEndpointPort " + ($configGlobal.AvailabilityGroupConfig.AGEndpointPort) + " "
            if(($sqlVmCfg.Role -eq "PrimarySqlNode")) {
                $vmExtScriptArguments += "-paramSetupNewCluster "
            }
            if($IsVerbosePresent) {
                $vmExtScriptArguments += "-Verbose "
            }

            # Execute the Remote Script Extension
            Invoke-AzureVmExtensionWithScript -vmTargetName ($sqlVmCfg.NodeName) `
                                              -vmTargetService $vmExtTargetServiceName `
                                              -scriptNameToRun ($configGlobal.GeneralConfig.SetupSqlAllNodes) `
                                              -scriptArguments $vmExtScriptArguments `
                                              -storageAccountName $vmExtStorageAccountName `
                                              -storageContainerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                              -storageAccountKey $vmExtStorageAccountKey `
                                              -WaitIntervalInSec ($configGlobal.GeneralConfig.RetryIntervalSec) `
                                              -WaitMaxAttempts ($configGlobal.GeneralConfig.RetryCount) `
                                              -Verbose:($IsVerbosePresent)
        }

        Write-Host "Preparing some data required for VM Extensions Execution Arguments on both, primary and secondary SQL Nodes..."
        $vmExtAgListenerName = ($configGlobal.AvailabilityGroupConfig.AGName) + "-Listener"
        Write-Verbose -Message "- AG Listener Name: $vmExtAgListenerName"
        $vmExtArrayHelp = @()
        (Get-NodeByRole -config $configGlobal -role "SecondarySqlNode").NodeName `
        | ForEach-Object { $vmExtArrayHelp += "$_" }
        $vmExtSecondarySqlNodes = $vmExtArrayHelp -join ";"
        Write-Verbose -Message "Secondary Nodes: $vmExtSecondarySqlNodes"

        Write-Host "Running configuration scripts on Primary SQL Server Node..."
        Write-Host "- Create the initial databases for the AG Group"
        Write-Host "- Configure BACKUP/RESTORE Credentials for Azure Storage based backups"
        Write-Host "- Create the AG Group with the initial databases"
        Write-Host "- Setup the AlwaysOn Availability Group Listener"

        # Prepare some further arguments for the primary SQL Node VM Extension Execution
        $sqlVmPrimaryCfg = (Get-NodeByRole -config $configGlobal -role "PrimarySqlNode")
        $vmExtPrimarySqlLocalEndPoint = (($sqlVmPrimaryCfg.NodeName) + "." + $DomainName + ":" + `
                                        ($configGlobal.AvailabilityGroupConfig.AGEndpointPort))
        $vmExtParamStorageAccountKeyEnc = Get-EncryptedPassword -certName $certNameForPwdEncryption -passwordToEncrypt ($StorageAccountPrimaryRegionKey.Primary)
        # Prepare the arguments for the VM Extension
        $vmExtScriptArguments = "-scriptsBaseDirectory `"" + ($configGlobal.GeneralConfig.SetupScriptsVmTargetDirectory) + "`" " + `
                                "-certNamePwdEnc $certNameForPwdEncryption " + `
                                "-domainNameShort `"$DomainNameShort`" " + `
                                "-domainAdminUser `"$DomainAdminShortUserName`" " + `
                                "-domainAdminPwdEnc `"$DomainAdminEncryptedPassword`" " + ` 
                                "-paramHaGroupName `"" + ($configGlobal.AvailabilityGroupConfig.AGNAme) + "`" " + `
                                "-paramClusterName `"" + ($configGlobal.ClusterConfig.ClusterName) + "`" " + `
                                "-paramSqlAlwaysOnLocalEndPoint `"$vmExtPrimarySqlLocalEndPoint`" " + `
                                "-paramDatabaseNames " + ($configGlobal.AvailabilityGroupConfig.AGSqlDatabaseNames) + " " + `
                                "-paramPrimarySqlNode `"" + ($sqlVmPrimaryCfg.NodeName) + "`" " + `
                                "-paramSecondarySqlNodes $vmExtSecondarySqlNodes " + `
                                "-paramCreateDatabases " + `
                                "-paramCreateDatabasesSqlScriptFileNames " + ($configGlobal.AvailabilityGroupConfig.AGSqlDatabaseCreateScripts) + " " + `
                                "-paramStorageAccountName `"" + $StorageAccountNamePrimaryRegion + "`" " + `
                                "-paramStorageAccountKeyEnc `"$vmExtParamStorageAccountKeyEnc`" " + `
                                "-paramStorageAccountBackupContainer `"" + ($configGlobal.AvailabilityGroupConfig.AGSqlDatabaseBackupContainerName) + "`" " + `
                                "-paramPrimaryILBIP `"" + ($configGlobal.AvailabilityGroupConfig.AGListenerPrimaryRegionIP) + "`" " + `
                                "-paramPrimaryILBIPSubnetMask `"" + ($configGlobal.AvailabilityGroupConfig.AGListenerPrimaryRegionSubnetMask) + "`" " + `
                                "-paramSecondaryILBIP `"" + ($configGlobal.AvailabilityGroupConfig.AGListenerSecondaryRegionIP) + "`" " + `
                                "-paramSecondaryILBIPSubnetMask `"" + ($configGlobal.AvailabilityGroupConfig.AGListenerSecondaryRegionSubnetMask) + "`" " + `
                                "-paramProbePort `"" + ($configGlobal.AvailabilityGroupConfig.AGProbePort) + "`" " + `
                                "-paramAGListenerName `"$vmExtAgListenerName`" " + `
                                "-paramPrimaryClusterNetworkName `"" + ($configGlobal.ClusterConfig.PrimaryNetwork) + "`" " + `
                                "-paramSecondaryClusterNetworkName `"" + ($configGlobal.ClusterConfig.SecondaryNetwork) + "`" "

        Invoke-AzureVmExtensionWithScript -vmTargetName ($sqlVmPrimaryCfg.NodeName) `
                                          -vmTargetService $serviceNamePrimaryRegion `
                                          -scriptNameToRun ($configGlobal.GeneralConfig.SetupSqlPrimaryNode) `
                                          -storageAccountName $StorageAccountNamePrimaryRegion `
                                          -storageContainerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                          -storageAccountKey ($storageAccountPrimaryRegionKey.Primary) `
                                          -WaitIntervalInSec ($configGlobal.GeneralConfig.RetryIntervalSec) `
                                          -WaitMaxAttempts ($configGlobal.GeneralConfig.RetryCount) `
                                          -scriptArguments ($vmExtScriptArguments) `
                                          -Verbose:($IsVerbosePresent)

        Write-Host "Running configuration scripts on Secondary SQL Server Nodes..."
        Write-Host "- Join the previously created SQL AlwaysOn AG"
        Write-Host "- Restore SQL AlwaysOn AG Databases and join them into the AG"
        $sqlVmScondaryCfg = (Get-NodeByRole -config $configGlobal -role "SecondarySqlNode")
        foreach($sqlVmCfg in $sqlVmScondaryCfg) {
            # Prepare some individual arguments which are different between locations
            if($sqlVmCfg.Location -eq 1) {
                $vmExtServiceName = $serviceNamePrimaryRegion
                $vmExtStorageAccountForScriptsName = $StorageAccountNamePrimaryRegion
                $vmExtStorageAccountForScriptsKey = $storageAccountPrimaryRegionKey
                $vmExtParamStorageAccountName = $StorageAccountNamePrimaryRegion
                $vmExtParamCommitMode = "Synchronous_Commit"
                $vmExtParamFailoverMode = "Automatic"
            } else {
                $vmExtServiceName = $serviceNameSecondaryRegion
                $vmExtStorageAccountForScriptsName = $StorageAccountNameSecondaryRegion
                $vmExtStorageAccountForScriptsKey = $storageAccountSecondaryRegionKey
                $vmExtParamStorageAccountName = $StorageAccountNamePrimaryRegion # Note: at the moment the script always backs up into the primary region
                $vmExtParamCommitMode = "Asynchronous_Commit"
                $vmExtParamFailoverMode = "Manual"
            }
            $vmExtParamSqlLocalEndPoint = (($sqlVmCfg.NodeName) + "." + $DomainName + ":" + `
                                           ($configGlobal.AvailabilityGroupConfig.AGEndpointPort))
            # Prepare the arguments for the VM Extension
            $vmExtScriptArguments = "-scriptsBaseDirectory `"" + ($configGlobal.GeneralConfig.SetupScriptsVmTargetDirectory) + "`" " + `
                                    "-certNamePwdEnc $certNameForPwdEncryption " + `
                                    "-domainNameShort `"$DomainNameShort`" " + `
                                    "-domainAdminUser `"$DomainAdminShortUserName`" " + `
                                    "-domainAdminPwdEnc `"$DomainAdminEncryptedPassword`" " + ` 
                                    "-paramHaGroupName `"" + ($configGlobal.AvailabilityGroupConfig.AGNAme) + "`" " + `
                                    "-paramClusterName `"" + ($configGlobal.ClusterConfig.AzureClusterName) + "`" " + `
                                    "-paramDatabaseNames " + ($configGlobal.AvailabilityGroupConfig.AGSqlDatabaseNames) + " " + `
                                    "-paramBackupStorageAccountName `"" + $vmExtParamStorageAccountName + "`" " + `
                                    "-paramBackupStorageAccountBackupContainer `"" + ($configGlobal.AvailabilityGroupConfig.AGSqlDatabaseBackupContainerName) + "`" " + `
                                    "-paramSqlInstanceToAdd `"" + ($sqlVmCfg.NodeName) + "`" " + `
                                    "-paramSqlAlwaysOnLocalEndpoint `"$vmExtParamSqlLocalEndPoint`" " + `
                                    "-paramCommitMode `"$vmExtParamCommitMode`" " ` +
                                    "-paramFailoverMode `"$vmExtParamFailoverMode`" " 

            Invoke-AzureVmExtensionWithScript -vmTargetName ($sqlVmCfg.NodeName) `
                                              -vmTargetService $vmExtServiceName `
                                              -scriptNameToRun ($configGlobal.GeneralConfig.SetupSqlSecondaryNodes) `
                                              -storageAccountName $vmExtStorageAccountForScriptsName `
                                              -storageContainerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                              -storageAccountKey ($vmExtStorageAccountForScriptsKey.Primary) `
                                              -WaitIntervalInSec ($configGlobal.GeneralConfig.RetryIntervalSec) `
                                              -WaitMaxAttempts ($configGlobal.GeneralConfig.RetryCount) `
                                              -scriptArguments ($vmExtScriptArguments) `
                                              -Verbose:($IsVerbosePresent)
        }

        Write-Host "Running configuration scripts on the SQL Witness..."
        Write-Host "- Creates a file share on the Witness"
        Write-Host "- Configures the quorum to include the Witness"
        $sqlWitnessVmCfg = (Get-NodeByRole -config $configGlobal -role "SqlWitness")

        $vmExtScriptArguments = "-scriptsBaseDirectory `"" + ($configGlobal.GeneralConfig.SetupScriptsVmTargetDirectory) + "`" " + `
                                "-certNamePwdEnc $certNameForPwdEncryption " + `
                                "-domainNameShort `"$DomainNameShort`" " + `
                                "-domainAdminUser `"$DomainAdminShortUserName`" " + `
                                "-domainAdminPwdEnc `"$DomainAdminEncryptedPassword`" " + `
                                "-paramWitnessFolderName `"" + ($configGlobal.ClusterConfig.WitnessFolder) + "`" " + `
                                "-paramWitnessShareName  `"" + ($configGlobal.ClusterConfig.WitnessShare) + "`" " + `
                                "-paramSqlServiceAccount  `"" + $SqlServerServiceDomainUserName + "`" " + `
                                "-paramAzureVirtualClusterName  `"" + ($configGlobal.ClusterConfig.AzureClusterName) + "`" " + `
                                "-paramSqlAvailabilityGroupName `"" + ($configGlobal.AvailabilityGroupConfig.AGNAme) + "`""

        Invoke-AzureVmExtensionWithScript -vmTargetName ($sqlWitnessVmCfg.NodeName) `
                                          -vmTargetService $serviceNamePrimaryRegion `
                                          -scriptNameToRun ($configGlobal.GeneralConfig.SetupSqlWitnessNode) `
                                          -storageAccountName $StorageAccountNamePrimaryRegion `
                                          -storageContainerName ($configGlobal.GeneralConfig.SetupScriptsStorageContainerName) `
                                          -storageAccountKey ($StorageAccountPrimaryRegionKey.Primary) `
                                          -WaitIntervalInSec ($configGlobal.GeneralConfig.RetryIntervalSec) `
                                          -WaitMaxAttempts ($configGlobal.GeneralConfig.RetryCount) `
                                          -scriptArguments ($vmExtScriptArguments) `
                                          -Verbose:($IsVerbosePresent)

    } catch {
        Write-Error $_.Exception.Message
        Write-Error $_.Exception.ItemName
        throw "Failed setting up SQL Server AlwaysOn Availability Groups. Please review earlier error messages for details!"     
    }
}


Write-Host ""
Write-Host "----------------------------------------------------------------------"
Write-Host "Creating Remote Desktop Manager Files if requested..."
Write-Host "----------------------------------------------------------------------"
if(-not $RemoteDesktopCreate) {
    Write-Host "-- Skipping RDC Manager File Creation, please specify '-RemoteDesktopCreate' to create RDP and RDCMan files!"
} else {
    if(-not [System.IO.Path]::IsPathRooted($RemoteDesktopOutputPath)) {
        $RemoteDesktopOutputPath = [System.IO.Path]::Combine((Get-Location), $RemoteDesktopOutputPath)
    }
    
    Write-Host "-- Creating Remote Desktop Files in $RemoteDesktopOutputPath..."
    if(-not (Test-Path $RemoteDesktopOutputPath)) {
        New-Item -ItemType Directory $RemoteDesktopOutputPath
    }

    # Get the normal Remote Desktop Files
    Write-Host "-- Getting standard RDP Files from Azure..."
    $vmsForRdp = @()
    $vmsForRdp += (Get-NodeByRole -config $configGlobal)
    foreach($rdpVm in $vmsForRdp) {
        $rdpFileName = ([System.IO.Path]::Combine($RemoteDesktopOutputPath, $rdpVm.NodeName + ".rdp"))
        if($rdpVm.Location -eq 1) {
            Get-AzureRemoteDesktopFile -ServiceName $serviceNamePrimaryRegion -Name ($rdpVm.NodeName) -LocalPath $rdpFileName
        } else {
            Get-AzureRemoteDesktopFile -ServiceName $serviceNameSecondaryRegion -Name ($rdpVm.NodeName) -LocalPath $rdpFileName
        }
    }
}


Write-Host ""
Write-Host "******************************************************************************" -ForegroundColor Green
Write-Host "** Cross-Region SQL Server AlwaysOn Availability Group Setup COMPLETED !!!! **" -ForegroundColor Green
Write-Host "******************************************************************************" -ForegroundColor Green
$endTime = (Get-Date)
$duration = ($endTime.Subtract($startTime))
Write-Host "- Start Time:            $startTime"
Write-Host "- End Time:              $endTime"
Write-Host "- Duration:              $duration"
Write-Host "- Setup Fundamentals:    ALWAYS (cloud services, storage accounts)"
Write-Host "- Upload Setup Scripts:  $UploadSetupScripts"
Write-Host "- Setup Networking:      $SetupNetwork"
Write-Host "- Setup AD Forest:       $SetupADDCForest"
Write-Host "- Setup Secondary ADDCs: $SetupSecondaryADDCs"
Write-Host "- Setup SQL VMs:         $SetupSQLVMs"
Write-Host "- Setup SQL AG:          $SetupSQLAG"
Write-Host "******************************************************************************" -ForegroundColor Green
Write-Host ""