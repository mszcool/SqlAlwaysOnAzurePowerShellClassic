function Get-IPrange { 
    <#  
        .SYNOPSIS   
            Get the IP addresses in a range  
        .EXAMPLE  
            Get-IPrange -start 192.168.8.2 -end 192.168.8.20  
        .EXAMPLE  
            Get-IPrange -ip 192.168.8.2 -mask 255.255.255.0  
        .EXAMPLE  
            Get-IPrange -ip 192.168.8.3 -cidr 24

        .LINK
            http://gallery.technet.microsoft.com/scriptcenter/List-the-IP-addresses-in-a-60c5bb6b
    #>  
  
    param  
    (  
      [string]$start,  
      [string]$end,  
      [string]$ip,  
      [string]$mask,  
      [int]$cidr  
    )  
  
    function IP-toINT64 () {  
      param ($ip)  
  
      $octets = $ip.split(".")  
      return [int64]([int64]$octets[0]*16777216 +[int64]$octets[1]*65536 +[int64]$octets[2]*256 +[int64]$octets[3])  
    }  
  
    function INT64-toIP() {  
      param ([int64]$int)  
 
      return (([math]::truncate($int/16777216)).tostring()+"."+([math]::truncate(($int%16777216)/65536)).tostring()+"."+([math]::truncate(($int%65536)/256)).tostring()+"."+([math]::truncate($int%256)).tostring() ) 
    }  
  
    if ($ip) {$ipaddr = [Net.IPAddress]::Parse($ip)}  
    if ($cidr) {$maskaddr = [Net.IPAddress]::Parse((INT64-toIP -int ([convert]::ToInt64(("1"*$cidr+"0"*(32-$cidr)),2)))) }  
    if ($mask) {$maskaddr = [Net.IPAddress]::Parse($mask)}  
    if ($ip) {$networkaddr = new-object net.ipaddress ($maskaddr.address -band $ipaddr.address)}  
    if ($ip) {$broadcastaddr = new-object net.ipaddress (([system.net.ipaddress]::parse("255.255.255.255").address -bxor $maskaddr.address -bor $networkaddr.address))}  
  
    if ($ip) {  
      $startaddr = IP-toINT64 -ip $networkaddr.ipaddresstostring  
      $endaddr = IP-toINT64 -ip $broadcastaddr.ipaddresstostring  
    } else {  
      $startaddr = IP-toINT64 -ip $start  
      $endaddr = IP-toINT64 -ip $end  
    }  
  
  
    for ($i = $startaddr; $i -le $endaddr; $i++)  
    {  
      INT64-toIP -int $i  
    } 
 
}

function MatchSubnetToPrefix {
    <#
        .SYNOPSIS
            This function matches a given subnet to a prefix

        .DESCRIPTION
            This function matches a given subnet to a prefix. It uses the Get-IPrange function written by Barry Chum
            http://gallery.technet.microsoft.com/scriptcenter/List-the-IP-addresses-in-a-60c5bb6b

        .EXAMPLE
            MatchSubnetToPrefix -Subnet "192.168.2.0/24" -Prefix "192.168.0.0/23"
        
            This example will return False

        .EXAMPLE
            MatchSubnetToPrefix -Subnet "192.168.1.0/24" -Prefix "192.168.0.0/23"
        
            This example will return True
    #>
    param (
        [string] $prefix,
        [string] $subnet
    )

    $prefixT = $prefix.Split("/")
    $subnetT = $subnet.Split("/")

    $IPRangePrefix = Get-IPrange -ip $prefixT[0] -cidr $prefixT[1]
    $IPRangeSubnet = Get-IPrange -ip $subnetT[0] -cidr $subnetT[1]

    foreach ($IP in $IPRangeSubnet) {
        if ($IPRangePrefix.Contains($IP)) {
            $IPMatch = $true
        } else {
            $IPMatch = $false
        }
    }
    return $IPMatch
}

