function Set-AzureLocalNetwork {
    <#
        .SYNOPSIS
        Use this function to set new configuration details on a Local Network

        .DESCRIPTION
        Use this function to set new configuration details on a Local Network

        .PARAMETER Name
        Name of the Local Network to update

        .PARAMETER VPNGatewayAddress
        IP Address for the Local Network VPN Gateawey

        .PARAMETER addAddressSpace
        Single string or list of IP subnets to add to a local network

        .PARAMETER removeAddressSpace
        Single string or list of IP subnets to remove from a local network

        .EXAMPLE
        Set-AzureLocalNetwork -Name "MyNetwork" -IPAddress "123.123.123.123"

        .EXAMPLE
        Set-AzureLocalNetwork -Name "MyNetwork" -addAddressSpace "192.168.0.0/24","192.168.1.0/24"

        .EXAMPLE
        Set-AzureLocalNetwork -Name "MyNetwork" -removeAddressSpace "192.168.0.0/24","192.168.1.0/24"

        .NOTES
            Author: Anders Eide
            Blog: http://anderseideblog.wordpress.com/
            Twitter: @anderseide
		
        .LINK
            http://gallery.technet.microsoft.com/Azure-Networking-e52cbf92

    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
    [Parameter(Mandatory=$true,HelpMessage="Name of the local network to manage")]
    [string]
    $Name,
    [Parameter(Mandatory=$false,HelpMessage="IP Address to your VPN gateway")]
    [string]
    $VPNGatewayAddress,
    [Parameter(Mandatory=$false,HelpMessage="IP subnet prefix for the Address Space you want to add")]
    [string[]] $addAddressSpace,
    [Parameter(Mandatory=$false,HelpMessage="IP subnet prefix for the Address Space you want to add")]
    [string[]] $removeAddressSpace
    )

    Begin {
        try {
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Getting current VNet config"
            # Run Get-AzureVNetConfig and store to ActiveAzureVNetConfig variable
            $ActiveAzureVNetConfig = Get-AzureVNetConfig
            [xml]$AzureVNetConfig = $ActiveAzureVNetConfig.XMLConfiguration

        }
        catch [Exception] {
            # If any error, stop running, and show the error message
            Write-Error -Message $_.Exception.Message -ErrorAction Stop
        }
    }
    Process {
        # Get network site
        Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Locating the local network to manage"
        $LocalNetworkSite = $AzureVNetConfig.GetElementsByTagName("LocalNetworkSite") | ? {$_.name -eq $Name}
        # Check if VPNGatewayAddress object exists
        if ($VPNGatewayAddress) {
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Updating VPN Gateway IP Address"
            if (($LocalNetworkSite.VPNGatewayAddress) -eq $null) {
                # Does not exists. Create it and apply the VPNGateawyAddress
                $newVPNGatewayAddressConfig = $AzureVNetConfig.CreateElement("VPNGatewayAddress","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $newVPNGatewayAddressConfig.InnerText = $VPNGatewayAddress
                $VPNGatewayAddressConfig = $LocalNetworkSite.AppendChild($newVPNGatewayAddressConfig)
            } else {
                # It exists, so just update the VPNGatewayAddress
                $LocalNetworkSite.VPNGatewayAddress = $VPNGatewayAddress
            }
        }

        if ($removeAddressSpace) {
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removing Local Network address space"
            foreach ($AddressSpace in $removeAddressSpace) {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Remove Local Network Address Space with prefix $AddressSpace"
                $LocalSubnetsToKeep = $LocalNetworkSite.AddressSpace.AddressPrefix | ? {$_ -ne $AddressSpace}

                # Select the address space, and remove all child nodes
                $LocalNetworkAddressSpace = $LocalNetworkSite.AddressSpace
                $LocalNetworkAddressSpace.RemoveAll()

                # For each local subnet to keep, add them back to the address space
                foreach ($LocalSubnet in $LocalSubnetsToKeep) {
                    $newSubnet = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $newSubnet.InnerText=$LocalSubnet
                    $newSubnetConfig = $LocalNetworkAddressSpace.AppendChild($newSubnet)
                }
            }
        }

        if ($addAddressSpace) {
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding Local Network address space"
            foreach ($subnet in $addAddressSpace) {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Creating Local Network Address Space with prefix $subnet"
                $NewAddressPrefix = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewAddressPrefix.InnerText = $subnet
                $updatedVNetConfig = $LocalNetworkSite.AddressSpace.AppendChild($NewAddressPrefix)
            }
        }
    }
    End {
        # Store configuration back to Azure
        if ($PSCmdlet.ShouldProcess("Network Configuration", "Upload")) {
            try {
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
            catch [Exception] {
                # If any error, stop running and show the error
                Write-Error -Message $_.Exception.Message -ErrorAction Stop
            }
        }
    }

}
