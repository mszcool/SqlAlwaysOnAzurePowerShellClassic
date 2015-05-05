
function New-AzureVirtualNetwork {
    <#
        .SYNOPSIS
            Create a new Azure Virtual Network

        .DESCRIPTION
            Create a new Azure Virtual Network
    
        .PARAMETER VNetName
            The name of your new network. Example: MyNewNetwork. No space or number at the begining

        .PARAMETER Location
            The Location of your new network. Example: North Europe

        .PARAMETER AddressSpace
            The Address Space of your new network. Example: 192.168.0.0/20

        .PARAMETER Subnets
            An Array containging a Hash table of your subnets. Example: @(@{Name="FrontEnd";Prefix="192.168.2.0/24"},@{Name="BackEnd";Prefix="192.168.3.0/24"})
        
        .PARAMETER .addDNSServer
            Adds an existing DNS server to the network

        .PARAMETER newDNSServerConfig
            A Hash table with new DNS server settings. @{Name="MyDNS";IPAddress="10.0.0.4"}

        .PARAMETER EnableP2S
            Enables Point-To-Site VPN on the network

        .PARAMETER P2SAddressSpace
            The address space used by client connecting to the site

        .PARAMETER EnableS2S
            Enables Site-To-Site VPN on the network

        .PARAMETER addLocalNetwork
            List of names of the local networks to use with your network

        .PARAMETER GatewaySubnet
            Subnet to be used as Gateway Subnet

        .EXAMPLE
            New-AzureVirtualNetwork -Name "MyNewNetwork" -Location "North Europe" -AddressSpace "192.168.2.0/23" -Subnets @(@{Name="FrontEnd";Prefix="192.168.2.0/24"},@{Name="BackEnd";Prefix="192.168.3.0/24"})

        .EXAMPLE
            New-AzureVirtualNetwork -VNetName "MyAwesomeVNet" -Location "North Europe" -AddressSpaces "192.168.0.0/23" -Subnets @{Name="Subnet";Prefix="192.168.0.1/24"} -addDNSServer "DNS" -newDNSServerConfig @{Name="DNS3";IPAddress="192.168.0.6"} -EnableP2S -P2SAddressSpace "172.17.0.0/24" -EnableS2S -addLocalNetwork "MyNetwork","TestLocalNetwork" -GatewaySubnet "192.168.1.0/27"

        .NOTES
            Author: Anders Eide
            Blog: http://anderseideblog.wordpress.com/
            Twitter: @anderseide

            # Todo
                - Add logic for adding the subnet automatically if not supplied by the user
                - Add logic for creating the VPN gateawysubnet autoamtically if not supplier by the user
		
        .LINK
            http://gallery.technet.microsoft.com/Azure-Networking-e52cbf92


    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true,
            HelpMessage="Name of your new network. Can not start with number or white space")]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(2,63)]
        [ValidatePattern('^[a-zA-Z]\S')]
        [string] $VNetName,

        [Parameter(Mandatory=$true,
            HelpMessage="Location of your new network")]
        [ValidateNotNullOrEmpty()]
        [string] $Location,
        
        [Parameter(Mandatory=$true,
            HelpMessage="Address Space of your new network")]
        [ValidateNotNullOrEmpty()]
        [string[]] $AddressSpaces,
        
        [Parameter(Mandatory=$true,
            HelpMessage="Array with an Hash table of your subnets")]
        [ValidateNotNullOrEmpty()]
        [array[]]$Subnets,
        
        [Parameter(Mandatory=$false,
            HelpMessage="List of DNS server to connect with your nettwork")]
        [string[]] $addDNSServer,
        
        [Parameter(Mandatory=$false,
            HelpMessage="Hash table of your new DNS Server")]
        [array[]] $newDNSServerConfig,
        
        # Parameter EnableP2S
        [Parameter(Mandatory=$false,
            HelpMEssage="Enable or Disable Point-To-Site VPN")]
        [switch] $EnableP2S,

        # Parameter P2SAddressSpace
        [Parameter(Mandatory=$false,
            HelpMessage="Define the address space for VPN clients")]
        [string[]] $P2SAddressSpace,

        # Parameter EnableS2S
        [Parameter(Mandatory=$false,
            HelpMessage="Enable or Disable Site-To-Site VPN")]
        [switch] $EnableS2S,

        # Parameter addLocalNetwork
        [Parameter(Mandatory=$false,
            HelpMessage="List of names of the local networks you want to connect")]
        [string[]] $addLocalNetwork,

        # Parameter GatewaySubnet
        [Parameter(Mandatory=$false,
            HelpMessage="Subnet to be used as GatewaySubnet")]
        [string] $GatewaySubnet

    )
    Begin {
        # Get current network configuration
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

        if (($EnableP2S) -and ($EnableExpressRoute)) {
            Write-Error -Message "You cannot enable both Point-To-Site and ExpressRoute on the same network" -ErrorAction Stop
        }
        if (($EnableS2S) -and (-not $addLocalNetwork)) {
            Write-Error "Site-To-Site VPN requires a Local Network. Please set it using -LocalNetwork" -ErrorAction Stop
        }
    }
    Process {
        # Get network sites
        $AzureVNetSitesConfig = $AzureVNetConfig.GetElementsByTagName("VirtualNetworkSites")[0]
        if($AzureVNetSitesConfig -eq $null) {
            Write-Verbose "No VirtualNetworkSites defined, creating root element..."
            $AzureVNetSitesConfig = $AzureVnetConfig.CreateElement("VirtualNetworkSites", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $vnetRoot.AppendChild($AzureVNetSitesConfig)
        }

        # Check if the virtual network site does exist, already
        $vnetSiteExists = $false
        $vnetSitesExistingAlready = $AzureVnetConfig.GetElementsByTagName("VirtualNetworkSite")
        foreach($existingSite in $vnetSitesExistingAlready) {
            $existingSiteName =  $existingSite.GetAttribute("name")
            if($existingSiteName -eq $VNetName) {
                $vnetSiteExists = $true
            }
        }

        if($vnetSiteExists) {
            Write-Warning "Skipping creation of VNET since VNET $VNetName exists, already!"
        } else {
            # If P2S or S2S is enabled, a gateway subnet is needed
            if ($EnableP2S -or $EnableS2S) {
                if (-not $GatewaySubnet) {
                    if (-not $VirtualNetworkToManage.Gateway) {
                        Write-Error "A gateway subnet is required the first time a VPN config is created" -ErrorAction Stop
                    }
                }
            }

            # Create new network site
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding the new network"
            $NewVitualNetwork = $AzureVNetConfig.CreateElement("VirtualNetworkSite","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $NewVitualNetwork.SetAttribute("name",$VNetName)
            $NewVitualNetwork.SetAttribute("Location",$Location)
            $NetworkConfig = $AzureVNetSitesConfig.AppendChild($NewVitualNetwork)


            # Create new Address Space
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding the new Address Space"
            $NewAddressSpace = $AzureVNetConfig.CreateElement("AddressSpace","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $AddressSpaceConfig = $NetworkConfig.appendchild($NewAddressSpace)

            foreach ($AddressSpace in $AddressSpaces) {
                $NewAddressPrefix = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewAddressPrefix.InnerText=$AddressSpace
                $AddressSpaceConfig.AppendChild($NewAddressPrefix)
            }

            #
            # Add subnetes
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding the new subnets"
            $NewSubnets = $AzureVNetConfig.CreateElement("Subnets","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            $SubnetsConfig = $NetworkConfig.appendchild($NewSubnets)

            foreach ($Subnet in $Subnets) {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding subnet $($Subnet.Name)"
                $NewSubnet = $AzureVNetConfig.CreateElement("Subnet","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewSubnet.SetAttribute("name",$Subnet.Name)
                $SubnetConfig = $SubnetsConfig.AppendChild($NewSubnet)
                $NewAddressPrefix = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewAddressPrefix.InnerText=$Subnet.Prefix
                $SubnetConfig.AppendChild($NewAddressPrefix)

            }

            # Enable Point-To-Site
            if ($EnableP2S) {
                if (-not $P2SAddressSpace) {
                    Write-Error "P2SAddressSpace is required when you enable Point-To-Site VPN" -ErrorAction Stop
                }
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Enabling Point-To-Site VPN on network"
                # If $EnableP2S is set to $true, check that the Gateway Node exist, and then add a VPNClientAddressPool
                if (($NetworkConfig.Gateway) -eq $null) {
                    # If Gateway node does not exist, create it
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Gateway config node missing. Creating, and select for management"
                    $NewGatewayConfig = $AzureVNetConfig.CreateElement("Gateway","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $GatewayConfigNode = $NewVitualNetwork.appendchild($NewGatewayConfig)
                } else {
                    # Else, get the gateway config node
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Gateway config node found. Select for management"
                    $GatewayConfigNode = $NewVitualNetwork.Gateway
                }
                
                # Create the VPNClientAddressPool node
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding new Point-To-Site config, and adding it configuration"
                $NewP2SConfig = $AzureVNetConfig.CreateElement("VPNClientAddressPool","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                # Test if a ConnectionsToLocalNetowrk Exist
                if (($GatewayConfigNode.ConnectionsToLocalNetwork) -ne $null) {
                    # If it exist, insert the Client-To-Site config node before this element
                    # Unless the XML Schema will not validate
                    $GatewayConfigNode.InsertBefore($NewP2SConfig,$GatewayConfigNode.ConnectionsToLocalNetwork)
                } else {
                    # If it does not exist, just simple append it
                    $GatewayConfigNode.AppendChild($NewP2SConfig)
                }

                # Add prefixes.
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding Address Prefixes for the Point-To-Site VPN configuration"
                foreach ($AddrPrefix in $P2SAddressSpace) {
                    $NewP2SConfigAddressPrefix = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $NewP2SConfigAddressPrefix.InnerText=$AddrPrefix
                    $NewP2SConfig.AppendChild($NewP2SConfigAddressPrefix)
                }
            }

            # Enable Site-To-Site
            if ($EnableS2S) {
                
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Enabling Site-To-Site VPN on network"
                # Check that Gateway config node exist
                if (($NewVitualNetwork.Gateway) -eq $null) {
                    # If Gateway node does not exist, create it
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Gateway config node does not exists. Creating it"
                    $NewGatewayConfig = $AzureVNetConfig.CreateElement("Gateway","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $GatewayConfigNode = $NewVitualNetwork.appendchild($NewGatewayConfig)
                } else {
                    # Else, get the gateway config node
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Selecting the gateway config node"
                    $GatewayConfigNode = $NewVitualNetwork.Gateway
                }

                # Create the ConnectionsToLocalNetowrk node
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Creating the ConnectionsToLocalNetwork node"
                $NewLocalConnectionsNode = $AzureVNetConfig.CreateElement("ConnectionsToLocalNetwork","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $LocalConnectionsNode = $GatewayConfigNode.AppendChild($NewLocalConnectionsNode)

                # Create a Local Network Site Ref
                foreach ($LocalNet in $addLocalNetwork) {
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Creating the LocalNetworkSiteRef node for $LocalNet"
                    $NewLocalNetworkSiteRef = $AzureVNetConfig.CreateElement("LocalNetworkSiteRef","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $NewLocalNetworkSiteRef.SetAttribute("name",$LocalNet)
                    $LocalNetworkSiteRef = $LocalConnectionsNode.AppendChild($NewLocalNetworkSiteRef)
                }

                # Create GatewaySubnet
                $VNetToManageSubnets = $NewVitualNetwork.Subnets
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Creating GatewaySubnet"
                $NewSubnet = $AzureVNetConfig.CreateElement("Subnet","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewSubnet.SetAttribute("name","GatewaySubnet")
                $subnetConfig = $VNetToManageSubnets.AppendChild($NewSubnet)

                $NewAddressPrefix = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewAddressPrefix.InnerText=$GatewaySubnet
                $SubnetConfig.AppendChild($NewAddressPrefix)

            }


            # Add existing DNS Server
            if ($addDNSServer) {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding existing DNS Server"
                # Check that DNSServerRef node exists. If not, create it
                if (($NewVitualNetwork.DnsServersRef) -eq $null) {
                    $NewDNSServersRef = $AzureVNetConfig.CreateElement("DnsServersRef","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $DNSServersRef = $NewVitualNetwork.appendchild($NewDNSServersRef)
                } else {
                    $DNSServersRef = $NewVitualNetwork.DnsServersRef
                }

                # Add all DNS Servers referenced
                # Add logic that test if the "existing" DNS reference exists
                foreach ($DNSServer in $addDNSServer) {
                    $NewDNSServer = $AzureVNetConfig.CreateElement("DnsServerRef","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $NewDNSServer.SetAttribute("name",$DNSServer)
                    $DNSServersRef.AppendChild($NewDNSServer)
                }
            }

            # Add new DNS server
            if ($newDNSServerConfig) {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding new DNS server"
                # Get DNS servers configg
                $DNSServersConfig = $AzureVNetConfig.GetElementsByTagName("DnsServers")[0]
                if($DNSServersConfig -eq $null) {
                    $DNSConfig = $AzureVNetConfig.GetElementsByTagName("Dns")[0]
                    if($DNSConfig -eq $null) {
                        $DNSConfig = $AzureVnetConfig.CreateElement("Dns", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                        $vnetRoot.AppendChild($DNSConfig)
                    }
                    $DNSServersConfig = $AzureVNetConfig.CreateElement("DnsServers", "http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $DNSConfig.AppendChild($DNSServersConfig)
                }

                foreach ($DNSServer in $newDNSServerConfig) {
                    $dnsServerExists = $false
                    $dnsServerExisting = $AzureVNetConfig.GetElementsByTagName("DnsServer")
                    foreach($dnsExisting in $dnsServerExisting) {
                        $dnsServerName = $dnsExisting.GetAttribute("name")
                        if($dnsServerName -eq $DNSServer.Name) {
                            $dnsServerExists = $true
                        }
                    }
                    if(-not $dnsServerExists) {
                        $newDNSServer = $AzureVNetConfig.CreateElement("DnsServer","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                        $newDNSServer.SetAttribute("name",$DNSServer.Name)
                        $newDNSServer.SetAttribute("IPAddress",$DNSServer.IPAddress)
                        $DNSConfig = $DNSServersConfig.AppendChild($newDNSServer)
                    }
                }
                if (($NewVitualNetwork.DnsServersRef) -eq $null) {
                    $NewDNSServersRef = $AzureVNetConfig.CreateElement("DnsServersRef","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $DNSServersRef = $NewVitualNetwork.appendchild($NewDNSServersRef)
                } else {
                    $DNSServersRef = $NewVitualNetwork.DnsServersRef
                }

                foreach ($DNSServer in $newDNSServerConfig) {
                    $NewDNSServer = $AzureVNetConfig.CreateElement("DnsServerRef","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $NewDNSServer.SetAttribute("name",$DNSServer.Name)
                    $DNSServersRef.AppendChild($NewDNSServer)
                }
            } # End of NewDNS block
        }
    }
    End {
        # Store configuration back to Azure
        if ($PSCmdlet.ShouldProcess("Network Configuration", "Upload")) {
            try {
                if(-not $vnetSiteExists) {                
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
