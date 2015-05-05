#
# Utility for enabling Credential Security Support Provider (CredSSP)
# Required for enabling delegation of credentials to/from clients/servers
#
function Set-CredSSP
{
    [CmdletBinding()]
    Param(
        [switch]
        $paramPresent,

        [switch]
        $paramIsServer,

        [System.String[]]
        $paramDelegateComputers
    )

    #
    # Main Execution Logic
    #
    Write-Host "Enabling Credential Security Support Provider for credential delegation..."
    if($paramIsServer)
    {
        if($paramPresent)
        {
            Write-Verbose "ENABLING CredSSP for role SERVER..."
            Enable-WSManCredSSP -Role Server -Force
        }
        else
        {
            Write-Verbose "DISABLING CredSSP for role SERVER..."
            Disable-WSManCredSSP -Role Server
        }
    } 
    else 
    {
        if($paramPresent)
        {
            Write-Verbose "ENABLING CredSSP for role CLIENT..."
            if($paramDelegateComputers)
            {
                Write-Verbose "- Getting own credSSP info..."
                $currentDelegateComputerInfo = (Get-WSManCredSSP)[0]
                Write-Verbose ("- Retrieved CredSSP Info: " + $currentDelegateComputerInfo)
                foreach($delegateComputer in $paramDelegateComputers) {
                    if($currentDelegateComputerInfo.Contains("wsman/$delegateComputer") -eq $false)
                    {
                        Write-Verbose -Message ("- Enabling delegation for " + $delegateComputer)
                        Enable-WSManCredSSP -Role Client -DelegateComputer $delegateComputer -Force
                    }
                    else
                    {
                        Write-Verbose -Message ("- Delegation already enabled for " + $delegateComputer)
                    }
                }
            }
            else
            {
                throw "Computers allowed for delegation are required!"
            }
        }
        else
        {
            Write-Verbose "DISABLING CredSSP for Role CLIENT..."
            Disable-WSManCredSSP -Role Client
        }
    }
}