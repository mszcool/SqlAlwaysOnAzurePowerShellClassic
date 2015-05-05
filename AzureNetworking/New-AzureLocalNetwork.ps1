function New-AzureLocalNetwork {
    <#
        .SYNOPSIS
            Creates a new Azure Local Network

        .DESCRIPTION
            Creates a new Local Network in Azure

        .PARAMETER Name
            Name of the new local network

        .PARAMETER VPNGatewayAddress
            IPAddress of the Local Networks VPN Gateway

        .PARAMETER addAddressSpaces
            List of address spaces to add

        .EXAMPLE
            New-AzureLocalNetwork -Name "MyNewLocalNetwork" -IPAddress "123.123.123.123" -addAddressSpaces "192.168.0.0/24"
        
        .EXAMPLE
            New-AzureLocalNetwork -Name "MyNewLocalNetwork" -addAddressSpaces "192.168.0.0/24","192.168.1.0/24"

        .NOTES
            Author: Anders Eide
            Blog: http://anderseideblog.wordpress.com/
            Twitter: @anderseide
		
        .LINK
            http://gallery.technet.microsoft.com/Azure-Networking-e52cbf92

        
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true,HelpMessage="Name of your local network")]
        [ValidateNotNullOrEmpty()]
        [string] $Name,
        [Parameter(Mandatory=$false,HelpMessage="VPN Gateway Address of your local network")]
        [string] $VPNGatewayAddress,
        [Parameter(Mandatory=$true,HelpMessage="List of your address spaces in your local network")]
        [ValidateNotNullOrEmpty()]
        [Alias("AddressSpaces")]
        [string[]]$addAddressSpace
    )
    Begin {
        try {
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Getting current VNet config"
            # Run Get-AzureVNetConfig and store to ActiveAzureVNetConfig variable
            $ActiveAzureVNetConfig = Get-AzureVNetConfig
            [xml]$AzureVNetConfig = $ActiveAzureVNetConfig.XMLConfiguration
            if($AzureVNetConfig -eq $null) {
                $AzureVnetConfig = [xml]"<NetworkConfiguration xmlns='http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration'><VirtualNetworkConfiguration /></NetworkConfiguration>"
            }
            $vnetRoot = $AzureVnetConfig.GetElementsByTagName("VirtualNetworkConfiguration")[0]
        }
        catch [Exception] {
            # If any error, stop running, and show the error message
            Write-Error -Message $_.Exception.Message -ErrorAction Stop
        }
    }
    Process {
        # Get network sites
        Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Locating the Local Networks Site config"
        $localNetConfig = $AzureVNetConfig.GetElementsByTagName("LocalNetworkSites")[0]
        if($localNetConfig -eq $null) {
            Write-Verbose "Local network configuration does not exist, creating it..."
            $localNetConfig = $AzureVnetConfig.CreateElement("LocalNetworkSites", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $vnetRoot.AppendChild($localNetConfig)
        }

        # Simple way to detect if local network exists, already
        $localNetworkExists = $false
        $localNetworkSitesInVnet = $AzureVnetConfig.GetElementsByTagName("LocalNetworkSite")
        foreach($existingSite in $localNetworkSitesInVnet) {
            $existingSiteName =  $existingSite.GetAttribute("name")
            if($existingSiteName -eq $Name) {
                $localNetworkExists = $true
            }
        }

        # Create the local network if it does not exist
        if($localNetworkExists -eq $true) {
            Write-Warning -Message "Local network with name $Name does exist, already! Skipping creation!"
        } else {
            # Create new network site
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding the new network"
            $newNetwork = $AzureVNetConfig.CreateElement("LocalNetworkSite","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $newNetwork.SetAttribute("name",$Name)
            $NetworkConfig = $localNetConfig.AppendChild($newNetwork)

            # Create new Address Space
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Preparing to add Address Spaces"
            $NewAddressSpace = $AzureVNetConfig.CreateElement("AddressSpace","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $AddressSpaceConfig = $NetworkConfig.appendchild($NewAddressSpace)

            # For each Address Space, add it
            foreach ($AddressSpace in $addAddressSpace) {
                # Creating AddressPrefix element
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding Address Space with subnet $AddressSpace"
                $NewAddressSpace = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewAddressSpace.InnerText=$AddressSpace
                $NewAddressSpaceConfig = $AddressSpaceConfig.AppendChild($NewAddressSpace)
            }

            # If VPNGatewayAddress is set, add it
            if ($VPNGatewayAddress) {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding VPN Gateway Address"
                $newVPNGatewayAddress = $AzureVNetConfig.CreateElement("VPNGatewayAddress","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $newVPNGatewayAddress.InnerText=$VPNGatewayAddress
                $VPNGatewayAddressConfig = $NetworkConfig.appendchild($newVPNGatewayAddress)
            }    
        }
    }
    End {
        # Store configuration back to Azure
        if ($PSCmdlet.ShouldProcess("Network Configuration", "Upload")) {
            try {
                if(-not $localNetworkExists) {
                    # Store configuration back to Azure
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Write XML configuration to temp file"
                    # Make a netcfg file in a tempfolder
                    $TempAzureNetcfgFile = $env:TEMP + "\AzureVNetConfig.netcfg"
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Temp file path is set to $TempAzureNetcfgFile"
                    $AzureVNetConfig.Save($TempAzureNetcfgFile)
        
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Uploading configuration to Azure"
                    # Upload to Azure using default Azure cmdlet
                    Set-AzureVNetConfig -ConfigurationPath $TempAzureNetcfgFile
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Upload prosess finished"
                }
            }
            catch [Exception] {
                # If any error, stop running and show the error
                Write-Error -Message $_.Exception.Message -ErrorAction Stop
            }
        }
    }
}
