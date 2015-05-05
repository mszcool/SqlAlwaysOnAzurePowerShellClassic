
function Remove-AzureNetworkDNSServer {
    <#
        .SYNOPSIS
            Removes a DNS Server from Azure Network Configuration

        .DESCRIPTION
            Removes a DNS server from Azure Network Configuration

        .PARAMETER Name
            The name of the DNS Server to remove

        .EXAMPLE
            Remove-AzureNetworkDNSServer -Name "MyDNS"

        .EXAMPLE
            Remove-AzureNetworkDNSServer -NAme "MyDNS","MyOtherDNS"

        .NOTES
            Author: Anders Eide
            Blog: http://anderseideblog.wordpress.com/
            Twitter: @anderseide
		
        .LINK
            http://gallery.technet.microsoft.com/Azure-Networking-e52cbf92

    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param(
        [Parameter(Mandatory=$true,HelpMessage="Name of the DNS Server you want to remove")]
        [ValidateNotNullOrEmpty()]
        [string[]] $Name
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
        # For each DNS server in the name list, remove it
        Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removing DNS server from config"
        foreach ($DNSServerName in $Name) {
            # Find the object that has the name of the DNS server
            Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Trying to remove DNS named $DNSServerName"
            $DnsServerToRemove = $AzureVNetConfig.GetElementsByTagName("DnsServer") | ? {$_.name -eq $DNSServerName}
            if ($DnsServerToRemove -ne $null) {
                # If result is not null, remove
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - DNS named $DNSServerName found. Removing"
                $AzureVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.Dns.DnsServers.RemoveChild($DnsServerToRemove)
            } else {
                # Nothing found. Writes to verbose
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - DNS named $DNSServerName not found."
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
