#
# SQL Server Failover Cluster Foundation
# - Target:  All nodes running the SQL Server Service
# - Tasks:   Creates a FailoverCluster with the first SQL Server VM
#            Adds other SQL Server VMs to the failover cluster
#

Param (
    [Parameter(Mandatory = $true)]
    [string]
    $paramClusterName,

    [Parameter(Mandatory = $true)]
    [string]
    $paramAzureVirtualClusterName,

    [Parameter(Mandatory = $true)]
    [string]
    $paramClusterIPAddress,

    [switch]
    $paramSetupNewCluster
)

Write-Output ""
Write-Output "---" 
Write-Output "Setting up Windows Cluster used for SQL AlwaysOn HA later..." 
Write-Output "---" 
Write-Output ""


#
# Imports of dependent modules
#
Import-Module FailoverClusters

try {
    #
    # Getting computer's domain name in the AD domain
    #
    $computerDomainInfo = Get-WmiObject Win32_ComputerSystem
    if( ($computerDomainInfo -eq $null) -or ($computerDomainInfo.Domain -eq $null) )
    {
        throw "Unable to find computer's domain name with WMI."
    }

    #
    # Creating or joining the cluster depending on the parameter
    #
    if($paramSetupNewCluster)
    {
        Write-Output "---"
        Write-Output "Setting up failover cluster $paramClusterName..."
        Write-Output "---"

        Write-Output "Try getting existing cluster..."
        $existingCluster = Get-Cluster -Name $paramClusterName -ErrorAction SilentlyContinue
        if( $existingCluster -eq $null )
        {
            Write-Output "Creating WFCS cluster..."
            New-Cluster -Name $paramClusterName -Node $env:COMPUTERNAME -StaticAddress $paramClusterIPAddress -NoStorage -Force
            Write-Output "Cluster created successfully!"
        } 
        else 
        {
            Write-Output "Cluster does exist, already. Skipping creation!"
        }
    }
    else
    {
        Write-Output "---"
        Write-Output "Joining failover cluster $paramClusterName..."
        Write-Output "---"

        $tryContinueFindCluster = $true
        $tryContinueFindClusterAttempts = 0
        $tryContinueFindClusterMaxAttempts = 20
        do {
            # Clear the DNS Cache and try continue finding the cluster
            Clear-DnsClientCache
            Register-DnsClient

            # Try to get the cluster
            try {
                Write-Output "Try finding cluster by Azure virtual cluster name $paramAzureVirtualClusterName..."
                $tryClusterFound = Get-Cluster -Name $paramAzureVirtualClusterName
                if($tryClusterFound -ne $null) {
                    Write-Output "Cluster Found!!"
                    $tryContinueFindCluster = $false
                } else {
                    throw "Failed finding cluster..."
                }
            } catch {
                Write-Output "Failed finding cluster!!"
                if($tryContinueFindClusterAttempts -le $tryContinueFindClusterMaxAttempts) {
                    $tryContinueFindClusterAttempts += 1
                    Start-Sleep -Seconds 20
                } else {
                    Write-Output "Giving up finding cluster after $tryContinueFindClusterMaxAttempts!"
                    $tryContinueFindCluster = $false
                }
            }
        } while($tryContinueFindCluster)
        
        Write-Output "Trying to setup cluster node..."
        Write-Output "Removing existing nodes in the cluster if they are down..."
        $addNode = $true
        $list = Get-ClusterNode -Cluster $paramAzureVirtualClusterName 
        foreach ($node in $list)
        {
            if ($node.Name -eq $env:COMPUTERNAME)
            {
                $addNode = $false
                if ($node.State -eq "Down")
                {
                    $addNode = $true
                    Write-Output "node $env:COMPUTERNAME was down, need remove it from the list."

                    Remove-ClusterNode $env:COMPUTERNAME -Cluster $paramAzureVirtualClusterName -Force
                }
            }
        }
        Write-Output "Completed removing existing nodes which were down!"

        Write-Output "Adding node to cluster..."
        if($addNode) {
            Add-ClusterNode $env:COMPUTERNAME -Cluster $paramAzureVirtualClusterName -NoStorage -ErrorAction Ignore
        }
        Write-Output "Finished adding node to cluster!"
    }
} catch {
    Write-Output "!!!!!!!!!! ERROR !!!!!!!!!!"
    Write-Output $_.Exception.Message
    Write-Output $_.Exception.ItemName
    throw "Failed setting up SQL Server AlwaysOn Availability Groups. Please review earlier error messages for details!"
}

Write-Output ""
Write-Output "---" 
Write-Output "Done with setting up the cluster!" 
Write-Output "---" 
Write-Output "" 

#
# END OF SCRIPT
# Next script - Sql-ClusterAlwaysOnSetup.ps1
#
