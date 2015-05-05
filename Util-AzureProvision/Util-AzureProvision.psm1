#####################################################
# Utility functions for provisioning items on Azure #
#####################################################


#
# General Utility Functions used as part of the main provisioning script #####################
#

# Creates a ZIP archive of files (to be uploaded later to e.g. Blob storage)
function New-ZipArchive($parentDirectory, $zipFileName) {
    $existingFile = Get-Item $zipFileName -ErrorAction SilentlyContinue
    if($existingFile -ne $null) {
        Remove-Item $zipFileName
    }

    Add-Type -Assembly System.IO.Compression.FileSystem
    $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
    [System.IO.Compression.ZipFile]::CreateFromDirectory($parentDirectory, $zipFileName, $compressionLevel, $false)
}

# Gets a node configuration from our provisioning configuration file
function Get-NodeByRole($config, [string]$role=$null, [Int32]$location=-1)
{
    $nodes = $config.AllNodes
    if ($role)
    {
        $nodes = $nodes | Where { $_.Role -eq $role }
    }
    if ($location -ne -1)
    {
        $nodes = $nodes | Where { $_.Location -eq $location}
    }
    return $nodes
}

function Write-VerboseNodeConfiguration
{
    [CmdletBinding()]
    Param(
        $node
    )

    Write-Verbose -Message ("- " + $node.Role)
    Write-Verbose -Message ("- " + $node.NodeName)
    Write-Verbose -Message ("- " + $node.IP)
    Write-Verbose -Message ("- " + $node.Subnet)
    Write-Verbose -Message ("- " + $node.Location)
}

