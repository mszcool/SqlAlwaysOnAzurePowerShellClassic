
function Remove-AzureVirtualNetwork {
    <#
        .SYNOPSIS
            Removes a Azure Virtual Network

        .DESCRIPTION
            Removes all virtual networks supplied in the Name parameter
    
        .PARAMETER VNetName
            The name of the Virtual Network to remove

        .EXAMPLE
            Remove-AzureVirtualNetwork -Name "MyNetwork"

        .EXAMPLE
            Remove-AzureVirtualNetwork -Name "MyFirstNetwork","MySecondNetwork" 

        .NOTES
            Author: Anders Eide
            Blog: http://anderseideblog.wordpress.com/
            Twitter: @anderseide
		
        .LINK
            http://gallery.technet.microsoft.com/Azure-Networking-e52cbf92

    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param(
        [Parameter(Mandatory=$true,HelpMessage="Name of the new network you want to remove")]
        [ValidateNotNullOrEmpty()]
        [string[]] $VNetName
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
        # For each name in the Name parameter, try to remove
        foreach ($VNet in $VNetName) {
            Write-Verbose -Message "$(Get-Date -Format "HH:mm:ss") - Removing $name from configuration"
            $virtNetToRemove = $AzureVNetConfig.GetElementsByTagName("VirtualNetworkSite") | ? {$_.name -eq $VNet}
            if ($virtNetToRemove -ne $null) {
                $AzureVNetConfig.NetworkConfiguration.VirtualNetworkConfiguration.VirtualNetworkSites.RemoveChild($virtNetToRemove)
            } else {
                Write-Verbose "$(Get-Date -Format "HH:mm:ss") - Virtual Network $VNet does not exists"
                Write-Host "$(Get-Date -Format "HH:mm:ss") - Virtual Network $VNet does not exists"
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
