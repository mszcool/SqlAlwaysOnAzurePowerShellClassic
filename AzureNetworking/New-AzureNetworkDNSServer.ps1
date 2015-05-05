function New-AzureNetworkDNSServer {
    <#
        .SYNOPSIS
            Add a new DNS server to your network configuration

        .DESCRIPTION
            Add a new DNS server to your network configuration

        .PARAMETER Name
            Name of the DNS Server

        .PARAMETER IPAddress
            IPAddress for the new DNS Server

        .EXAMPLE
            New-AzureNetworkDNSServer -Name "MyDNS" - IPAddress "10.0.0.4"

        .NOTES
            Author: Anders Eide
            Blog: http://anderseideblog.wordpress.com/
            Twitter: @anderseide
		
        .LINK
            http://gallery.technet.microsoft.com/Azure-Networking-e52cbf92

    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param(
        [Parameter(Mandatory=$true,HelpMessage="Name of your new DNS server")]
        [ValidateNotNullOrEmpty()]
        [string] $Name,
        [Parameter(Mandatory=$true,HelpMessage="IP Address of your new DNS server")]
        [ValidateNotNullOrEmpty()]
        [string] $IPAddress
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
        #Get the config node containing DNS servers
        Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Locaing the DNS server configuration"
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

        # Add DNS server to config
        Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Adding DNS server to config"
        $newDNSServer = $AzureVNetConfig.CreateElement("DnsServer","http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration")
        $newDNSServer.SetAttribute("name",$Name)
        $newDNSServer.SetAttribute("IPAddress",$IPAddress)
        $DNSConfig = $DNSServersConfig.AppendChild($newDNSServer)
        
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
                Set-AzureVNetConfig -ConfigurationPath $TempAzureNetcfgFile -ErrorAction Stop
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Upload prosess finished"
            }
            catch [Exception] {
                # If any error, stop running and show the error
                Write-Error -Message $_.Exception.Message -ErrorAction Stop
            }
        }
    }
}