# Executes a PowerShell script block on a remote machine with a given number of retries
function Invoke-RemotePSScript
{
    [CmdletBinding()]
    Param(
        $vm, $adminUser, $adminPwd, $scriptBlock, $remotePsLocalPort, $retryNum, $retryIntervalSec, $variables
    )

    $retryCounter = 0

    Write-Verbose -Message "Calling Remote PowerShell Script with the following variables/parameters:"
    foreach($v in $variables.Keys) {
        if(($v.ToLower().Contains("password")) -or ($v.ToLower().Contains("pwd")) -or ($v.ToLower().Contains("secred"))) {
            Write-Verbose -Message ("- $v = <password value not primted>")
        } else {
            Write-Verbose -Message ("- $v = " + $variables[$v])
        }
    }
    
    Write-Verbose -Message ("Getting endpoints from virtual machine " + $vm.Name)
    $allendpoints = $vm | Get-AzureEndpoint
    Write-Verbose -Message "Locating Remote Powershell endpoint per local port $remotePsLocalPort..."
    $poshEP = $allendpoints | where {$_.LocalPort -match $remotePsLocalPort}
    if($poshEP -eq $null) {
        throw "Endpoint for Remote PowerShell not found!"
    }

    $vip = $poshEP.Vip
    $port = $poshEP.Port
    $secPassword = ConvertTo-SecureString $adminPwd -AsPlainText -Force
    $remotePoShCred = New-Object System.Management.Automation.PSCredential ($adminUser, $secPassword)

    do {
        Write-Verbose -Message "Starting New PowerShell session on remote computer..."
        Write-Verbose -Message "- Remote IP = $vip"
        Write-Verbose -Message "- Port = $port"
        $session = New-PSSession -ComputerName $vip `
                                 -Port $port -UseSSL -Credential $remotePoShCred `
                                 -Sessionoption (New-PSSessionOption -skipcacheck -skipcncheck) `
                                 -ErrorAction Continue
        
        if($session) {
            Write-Verbose -Message "Invoking remote commands on virtual machine..."
            #$RemoteError = ""
            Invoke-Command -Session $session -ScriptBlock $scriptBlock #-ErrorVariable RemoteError
            #if($RemoteError.Length -gt 0) {
            #    throw "Failed executing remote script with errors! Please review earlier error messages!"
            #}
            Disconnect-PSSession $session -ErrorAction Ignore
        }
        else {
            Write-Verbose -Message "Remote VM not ready for remote PowerShell session ... wait and retry ..."
            Write-Verbose -Message "Number of retries so far: $retryCounter"
            Write-Verbose -Message "Waiting for $retryIntervalSec until next retry..."
            $retryCounter++
            Start-Sleep $retryIntervalSec 
        }
    }while( ($session -eq $null) -Or ($retryCounter -gt $retryNum) )
    
    if($retryCounter -gt $retryNum) {
        throw "Failed executing remote command on machine!"
    }
}


#
# Generic, re-usable Azure Helper Functions ##################################################
#

# Creates a cloud service in case it does not exist, yet
function New-CloudServiceIfNotExists {
    [CmdletBinding()]
    Param(
        $cloudServiceName, $location
    )

    Write-Verbose -Message "Checking if Cloud Service $cloudServiceName exists in location $location..."
    $cloudService = Get-AzureService -ServiceName $cloudServiceName -ErrorAction SilentlyContinue
    if( $cloudService -eq $null) 
    {
        Write-Verbose -Message "Cloud service $cloudServiceName does not exist, creating one..."
        New-AzureService -ServiceName $cloudServiceName -Location $location -Label $cloudServiceName
        Write-Verbose -Message "Cloud service created successfully..."
    }
    $cloudService = Get-AzureService -ServiceName $cloudServiceName
    if( $cloudService -eq $null )
    {
        throw "Unable to retrieve cloud service, so creation must have failed!"
    }
    return $cloudService
}

# Adds a certificate to a cloud service if it does not exist, yet
function Add-CloudServiceCertificateIfNotExists {
    [CmdletBinding()]
    Param(
        [String] $cloudServiceName,
        [PSCredential] $certificateCreds,
        [String] $certPfxFile
    )
    
    Write-Verbose -Message "Getting existing Certificate from store..."
    $cert = Get-SelfSignedCertificateByName -certName ($certificateCreds.UserName)
    if($cert -eq $null) {
        throw ("Certificate with name CN=" + ($certificateCreds.UserName) + " not found in LocalMachine/My certificate store!")
    }
    
    Write-Verbose -Message "Checking if Certificate exists in Cloud Service $cloudServiceName..."
    $foundCert = $false
    $existingCert = Get-AzureCertificate -ServiceName $cloudServiceName
    foreach($c in $existingCert) {
        if($c.Thumbprint -eq $cert.Thumbprint) {
            $foundCert = $true
        }
    }
    
    Write-Verbose -Message "Adding certificate to cloud service if it does not exist, yet."
    if($foundCert) {
        Write-Verbose -Message "-- Skipping, certificate exists in cloud service, already!"    
    } else {
        try {
            Add-AzureCertificate -CertToDeploy $certPfxFile -ServiceName $cloudServiceName -Password ($certificateCreds.GetNetworkCredential().Password) -ErrorAction Stop
        } catch {
            throw "Failed adding certificate to cloud service! Please verify parameters such as certificate PFX file path or PFX password!"
        }
    }
}

# Creates a storage account in case it does not exist, yet
function New-CloudStorageAccountIfNotExists {
    [CmdletBinding()]
    Param(
        $storageAccountName, $location
    )

    Write-Verbose -Message "Checking if Storage Account $storageAccountName exists in $location..."
    $storageAccount = Get-AzureStorageAccount -StorageAccountName $storageAccountName -ErrorAction SilentlyContinue
    if( $storageAccount -eq $null )
    {
        Write-Verbose -Message "Storage Account $storageAccountName does not exist, creating one..."
        $storageAccount = New-AzureStorageAccount -StorageAccountName $storageAccountName -Type Standard_LRS -Label $storageAccountName -Location $location
        Write-Verbose -Message "Succeeded creating storage account!"
    }
    else 
    {
        Write-Verbose -Message "Storage Account $storageAccountName exists, already!"
    }
    return $storageAccount
}

# Creates a container in a blob storage in case it does not exist, yet
function New-StorageContainerIfNotExists {
    [CmdletBinding()]
    Param(
        $storageContext, $containerName
    )

    Write-Verbose -Message "Checking if storage container $containerName exists in storage account."
    $existingContainer = Get-AzureStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue
    if($existingContainer -eq $null) {
        Write-Verbose -Message "Container does not exist, creating it now..."
        $existingContainer = New-AzureStorageContainer -Name $containerName -Context $storageContext
    } else {
        Write-Verbose -Message "Container exists, skipping creation!"
    }
    return $existingContainer
}

# Uploads a list of files to a blob storage container
function Send-FilesToStorageContainer {
    [CmdletBinding()]
    Param(
        $storageContext, $containerName, $filesList
    )

    foreach($file in $filesList) {
        Write-Verbose -Message "Uploading $file..."
        $blobName = [System.IO.Path]::GetFileName($file)
        Write-Verbose -Message "to blob $blobName in container $containerName"
        Set-AzureStorageBlobContent -File $file `
                                    -Container $containerName `
                                    -Blob $blobName `
                                    -Context $storageContext `
                                    -BlobType Block `
                                    -Force
    }
}

