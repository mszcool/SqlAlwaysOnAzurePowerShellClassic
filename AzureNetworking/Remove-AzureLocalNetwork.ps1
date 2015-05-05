
function Remove-AzureLocalNetwork {
    <#
        .SYNOPSIS
            Removes a Local netowrk form the Azure Network Configuration

        .DESCRIPTION
            Add a local network name to this cmdlet to remove it from your network configuration

        .PARAMETER Name
            The name of the local network to remove

        .EXAMPLE
            Remove-AzureLocalNetwork -Name "MyLocalNetwork"

        .NOTES
            Author: Anders Eide
            Blog: http://anderseideblog.wordpress.com/
            Twitter: @anderseide
		
        .LINK
            http://gallery.technet.microsoft.com/Azure-Networking-e52cbf92

    #>

    [CmdletBinding(SupportsShouldProcess=$true)]
    Param(
        [Parameter(Mandatory=$true,HelpMessage="Name of the local network you want to remove")]
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
        # For each network supplied, remove it
        Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Removing local network from your configuration"
        foreach ($LNet in $Name) {
            $localNetToRemove = $AzureVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.LocalNetworkSites.LocalNetworkSite | ? {$_.name -eq $LNet}
            $AzureVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.LocalNetworkSites.RemoveChild($localNetToRemove)
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
