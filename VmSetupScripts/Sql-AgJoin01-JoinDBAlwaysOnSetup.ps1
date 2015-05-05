#
# SQL Server AlwaysOn Database Setup
# - Target:        On all SQL Nodes (with different parameters for master and secondaries)
# - Pre-Condition: Databases created on primary and restored with NO RECOVERY on secondary
# - Tasks:         Creates SQL HA Group on cluster for primary if it does not exist, already
#                  Adds a database to the SQL HA group
#                  Adds Nodes with their databases to the SQL HA group
#
Param
(
    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramHaGroupName,

    [parameter(Mandatory)]
    [ValidateNotNull()]
	[string]
    $paramDatabaseNames,

    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramClusterName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramBackupStorageAccountName,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramBackupStorageAccountBackupContainer,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
	[string]
    $paramSqlInstanceToAdd,

    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
	[string]
    $paramSqlAlwaysOnLocalEndpoint,
		
	[Parameter()]
    [string]
    $paramCommitMode = "Synchronous_Commit",
		
	[Parameter()]
    [string]
    $paramFailoverMode = "Automatic"
)

Write-Output ""
Write-Output "---"  
Write-Output "Joining SQL AlwaysOn High Availability Group..." 
Write-Output "Cluster: $paramClusterName, HA Group: $paramHaGroupName, Node: $paramSqlInstanceToAdd, databases: $paramDatabaseNames"
Write-Output "---" 
Write-Output ""

#
# Import the SQLHelper Module
#

Import-Module .\Util-SqlHelperFunctions.psm1

#
# Constants required in the script
#
$osqlPath = Get-OsqlPath

#
# Main Script Execution for SQL HA Setup for a database
#

Write-Output "---"
Write-Output "Checking if SQL HA group exists, already..."
Write-Output "---"

$existingHAGroupDetails = Get-SQLHADGroupDetails -paramClusterName $paramClusterName -paramSqlInstanceToAdd $paramSqlInstanceToAdd -paramHaGroupName $paramHaGroupName
$primarySqlNode = $existingHAGroupDetails.PrimaryNode
$sqlHAGroupExists = $existingHAGroupDetails.HAGroupExists
Write-Output ("HA Group exists: $sqlHAGroupExists, primary node found: $primarySqlNode")

#
# If the HA Group exists, add the instance to the HA Group
#
if($sqlHAGroupExists)
{
    #
    # Join the existing HA group
    #
    Write-Output "---"
    Write-Output "Adding instance $paramSqlInstanceToAdd to SQL HAG $paramHaGroupName"
    Write-Output "---"

    if($primarySqlNode -eq $null)
    {
        throw "No primary SQL Node found although HA Group exists..."
    }

    Write-Output "Checking if replica for $paramSqlInstanceToAdd exists in HA Group, already..."
    $nodeExistsInHAGroup = Get-SQLHAGroupReplicaExists -InstanceName $paramSqlInstanceToAdd -Name $paramHaGroupName -PrimaryInstanceName $primarySqlNode
    if($nodeExistsInHAGroup) {
        Write-Output "SQL HA Group $paramHaGroupName has already an instance $paramSqlInstanceToAdd, not changing basic group configuration..."
    }
    else
    {
        # Note: as opposed to other scripts I do not delete the replica relationship if the node
        #       exists, already, since that would allow adding databases with this script as well on existing replica nodes

        Write-Output "Adding instance $paramSqlInstanceToAdd to HA Group $paramHaGroupName on primary instance $primarySqlNode..."
        $query = "alter availability group $paramHaGroupName `
                                    add replica on '$paramSqlInstanceToAdd' with `
                                    ( `
                                        EndPoint_URL = 'TCP://$paramSqlAlwaysOnLocalEndpoint', `
                                        Availability_Mode = $paramCommitMode, `
                                        Failover_Mode = $paramFailoverMode, `
                                        Secondary_Role(Allow_connections = ALL) `
                                    ) "

        Write-Output "Query: $query"
        & $osqlPath -l 120  -S $primarySqlNode -E -Q $query

        Write-Output "Joining availability group on $paramSqlInstanceToAdd..."
        $query = "alter availability group $paramHaGroupName JOIN"
        & $osqlPath -l 120 -S $paramSqlInstanceToAdd -E -Q $query
    }

    #
    # Restore the databases and log files prepared for joining in the previous script (Sql-DatabaseCreateAlwaysOnSetup.ps1) and joining them to the HA Group
    #
    Write-Output "---"
    Write-Output "Restoring databases on secondary nodes and joining replicas..."
    Write-Output "---"
    $databaseNames = $paramDatabaseNames -split ";"
    foreach($dbName in $databaseNames)
    {
        Write-Output ("Restoring database on " + $paramSqlInstanceToAdd)
        $backupUrl = "https://$paramBackupStorageAccountName.blob.core.windows.net/$paramBackupStorageAccountBackupContainer/$dbName.bak"
        Write-Output ("RESTORE URL: " + $backupUrl)
        $restoreQuery = "RESTORE DATABASE $dbName FROM URL='$backupUrl' WITH CREDENTIAL='$paramBackupStorageAccountName', NORECOVERY, STATS=5"
        Write-Output $restoreQuery
        & $osqlPath -l 120 -S $paramSqlInstanceToAdd -E -Q $restoreQuery

        Write-Output ("Restoring database logs on " + $paramSqlInstanceToAdd)
        $backupUrl = "https://$paramBackupStorageAccountName.blob.core.windows.net/$paramBackupStorageAccountBackupContainer/$dbName.log"
        Write-Output ("RESTORE URL: " + $backupUrl)
        $restoreQuery = "RESTORE LOG $dbName FROM URL='$backupUrl' WITH CREDENTIAL='$paramBackupStorageAccountName', NORECOVERY, STATS=5"
        Write-Output $restoreQuery
        & $osqlPath -l 120 -S $paramSqlInstanceToAdd -E -Q $restoreQuery

        Write-Output "Joining database $dbName to HA AG replica $paramHaGroupName..."
        $query = "alter database $dbName SET HADR AVAILABILITY GROUP=$paramHaGroupName"
        Write-Output ("join HADR query: $query")
        & $osqlPath -l 120 -S $paramSqlInstanceToAdd -E -Q $query
    }
}
else
{
    throw "No primary node found. Please setup primary node first!"
}

Write-Output ""
Write-Output "---" 
Write-Output "Completed joining replicas to existing HA Group!" 
Write-Output "---" 
Write-Output ""

#
# End of Script
# Next script: Sql-PrepareWitness.ps1 if not executed, yet
#