# Getting a shared access signature URL for a storage blob
function Get-SharedAccessBlobUrl {
    [CmdletBinding()]
    Param(
        $storageContext, $containerName, $fileName, 
        [ValidateSet("r", "w", "d", "rw", "rwd", "wd", "rd")]$permission = "r",
        $expiresInMinutes = 60
    )

    $baseUrl = ($storageContext.BlobEndPoint + "$containername/$filename")
    Write-Verbose -Message "Getting SAS for blob with following details: "
    Write-Verbose -Message "- $baseUrl"
    $sasToken = New-AzureStorageBlobSASToken -Container $containerName  `
                                             -Blob $fileName `
                                             -Context $storageContext `
                                             -Permission $permission `
                                             -StartTime (get-date).ToUniversalTime() `
                                             -ExpiryTime ((get-date).ToUniversalTime().AddMinutes($expiresInMinutes))
    Write-Verbose -Message "- Token: $sasToken"
    Write-Verbose -Message "- Url: $baseUrl$sasToken"
    return "$baseUrl$sasToken"
}

# Gets the latest version of a VMImage from the Azure VM Image gallery
function Get-LatestAzureVMImage {
    [CmdletBinding()] 
    Param(
        $ImageFamily
    )

    Write-Verbose -Message "Getting the latest VMImage for $ImageFamily"
    $img = (Get-AzureVMImage | ? ImageFamily -match $ImageFamily | Sort PublishedDate -Descending)[0]
    $vmImage = $img.ImageName
    $date = $img.PublishedDate
    Write-Verbose -Message "VMImage - $ImageFamily on $date"
    return $img;
}


#
# SQL AG Deployment Specific Helper Funcitons ################################################
#

# Creates the Azure VM Config for primary domain controllers
function New-PrimaryADVMConfig {
    [CmdletBinding()]
    Param (
        $adVms, $vmSize, $imageName, $availabilitySetName, 
        $adminUser, $adminPwd, 
        $storageAccountName, $vhdContainerName, 
        $certToDeploy, 
        $custInstContainerName, $custInstFileName, $customVmExtArguments
    )

    # Deploy the certificate into LocalMachine\My
    $certConfig = New-AzureCertificateSetting -Thumbprint ($certToDeploy.Thumbprint) -StoreName "My"

    # Add the VM configuration settings
    $provisionVMs = @()
    ForEach( $dc in $adVms )
    {   
        $dcName = $dc.NodeName
        $mediaLocation = ("http://$storageAccountName.blob.core.windows.net/$vhdContainerName/$dcName-disk.vhd")
        Write-Verbose -Message "Adding AD-DC VM $dcName"
        Write-Verbose -Message "- VHD: $mediaLocation"
        # Create VM for DC...
        $provisionVMs += New-AzureVMConfig -Name $dc.NodeName -InstanceSize $vmSize -ImageName $imageName -AvailabilitySetName $availabilitySetName -MediaLocation $mediaLocation `
            | Add-AzureProvisioningConfig -Windows -AdminUsername $adminUser -Password $adminPwd -Certificates $certConfig `
            | Set-AzureStaticVNetIP -IPAddress $dc.IP `
            | Set-AzureSubnet -SubnetNames $dc.Subnet `
            | Set-AzureVMMicrosoftAntimalwareExtension `
                         -AntimalwareConfiguration '{ "AntimalwareEnabled": true }' `
            | Set-AzureVMCustomScriptExtension -ContainerName $custInstContainerName `
                                               -FileName "$custInstFileName","Util-CertsPasswords.psm1" `
                                               -Run $custInstFileName `
                                               -Argument $customVmExtArguments
    }
    
    return $provisionVMs

    # Add additional NICs to the VM configuration
    # Add-AzureNetworkInterfaceConfig -Name "Ethernet2" -SubnetName "BE" -StaticVNetIPAddress "10.2.2.222" -VM $vm
}