function Set-AzureVirtualNetwork {
    <#
        .SYNOPSIS
            Use this Cmdlet to set different settings on your Azure Virtual Network

        .DESCRIPTION
            Use this Cmdlet to set different settings on your Azure Virtual Network

        .PARAMETER VNetName
            Name of the virtual network you want to manage

        .PARAMETER addDNSServer
            Adds a existing DNS server to a network
            -addDNSServer "MyDNSServer"

        .PARAMETER newDNSServerConfig
            Adds a new DNS server to a network
            -newDNSServerConfig @{Name="MyDNSServer";IPAddress="192.168.0.4"}

        .PARAMETER removeDNSServer
            Removes a DNS server from a network
            -removeDNSServer "MyDNSSserver"

        .PARAMETER addAddressSpace
            Adds a AddressSpace to a network
            -addAddressSpace "192.168.1.0/24"

        .PARAMETER addSubnet
            An Array containging a Hash table of your subnets. 
            -addSubnet @(@{Name="FrontEnd";Prefix="192.168.2.0/24"},@{Name="BackEnd";Prefix="192.168.3.0/24"})
    
        .PARAMETER removeSubnet
            Removes a subnet by name
            -removeSubnet "MySubnet"
        
        .PARAMETER EnableP2S
            This parameter enables or disables Point-To-Site connectivity for your network
            Accepts True or False

        .PARAMETER P2SAddresSpace
            Address Space for user local clients

        .PARAMETER DisableP2S
            Disables (removes) the Point-To-Site configuration form a network

        .PARAMETER EnableS2S
            This parameter enables or disables Site-To-Site connectivity for your network
            Accepts True or False

        .PARAMETER DisableS2S
            Disables (removes) the Site-To-Site configuration from a network

        .PARAMETER removeLocalNetwork
            Name of local network to remove

        .PARAMETER addLocalNetwork
            Set the name that reference the local network you want to use
            Alias: LocalNetwork

        .PARAMETER GatewaySubnet
            Subnet to be used as GatewaySubnet.

        .NOTES
            Author: Anders Eide
            Blog: http://anderseideblog.wordpress.com/
            Twitter: @anderseide

        .LINK
            http://gallery.technet.microsoft.com/Azure-Networking-e52cbf92

    #>
    # Examples
    <#
        .EXAMPLE
            Set-AzureVirtualNetwork -VNetName "MyNetwork" -EnableP2S $true -P2SAddressSpace "192.168.0.0/24" -GatewaySubnet "192.168.1.0/29"

        .EXAMPLE 
            Set-AzureVirtualNetwork -VNetName "MyNetwork" -EnableS2S $true -addLocalNetwork "MyLocalNetwork" -GatewaySubnet "192.168.1.0/29"

        .EXAMPLE 
            Set-AzureVirtualNetwork -VNetName "MyNetwork" -EnableS2S $false

        .EXAMPLE 
            Set-AzureVirtualNetwork -VNetName "MyNetwork" -EnableP2S $false

        .EXAMPLE
            Set-AzureVirtualNetwork -VNetName "MyNetwork" -addDNSServer "MyDns"

        .EXAMPLE
            Set-AzureVirtualNetwork -VNetName "MyNetwork" -removeDNSServer "MyDns"

        .EXAMPLE
            Set-AzureVirtualNetwork -VNetName "MyNetwork" -newDNSServerConfig @{Name="MyVPNDns";IPAddress="192.168.5.6"}

        .EXAMPLE
            Set-AzureVirtualNetwork -VNetName "MyNetwork" -EnableS2S -addLocalNetwork "MySecondSite"

        .EXAMPLE
            Set-AzureVirtualNetwork -VNetName "MyNetwork" -DisableS2S -removeLocalNetwork "MySecondSite"


    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        # Parameter VNetName
        [Parameter(Position=0,
            Mandatory=$true,
            HelpMessage="Name of the virtual network you want to manage")]
        [string] $VNetName,

        # Parameter addDNSServer
        [Parameter(Mandatory=$false,
            HelpMessage="List of DNS server to connect with your nettwork")]
        [string[]] $addDNSServer,

        # Parameter newDNSServerConfig
        [Parameter(Mandatory=$false,
            HelpMessage="Hash table of your new DNS Server")]
        [array[]] $newDNSServerConfig,

        # Parameter removeDNSServer
        [Parameter(Mandatory=$false,
            HelpMessage="Removes a named DNS server from this network")]
        [string] $removeDNSServer,
        
        # Parameter addAddressSpace
        [Parameter(Mandatory=$false,
            HelpMessage="Add a new Address Space to a network")]
        [string[]] $addAddressSpace,

        # Parameter removeAddressSpace
        [Parameter(Mandatory=$false,
            HelpMessage="Remove a Address Space from a network. Also removes any subnets in the Address Space")]
        [string[]] $removeAddressSpace,

        # Parameter addSubnet
        [Parameter(Mandatory=$false,
            HelpMessage="Add a subnet to a Virtual Network")]
        [array[]] $addSubnet,

        # Parameter removeSubnet
        [Parameter(Mandatory=$false,
            HelpMessage="Remove a subnet from a Virtual Network by Name.'")]
        [string[]] $removeSubnet,

        # Parameter EnableP2S
        [Parameter(Mandatory=$false,
            HelpMEssage="Enable or Disable Point-To-Site VPN")]
        [switch] $EnableP2S,

        # Parameter DisableP2S
        [Parameter(Mandatory=$false,
            HelpMEssage="Enable or Disable Point-To-Site VPN")]
        [switch] $DisableP2S,

        # Parameter P2SAddressSpace
        [Parameter(Mandatory=$false,
            HelpMessage="Define the address space for VPN clients")]
        [string[]] $P2SAddressSpace,

        # Parameter EnableS2S
        [Parameter(Mandatory=$false,
            HelpMessage="Enable or Disable Site-To-Site VPN")]
        [switch] $EnableS2S,

        # Parameter DisableS2S
        [Parameter(Mandatory=$false,
            HelpMessage="Enable or Disable Site-To-Site VPN")]
        [switch] $DisableS2S,

        # Parameter removeLocalNetwork
        [Parameter(Mandatory=$false,
            HelpMessage="Name of the local networks you want to remove")]
        [string[]] $removeLocalNetwork,

        # Parameter addLocalNetwork
        [Parameter(Mandatory=$false,
            HelpMessage="Name of the local networks you want to add")]
        [Alias("LocalNetwork")]
        [string[]] $addLocalNetwork,

        # Parameter GatewaySubnet
        [Parameter(Mandatory=$false,
            HelpMessage="Subnet to be used as GatewaySubnet")]
        [string] $GatewaySubnet

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
        # Get the configuration node for the Virtual Network
        $VirtualNetworkToManage = $AzureVNetConfig.GetElementsByTagName("VirtualNetworkSite") | ? {$_.name -eq $VNetName}
        # $VirtualNetworkToManage = $AzureVNetConfig.GetElementsByTagName("VirtualNetworkSite") | ? {$_.name -eq "MyAwesomeVNet"}
        if ($EnableP2S -or $EnableS2S) {
            if (-not $GatewaySubnet) {
                if (-not $VirtualNetworkToManage.Gateway) {
                    Write-Error "A gateway subnet is required the first time a VPN config is created" -ErrorAction Stop
                }
            }
        }

        # Disable Point-To-Site
        if ($DisableP2S) {
            # Bug: Gateway subnet not removed when this is the latest VPN configuration
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Point-To-Site is set to false. Removing config"
            # If $EnableP2S is set to $false, remove the Point-To-Site configuration if any
            if ($VirtualNetworkToManage.Gateway.VPNClientAddressPool -ne $null) {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removing VPNClientAddressPool"
                $VirtualNetworkToManage.Gateway.RemoveChild($VirtualNetworkToManage.Gateway.VPNClientAddressPool)
            }
            # For some reason, ConnectionsToLocalNetwork element is a String when not containing any configuration, and P2S is enabled.
            if ($VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork.GetType().FullName -eq "System.String") {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - There is no more VPN configuration in this network. Checking for and removing any GatewaySubnet"
                $GatewaySubnetConfig = $VirtualNetworkToManage.Subnets.Subnet | ? {$_.name -eq "GatewaySubnet"}
                if ($GatewaySubnetConfig -ne $null) {
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removing GatewaySubnet from the virtual network"
                    $VirtualNetworkToManage.Subnets.RemoveChild($GatewaySubnetConfig)
                }
            }            
        }

        # Enable Point-To-Site
        if ($EnableP2S) {
            if (-not $P2SAddressSpace) {
                Write-Error "P2SAddressSpace is required when you enable Point-To-Site VPN" -ErrorAction Stop
            }

            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Enabling Point-To-Site VPN on network"
            # If $EnableP2S is set to $true, check that the Gateway Node exist, and then add a VPNClientAddressPool
            if (($VirtualNetworkToManage.Gateway) -eq $null) {
                # If Gateway node does not exist, create it
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Gateway config node missing. Creating, and select for management"
                $NewGatewayConfig = $AzureVNetConfig.CreateElement("Gateway","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $GatewayConfigNode = $VirtualNetworkToManage.appendchild($NewGatewayConfig)
            } else {
                # Else, get the gateway config node
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Gateway config node found. Select for management"
                $GatewayConfigNode = $VirtualNetworkToManage.Gateway
            }
            
            # Create the VPNClientAddressPool node
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding new Point-To-Site config, and adding it configuration"
            $NewP2SConfig = $AzureVNetConfig.CreateElement("VPNClientAddressPool","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
            # Test if a ConnectionsToLocalNetowrk Exist
            if (($GatewayConfigNode.ConnectionsToLocalNetwork) -ne $null) {
                # If it exist, insert the Client-To-Site config node before this element
                # Unless the XML Schema will not validate
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - ConnectionsToLocalNetwork already exists. Adding the P2S config before this" 
                $GatewayConfigNode.InsertBefore($NewP2SConfig,$GatewayConfigNode.ConnectionsToLocalNetwork)
            } else {
                # If it does not exist, just simple append it
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding the P2S config to the gateway settings" 
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

        # Disable Site-To-Site
        if ($DisableS2S) {
			# Remove local networks if given. If not, remove the whole config
			if ($removeLocalNetwork) {
				#$LocalConnectionsNode = $VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork
				Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removing local network from Site-To-Site configuration"
				foreach ($LocalNet in $removeLocalNetwork) {
					$VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork.RemoveChild(
						$($VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork.LocalNetworkSiteRef | ? {$_.name -eq $LocalNet})
					)
                    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removed local network $LocalNet from configuration"
                }
                ## $VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork is empty after this removal, test if the GatewaySubnet should be removed also
                if ($VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork.GetType().FullName -eq "System.String") {
					# Removig configuration for ConnectionsToLocalNetwork
					Write-Verbose "$(Get-Date -Format "HH:mm:ss") - There is no configuration for Site-To-Site. Testing if GatewaySubnet should be removed"
					$VirtualNetworkToManage.Gateway.RemoveChild($VirtualNetworkToManage.Gateway.Item("ConnectionsToLocalNetwork"))
                    if (($VirtualNetworkToManage.Gateway.HasChildNodes -eq $false) -or ($VirtualNetworkToManage.Gateway.HasChildNodes -eq $null)) {
					    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Last VPN config removed. Checking for any GatewaySubnet in the network"
					    $GatewaySubnetConfig = $VirtualNetworkToManage.Subnets.Subnet | ? {$_.name -eq "GatewaySubnet"}
					    if ($GatewaySubnetConfig -ne $null) {
						    Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removing GatewaySubnet from the virtual network"
						    $VirtualNetworkToManage.Subnets.RemoveChild($GatewaySubnetConfig)
					    }
				    }
				}
                
			} else {
				Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Site-To-Site is set to false. Removing config"
				# If $EnableS2S is set to $false, remove the Point-To-Site configuration if any
				if (($VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork) -ne $null) {
					# Removig configuration for ConnectionsToLocalNetwork
					Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removing configuration for ConnectionsToLocalNetwork"
					$VirtualNetworkToManage.Gateway.RemoveChild($VirtualNetworkToManage.Gateway.Item("ConnectionsToLocalNetwork"))
				}
				if (($VirtualNetworkToManage.Gateway.HasChildNodes -eq $false) -or ($VirtualNetworkToManage.Gateway.HasChildNodes -eq $null)) {
					Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Last VPN config removed. Checking for any GatewaySubnet in the network"
					$GatewaySubnetConfig = $VirtualNetworkToManage.Subnets.Subnet | ? {$_.name -eq "GatewaySubnet"}
					if ($GatewaySubnetConfig -ne $null) {
						Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removing GatewaySubnet from the virtual network"
						$VirtualNetworkToManage.Subnets.RemoveChild($GatewaySubnetConfig)
					}
				}
			}
        }
        
        # Enable Site-To-Site
        if ($EnableS2S) {
            if (-not $addLocalNetwork) {
                Write-Error "$(Get-Date -Format "HH:mm:ss") - Site-To-Site VPN requires a Local Network. Please set it using -addLocalNetwork" -ErrorAction Stop
            }
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Enabling Site-To-Site VPN on network"
            # Check that Gateway config node exist
            if (($VirtualNetworkToManage.Gateway) -eq $null) {
                # If Gateway node does not exist, create it
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Gateway config node does not exists. Creating it"
                $NewGatewayConfig = $AzureVNetConfig.CreateElement("Gateway","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $GatewayConfigNode = $VirtualNetworkToManage.appendchild($NewGatewayConfig)
            } else {
                # Else, get the gateway config node
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Selecting the gateway config node"
                $GatewayConfigNode = $VirtualNetworkToManage.Gateway
            }

            # Create a new Site-To-Site Local Network connection
            # Bug?: This test fails if P2S is enabled. ConnectionsToLocalNetwork is pressent, as string, when only P2S has been enabled.
            # Bug? Remove this sillyness if it's pressent
            if ($VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork) {
                if ($VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork.GetType().FullName -eq "System.String") {
                    $VirtualNetworkToManage.Gateway.RemoveChild($VirtualNetworkToManage.Gateway.Item("ConnectionsToLocalNetwork"))
                }
            }
            # Now, we should be ready to create a ConnectionsToLocalNetwork element if needed
            if ($VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork -eq $null) {
                # Create the ConnectionsToLocalNetwork node
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Creating the ConnectionsToLocalNetwork node"
                $NewLocalConnectionsNode = $AzureVNetConfig.CreateElement("ConnectionsToLocalNetwork","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $LocalConnectionsNode = $GatewayConfigNode.AppendChild($NewLocalConnectionsNode)
            } else {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - ConnectionsToLocalNetwork node exists. Selected"
                $LocalConnectionsNode = $VirtualNetworkToManage.Gateway.ConnectionsToLocalNetwork
            }

            # Create a Local Network Site Ref for each local network spesified
            foreach ($LocalNet in $addLocalNetwork) {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Creating the LocalNetworkSiteRef node"
                $NewLocalNetworkSiteRef = $AzureVNetConfig.CreateElement("LocalNetworkSiteRef","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewLocalNetworkSiteRef.SetAttribute("name",$LocalNet)
                $LocalNetworkSiteRef = $LocalConnectionsNode.AppendChild($NewLocalNetworkSiteRef)
            }

            if (($VirtualNetworkToManage.Subnets.Subnet | ? {$_.name -eq "GatewaySubnet"}) -eq $null) {
                # Create GatewaySubnet
                $VNetToManageSubnets = $VirtualNetworkToManage.Subnets
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Creating GatewaySubnet"
                $NewSubnet = $AzureVNetConfig.CreateElement("Subnet","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewSubnet.SetAttribute("name","GatewaySubnet")
                $subnetConfig = $VNetToManageSubnets.AppendChild($NewSubnet)

                $NewAddressPrefix = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewAddressPrefix.InnerText=$GatewaySubnet
                $SubnetConfig.AppendChild($NewAddressPrefix)
            }

        }

        # Remove DNS Server
        if ($removeDNSServer) {
            # Removes a named DNS server from the Virtual Network
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removing DNS server with name $removeDNSServer from configuration"
            $VirtualNetworkToManage.DnsServersRef.RemoveChild(
                $($VirtualNetworkToManage.DnsServersRef.DnsServerRef | ? {$_.name -eq $removeDNSServer}))
        }

        # Add existing DNS Server
        if ($addDNSServer) {
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding existing DNS Server"
            # Check that DNSServerRef node exists. If not, create it
            if (($VirtualNetworkToManage.DnsServersRef) -eq $null) {
                $NewDNSServersRef = $AzureVNetConfig.CreateElement("DnsServersRef","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $DNSServersRef = $VirtualNetworkToManage.appendchild($NewDNSServersRef)
            } else {
                $DNSServersRef = $VirtualNetworkToManage.DnsServersRef
            }

            # Add all DNS Servers referenced
            foreach ($DNSServer in $addDNSServer) {
                Write-Verbose -Message "$(Get-Date -Format "HH:mm:ss") - Adding DNS server with name $DNSServer"
                $NewDNSServer = $AzureVNetConfig.CreateElement("DnsServerRef","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewDNSServer.SetAttribute("name",$DNSServer)
                $DNSServersRef.AppendChild($NewDNSServer)
            }
        }

        # Create and then add a new DNS Server
        if ($newDNSServerConfig)  {
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding new DNS server"
            # Get DNS servers config
            $DNSServersConfig = $AzureVNetConfig.GetElementsByTagName("DnsServers")
            foreach ($DNSServer in $newDNSServerConfig) {
                $newDNSServer = $AzureVNetConfig.CreateElement("DnsServer","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $newDNSServer.SetAttribute("name",$DNSServer.Name)
                $newDNSServer.SetAttribute("IPAddress",$DNSServer.IPAddress)
                $DNSConfig = $DNSServersConfig.AppendChild($newDNSServer)
            }
            if (($VirtualNetworkToManage.DnsServersRef) -eq $null) {
                $NewDNSServersRef = $AzureVNetConfig.CreateElement("DnsServersRef","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $DNSServersRef = $VirtualNetworkToManage.appendchild($NewDNSServersRef)
            } else {
                $DNSServersRef = $VirtualNetworkToManage.DnsServersRef
            }

            foreach ($DNSServer in $newDNSServerConfig) {
                $NewDNSServer = $AzureVNetConfig.CreateElement("DnsServerRef","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewDNSServer.SetAttribute("name",$DNSServer.Name)
                $DNSServersRef.AppendChild($NewDNSServer)
            }
        } # End of NewDNS block
        
        # Remove Address Space. Also removes related subnets
        if ($removeAddressSpace) {
            foreach ($AddressSpace in $removeAddressSpace) {
                # Loop trough the subnets, and find all that matches this address space
                $Subnets = $VirtualNetworkToManage.Subnets.Subnet

                foreach ($Subnet in $Subnets) {
                    if ((MatchSubnetToPrefix -prefix $AddressSpace -subnet $Subnet.AddressPrefix) -eq $true) {
                        # Remove Subnet
                        $VirtualNetworkToManage.Subnets.RemoveChild(
                            $($VirtualNetworkToManage.Subnets.Subnet | ? {$_.name -eq $Subnet.name}))
                    }
                }

                # Then Remove AddressSpace prefix
                $AddressSpacesToKeep = $VirtualNetworkToManage.AddressSpace.AddressPrefix | ? {$_ -ne $AddressSpace}

                # Select the address space, and remove all child nodes
                $CurrentAddressSpace = $VirtualNetworkToManage.AddressSpace
                $CurrentAddressSpace.RemoveAll()

                # For each local subnet to keep, add them back to the address space
                foreach ($AddressSpaceKept in $AddressSpacesToKeep) {
                    $newAddressSpace = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                    $newAddressSpace.InnerText=$AddressSpaceKept
                    $newAddressSpaceConfig = $CurrentAddressSpace.AppendChild($newAddressSpace)
                }
            }
        }

        # Manage Address Spaces and subnets
        if ($addAddressSpace) {
            $AddressSpaceConfig = $VirtualNetworkToManage.AddressSpace
            foreach ($AddressSpace in $addAddressSpace) {
                $NewAddressPrefix = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewAddressPrefix.InnerText=$AddressSpace
                $AddressSpaceConfig.AppendChild($NewAddressPrefix)
            }
        }

        # Remove subnets
        if ($removeSubnet) {
            foreach ($SubnetName in $removeSubnet) {
                $VirtualNetworkToManage.Subnets.RemoveChild(
                    $($VirtualNetworkToManage.Subnets.Subnet | ? {$_.name -eq $SubnetName}))
            }
        }

        # Add subnets
        if ($addSubnet) {
            $SubnetsConfig = $VirtualNetworkToManage.Subnets
            foreach ($Subnet in $addSubnet) {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding subnet $Subnet.Name"
                $NewSubnet = $AzureVNetConfig.CreateElement("Subnet","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewSubnet.SetAttribute("name",$Subnet.Name)
                $SubnetConfig = $SubnetsConfig.AppendChild($NewSubnet)
                $NewAddressPrefix = $AzureVNetConfig.CreateElement("AddressPrefix","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
                $NewAddressPrefix.InnerText=$Subnet.Prefix
                $SubnetConfig.AppendChild($NewAddressPrefix)
            }
        }
    }
    End {
        # Store configuration back to Azure
        if ($PSCmdlet.ShouldProcess("Network Configuration","Upload")) {
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