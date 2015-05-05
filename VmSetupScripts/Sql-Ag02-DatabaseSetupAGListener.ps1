#
# SQL Server AlwaysON Availability Group Listener Setup
# - Target:        All first sql server nodes in a data center
# - Pre-Condition: AlwaysOn Availability Group with datbases must be setup, already.
# - Tasks:         Creates a Cluster Resource for the AlwaysOn AG Listener
#
Param
(
    [Parameter(Mandatory)]
    [string]
    $paramHaGroupName,

    [Parameter(Mandatory)]
    [string]
    $paramClusterName,

    [Parameter(Mandatory)]
    [string]
    $paramPrimarySqlNode,

    [Parameter(Mandatory)]
    [string]
    $paramPrimaryILBIP,

    [Parameter(Mandatory)]
    [string]
    $paramPrimaryILBIPSubnetMask,

    [Parameter(Mandatory)]
    [string]
    $paramSecondaryILBIP,

    [Parameter(Mandatory)]
    [string]
    $paramSecondaryILBIPSubnetMask,

    [Parameter(Mandatory)]
    [string]
    $paramProbePort,

    [Parameter(Mandatory)]
    [string]
    $paramAGListenerName,

    [Parameter(Mandatory)]
    [string]
    $paramPrimaryClusterNetworkName,

    [Parameter(Mandatory)]
    [string]
    $paramSecondaryClusterNetworkName
)


Write-Output ""
Write-Output "---" 
Write-Output "Setting up SQL AlwaysOn AG Listener for datacenter location..." 
Write-Output "Cluster: $paramClusterName, HA Group: $paramHaGroupName, SQL Server: $paramPrimarySqlNode"
Write-Output "AG Listener Name: $paramAGListenerName"
Write-Output "Primary Cluster Network: $paramPrimaryClusterNetworkName, Secondary Cluster Network: $paramSecondaryClusterNetworkName"
Write-Output "---" 
Write-Output ""

#
# Import the SQL Utilities Module
#
Import-Module .\Util-SqlHelperFunctions.psm1 -Force

#
# Constants required in the script
#
$osqlPath = Get-OsqlPath

#
# Main Script Execution
#

Write-Output "Checking if availabiltiy group $paramHaGroupName does exist, already..."
if ((Get-SQLHAGroupExists -InstanceName $paramPrimarySqlNode -Name $paramHaGroupName) -eq $False) {
    throw "HA Group does not exist. Please create the HA group by using Sql04-DatabaseCreateAlwaysOnSetup.ps1 first!"
}

Write-Output "Checking if the availability group listener does exist or not..."
if ((Get-SQLHAGroupListenerExists -InstanceName $paramPrimarySqlNode -ListenerName $paramAGListenerName -Verbose $True) -eq $False) {
    Write-Output "AG Listener $paramAGListenerName does not exist, creating it..."
    $sql = "alter availability group [$paramHaGroupName] `
            add listener N'$paramAGListenerName' ( `
                         WITH IP `
                         ( `
                            (N'$paramPrimaryILBIP', N'$paramPrimaryILBIPSubnetMask'), `
                            (N'$paramSecondaryILBIP', N'$paramSecondaryILBIPSubnetMask') `
                         ) `
                , PORT=1433);"
    Write-Output "SQL: $sql"
    & $osqlPath -l 120 -S $InstanceName -E -Q $sql
} else {
    Write-Output "AG Listener $paramAGListenerName does exist, skipping creation!"
}

Write-Output "Now configuring cluster resource for Azure Internal Load Balancer probes and parameters..."
$primaryIPResourceName = [String]::Concat($paramHaGroupName, "_", $paramPrimaryILBIP)
$secondaryIPResourceName = [String]::Concat($paramHaGroupName, "_", $paramSecondaryILBIP)
Get-ClusterResource $primaryIPResourceName | Set-ClusterParameter -Multiple @{"Address"="$paramPrimaryILBIP";"ProbePort"="$paramProbePort";"SubnetMask"="$paramPrimaryILBIPSubnetMask";"Network"="$paramPrimaryClusterNetworkName";"OverrideAddressMatch"=1;"EnableDhcp"=0}
Get-ClusterResource $secondaryIPResourceName | Set-ClusterParameter -Multiple @{"Address"="$paramSecondaryILBIP";"ProbePort"="$paramProbePort";"SubnetMask"="$paramSecondaryILBIPSubnetMask";"Network"="$paramSecondaryClusterNetworkName";"OverrideAddressMatch"=1;"EnableDhcp"=0}

Write-Output ""
Write-Output "---" 
Write-Output "Completed setting up AlwaysOn Availability Group Listener in Cluster..." 
Write-Output "---" 
Write-Output ""

#
# END OF SCRIPT
# Next script - Sql07-PrepareWitness.ps1
#