# Creates the Azure VM Config for secondary domain controllers
function New-AdditionalADVMsConfig {
    [CmdletBinding()]
    Param (
        $adVms, $vmSize, $imageName, $availabilitySetName, 
        $adminUser, $adminPwd, 
        $domain, $shortDomain, $domainAdminName, $domainAdminPwd, 
        $storageAccountName, $vhdContainerName,
        $certToDeploy, 
        $custInstContainerName, $custInstFileName, $customVmExtArguments
    )
    
    # Deploy the certificate into LocalMachine\My
    $certConfig = New-AzureCertificateSetting -Thumbprint ($certToDeploy.Thumbprint) -StoreName "My"

    $provisionVMs = @()
    ForEach( $dc in $adVms )
    {   
        $dcName = $dc.NodeName
        $mediaLocation = ("http://$storageAccountName.blob.core.windows.net/$vhdContainerName/$dcName-disk.vhd")
        Write-Verbose -Message "Adding AD-DC VM $dcName"
        Write-Verbose -Message "- VHD: $mediaLocation"
        Write-Verbose -Message "- VMExt Container: $custInstContainerName"
        # Create VM for DC...
        $provisionVMs += New-AzureVMConfig -Name $dc.NodeName -InstanceSize $vmSize -ImageName $imageName -AvailabilitySetName $availabilitySetName -MediaLocation $mediaLocation `
            | Add-AzureProvisioningConfig -WindowsDomain -AdminUsername $adminUser -Password $adminPwd -JoinDomain $domain -DomainUserName $domainAdminName -DomainPassword $domainAdminPwd -Domain $shortDomain -Certificates $certConfig `
            | Set-AzureStaticVNetIP -IPAddress $dc.IP `
            | Set-AzureSubnet -SubnetNames $dc.Subnet `
            | Set-AzureVMMicrosoftAntimalwareExtension `
                         -AntimalwareConfiguration '{ "AntimalwareEnabled": true }' `
            | Set-AzureVMCustomScriptExtension -ContainerName $custInstContainerName `
                                               -FileName "$custInstFileName","Util-CertsPasswords.psm1" `
                                               -Run $custInstFileName `
                                               -Argument $customVmExtArguments
    }
    
    return $provisionVMs

    # Add additional NICs to the VM configuration
    # Add-AzureNetworkInterfaceConfig -Name "Ethernet2" -SubnetName "BE" -StaticVNetIPAddress "10.2.2.222" -VM $vm
}

# Creates the Azure VM Config for SQL Server machines for the AlwaysOn AG Cluster
function New-SQLVMsConfig {
    [CmdletBinding()]
    Param(
        $sqlVms, $vmSize, $imageName, $availabilitySetName, 
        $adminUser, $adminPwd, 
        $domain, $shortDomain, $domainAdminName, $domainAdminPwd, 
        $certToDeploy,
        $custInstContainerName, $custInstFileName, 
        $custInstClusterFeature, $custInstDownloadFiles, $custInstZipFileLink, $custInstLocalScriptsDir,
        $storageAccountName, $vhdContainerName
    )

    # Deploy the certificate into LocalMachine\My
    $certConfig = New-AzureCertificateSetting -Thumbprint ($certToDeploy.Thumbprint) -StoreName "My"

    # Array for the VM Configurations to create
    $provisionVMs = @()

    ForEach($sql in $sqlVms)
    {   
        $sqlname = $sql.NodeName
        Write-Verbose -Message "Adding SQL VM $sqlname"
        
        Write-Verbose -Message "Creating Arguments for Custom Script VM Extension..."
        $customVmExtArguments = ""
        if($custInstDownloadFiles) {
            $customVmExtArguments = ($customVmExtArguments + ' -downloadFiles -downloadZipArchiveLink "' + $custInstZipFileLink + '" -targetDirectory "' + $custInstLocalScriptsDir + '"')
        }
        if($custInstClusterFeature) {
            $customVmExtArguments = ($customVmExtArguments + " -installClusterFeatureAsWell")
        }
        Write-Verbose -Message "Arguments for Custom Script Extension: $customVmExtArguments"

        $mediaLocation = ("http://$storageAccountName.blob.core.windows.net/$vhdContainerName/$sqlname-OS-disk.vhd")
        Write-Verbose -Message "Adding SQL VM $sqlname"
        Write-Verbose -Message "- VHD: $mediaLocation"

        Write-Verbose -Message "Creating AzureVMConfig..."
        $sqlVm = New-AzureVMConfig -Name $sql.NodeName -InstanceSize $vmSize -ImageName $imageName -AvailabilitySetName $availabilitySetName -MediaLocation $mediaLocation `
            | Add-AzureProvisioningConfig -WindowsDomain -AdminUsername $adminUser -Password $adminPwd -JoinDomain $domain -DomainUserName $domainAdminName -DomainPassword $domainAdminPwd -Domain $shortDomain -Certificates $certConfig `
            | Set-AzureStaticVNetIP -IPAddress $sql.IP `
            | Set-AzureSubnet -SubnetNames $sql.Subnet `
            | Set-AzureVMMicrosoftAntimalwareExtension `
                         -AntimalwareConfiguration '{ "AntimalwareEnabled": true }' `
            | Set-AzureVMCustomScriptExtension -ContainerName $custInstContainerName `
                                               -FileName $custInstFileName `
                                               -Run $custInstFileName `
                                               -Argument $customVmExtArguments

        if($sql.StorageSpaces -ne $null) {
            Write-Verbose -Message "Adding Data Disks to SQL VM..."           
            $diskSizeGB = $sql.StorageSpaces.DataDiskSizeGB / $sql.StorageSpaces.DataDiskStripes        
            $stripes = $sql.StorageSpaces.DataDiskStripes
            Write-Verbose -Message "Adding $stripes disks to VM $sqlname."
            
            for ($idx=1;$idx -le $sql.StorageSpaces.DataDiskStripes;$idx++)
            {
                $mediaLocation = ("http://$storageAccountName.blob.core.windows.net/$vhdContainerName/$sqlname-DATA-disk$idx.vhd")
                Write-Verbose -Message "Adding SQL Data Disk $mediaLocation"

                $sqlVm = $sqlVm `
                    | Add-AzureDataDisk -CreateNew -DiskSizeInGB $diskSizeGB -DiskLabel "Disk$idx" -LUN $idx -HostCaching None -MediaLocation $mediaLocation
            }
        } else {
            Write-Verbose -Message "No data disks defined for SQL VM $sqlname!!"
        }
        $provisionVMs += $sqlVm
    }
    
    return $provisionVMs
}

# Adds the load balanced endpoints for the internal load balancer to the SQL Server VMs for the AG Listener
function Set-SQLVMsILB {
    [CmdletBinding()]
    Param(
        [string]$svcloc, 
        [string]$epName, [string]$epPort, [string]$prPort, 
        [string]$ilbName, 
        $vms
    )

    Write-Verbose -Message "Updating SQL VMs in location $svcloc to use the Internal Loadbalancer"
    foreach($node in $vms)
    {
        Get-AzureVM -ServiceName $svcloc -Name $node.NodeName `
            | Add-AzureEndpoint -DirectServerReturn 1 -Name $epName `
                -LBSetName "$epName-LB" -Protocol tcp -LocalPort $epPort `
                -PublicPort $epPort -ProbePort $prPort -ProbeProtocol tcp `
                -ProbeIntervalInSeconds 10 -InternalLoadBalancerName $ilbName `
            | Update-AzureVM 
    }
}

# Filters a list of VM Definitions only containing VMS that do not exist, yet
function Get-VmDefsNonExistingAzureVms {
    [CmdletBinding()]
    Param(
        $vmDefsArray, 
        $serviceName
    )

    $resultArray = @()
    foreach($vDef in $vmDefsArray) {
        Write-Verbose ("- Checking " + ($vDef.RoleName) + " in $serviceName...")
        $vm = Get-AzureVM -ServiceName $serviceName -Name ($vDef.RoleName) -ErrorAction SilentlyContinue
        if($vm -eq $null) {
            $resultArray += $vDef
        } else {
            Write-Verbose -Message ("- Skipping " + ($vDef.RoleName) + " as it exists, already!")
        }
    }
    return $resultArray
}

# Wait for VMS to be in status ReadyRole
function Wait-AzureVmsReady {
    [CmdletBinding()]
    Param(
        $vmServiceNamesToMonitor,
        $sleepInSecondsInterval
    )

    $numVmsNotReady = 9999
    do {
        $vms = @()
        Write-Verbose -Message "Getting VMS from services..."
        foreach($vmService in $vmServiceNamesToMonitor) {
            Write-Verbose -Message "- Service $vmService"
            $vms += (Get-AzureVM -ServiceName $vmService)
        }

        if($vms.Length -eq 0) {
            $numVmsNotReady = 0
            Write-Verbose -Message "No VMs in services, nothing to wait for."
        } else {
            $numVmsNotReady = ($vms | Where { $_.Status -ne "ReadyRole" }).Length
            Write-Verbose -Message "Number of VMs not in ReadyRole state: $numVmsNotReady"
        }

        if($numVmsNotReady -ne 0) {
            Write-Verbose -Message "Sleeping in Seconds: $sleepInSecondsInterval"
            Start-Sleep $sleepInSecondsInterval
        }
    }while($numVmsNotReady -ne 0)
}

# Invoke a powershell script via VM Extension
function Invoke-AzureVmExtensionWithScript {
    [CmdletBinding()]
    Param(
        $vmTargetName,
        $vmTargetService,
        [Parameter(Mandatory)]$scriptNameToRun,
        [Parameter(Mandatory=$false)]$scriptArguments = "",
        [Parameter(Mandatory=$false)]$additionalScriptsToCopy = @(),
        [Parameter(Mandatory)]$storageAccountName,
        [Parameter(Mandatory)]$storageContainerName,
        [Parameter(Mandatory)]$storageAccountKey,
        [Parameter(Mandatory=$false)]$WaitForCompletion = $true,
        [Parameter(Mandatory=$false)]$WaitIntervalInSec = 30,
        [Parameter(Mandatory=$false)]$WaitMaxAttempts = 100
    )

    # Get the target virtual machine depending on parameters
    Write-Verbose -Message "Start executing remote command $scriptNameToRun on VM..."
    if(($vmTargetName -eq $null) -or ($vmTargetService -eq $null)) {
        throw "Either specify the vmTarget parameter or vmTargetName together with vmTargetService!!"
    }
    Write-Verbose -Message "-- Virtual Machine $vmTargetName in Cloud Service $vmTargetService!"
    $vmToRunOn = Get-AzureVM -ServiceName $vmTargetService -Name $vmTargetName
    if($vmToRunOn -eq $null) {
        throw "Target virtual machine could not be retrieved from Microsoft Azure Management APIs..."
    }

    # Get the timestamp of the last executed custom script extension on the VM (so that an update to this new one can be detected!)
    $lastExecutionTimeStamp = Get-AzureVMCustomScriptExtensionLastExecutionTime -vm $vmToRunOn

    # Set the VM Extension to start its execution
    Write-Verbose -Message "Setting custom script extension for Virtual Machine..."
    $files = @()
    $files = $additionalScriptsToCopy
    $files += $scriptNameToRun
    foreach($fn in $files) {
        Write-Verbose -Message "- File to copy: $fn..."
    }
    try {
        if(-not [String]::IsNullOrEmpty($scriptArguments)) {
            Set-AzureVMCustomScriptExtension -StorageAccountName $storageAccountName `
                                             -StorageAccountKey $storageAccountKey `
                                             -ContainerName $storageContainerName `
                                             -FileName $files `
                                             -Run $scriptNameToRun `
                                             -Argument ($scriptArguments) `
                                             -VM $vmToRunOn `
                                             | Update-AzureVM
        } else {
            Set-AzureVMCustomScriptExtension -StorageAccountName $storageAccountName `
                                             -StorageAccountKey $storageAccountKey `
                                             -ContainerName $storageContainerName `
                                             -FileName $files `
                                             -Run $scriptNameToRun `
                                             -VM $vmToRunOn `
                                             | Update-AzureVM
        }
    } catch {
        Write-Error $_.Exception.Message
        Write-Error $_.Exception.ItemName
        throw "Failed starting the azure custom script extension. Stopping!"
    }

    # Enter the wait-loop for the custom script extension
    if($WaitForCompletion) {
        $waitResult = Wait-AzureVmForCustomScriptExtension -vmTargetName $vmTargetName -vmTargetService $vmTargetService `
                                                           -vmPreviousScriptTimestamp $lastExecutionTimeStamp `
                                                           -WaitIntervalInSec $WaitIntervalInSec -WaitMaxAttempts $WaitMaxAttempts
        if($waitResult -ne "CompletedSuccessfully") {
            throw "Failed Executing Custom Script Extension. Please Review Messages Earlier in the Output: $waitResult!!"
        }
    }
}

# Get the timestamp from the previously executed custom script extension
function Get-AzureVMCustomScriptExtensionLastExecutionTime {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false)]$vm,
        [Parameter(Mandatory=$false)]$vmTargetName,
        [Parameter(Mandatory=$false)]$vmTargetService
    )
    try {
        $vmToRunOn = $vm
        if($vm -eq $null) {
            if(([String]::IsNullOrEmpty($vmTargetName)) -or ([String]::IsNullOrEmpty($vmTargetService))) {
                throw "Either specify vm-parameter or vmTargetName and vmTargetService parameters!!"
            } else {
                $vmToRunOn = Get-AzureVM -ServiceName $vmTargetService -Name $vmTargetName
            }
        }
        $extStatus = ($vmToRunOn.ResourceExtensionStatusList | Where{$_.HandlerName -eq "Microsoft.Compute.CustomScriptExtension"})
        $extLastTimeStamp = ""
        if(($extStatus -ne $null) -and ($extStatus.ExtensionSettingStatus -ne $null) -and ($extStatus.ExtensionSettingStatus.TimestampUtc -ne $null)) {
            $extLastTimeStamp = $extStatus.ExtensionSettingStatus.TimestampUtc.ToString()
            Write-Verbose -Message "Existing time stamp on custom script extension: $extLastTimeStamp"
        }

        return $extLastTimeStamp
    } catch {
        Write-Verbose "No previous script execution timestamp..."
        return ""
    }
}

# Wait for custom script extensions to be finished
function Wait-AzureVmForCustomScriptExtension {
    [CmdletBinding()]
    Param(
        $vmTargetName,
        $vmTargetService,
        $vmPreviousScriptTimestamp,
        [Parameter(Mandatory=$false)]$WaitIntervalInSec = 30,
        [Parameter(Mandatory=$false)]$WaitMaxAttempts = 100
    )

    Write-Verbose -Message "Waiting for script execution to complete as requested!"
    $completed = $false
    $completedWithErrors = $false
    $waitAttempts = 0
    do {
        $vmToRunOn = Get-AzureVM -ServiceName $vmTargetService -Name $vmTargetName
        if($vmToRunOn -eq $null) {
            throw "Virtual machine to check for VM Extension Not found!"
        }
        Write-Verbose -Message ("Virtual Machine retrieved: " + $vmToRunOn.InstanceName)
        try {
            Write-Verbose -Message "Getting status details on VM Extension for Virtual Machine..."
            $extStatus = ($vmToRunOn.ResourceExtensionStatusList | Where{$_.HandlerName -eq "Microsoft.Compute.CustomScriptExtension"})
            $extOperation = $extStatus.ExtensionSettingStatus.Operation
            $extStatusVal = $extStatus.ExtensionSettingStatus.Status
            $extStatusCommandStatus = $extStatus.ExtensionSettingStatus.FormattedMessage.Message
            $extStdOut = $extStatus.ExtensionSettingStatus.SubStatusList | Where{$_.Name -eq "StdOut"}
            $extStdErr = $extStatus.ExtensionSettingStatus.SubStatusList | Where{$_.Name -eq "StdErr"}
            $currentScriptTimeStamp = Get-AzureVMCustomScriptExtensionLastExecutionTime -vm $vmToRunOn
            Write-Verbose -Message "- Operation: $extOperation"
            Write-Verbose -Message "- Status: $extStatusVal"
            Write-Verbose -Message "- Command Status: $extStatusCommandStatus"
            Write-Verbose -Message "- Previous Timestamp: $vmPreviousScriptTimestamp"
            Write-Verbose -Message "- Current Timestamp: $currentScriptTimeStamp"

            # Check if the command execution is done...
            if($vmPreviousScriptTimestamp -ne $currentScriptTimeStamp) {
                if(($extStatusCommandStatus -eq "Finished executing command")) {
                    $completed = $true
                    Write-Verbose -Message "Execution of custom script extension completed..."
                    if(-not [String]::IsNullOrEmpty($extStdOut.FormattedMessage.Message)) {
                        $stdOutFormatted = $extStdOut.FormattedMessage.Message.Replace("\n", "`n")
                        Write-Verbose "Script Output`n$stdOutFormatted"
                    } else {
                        Write-Verbose "No standard output available from script!"
                    }
                    if(-not [String]::IsNullOrEmpty($extStdErr.FormattedMessage.Message)) {
                        $completedWithErrors = $true
                        $stdErrFormatted = $extStdErr.FormattedMessage.Message.Replace("\n", "`n")
                        Write-Error "Error Output:`n$stdErrFormatted"
                    } else {
                        Write-Verbose "No ERROR output available from script!"
                    }
                } else {
                    if($extStatusVal -eq "Error") {
                        Write-Error "Error status in custom script extension detected, stopping!!"
                        $completed = $true
                        $completedWithErrors = $true
                    }
                }
            } else {
                Write-Verbose -Message "Command not done, yet, continue waiting..."
                $waitAttempts += 1
            }
        } catch {
            Write-Warning "Failed retrieving custom VM Extension status. This typically indicates that the Custom Script Extension is not enabled on the VM."
        }

        # Wait before querying next time
        if(-not $completed) {
            Write-Verbose -Message "Waiting for $WaitIntervalInSec seconds..."
            Start-Sleep $WaitIntervalInSec
        }
    }while(($waitAttempts -le $WaitMaxAttempts) -and (-not $completed))

    # Check if the maximum number of wait times is reached. If so, throw an Error
    if((-not $completed) -and ($waitAttempts -ge $WaitMaxAttempts)) {
        Write-Error "Waiting for custom script extension did time-out. Assuming that custom script extension hangs or did not complete, successfully!"
        return "TimeOut"
    } else {
        if($completedWithErrors) {
            return "CompletedWithErrors"
        } else {
            if($completed) {
                return "CompletedSuccessfully"
                } else {
                    Write-Error "Custom script extension did not complete but terminated before retry count was exceeded!"
                    return "NotCompletedUnknown"
                }
        }
    }
}
