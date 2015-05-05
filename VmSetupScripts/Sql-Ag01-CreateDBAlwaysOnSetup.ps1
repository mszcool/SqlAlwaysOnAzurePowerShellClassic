#
# SQL Server Database Setup on the Primary Node
# - Target:        Only the Primary SQL Node in the AlwaysOn Availability Group
# - Pre-Condition: All databases passed in must be created, already, if not called with paramCreateDatabases
# - Tasks:         Creates databases for the AlwaysOn Availability Groups
#                  Creates the initial backups for the AlwaysOn Availability Group Setup
#                  Restores the databases on the other SQL Server Nodes
#
Param
(
    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramHaGroupName,

    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $paramClusterName,

    [Parameter()]
    [string]
    $paramCommitMode = "Synchronous_Commit",
		
	[Parameter()]
    [string]
    $paramFailoverMode = "Automatic",
    
    [parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
	[string]
    $paramSqlAlwaysOnLocalEndPoint,

    [Parameter(Mandatory)]
    [string]
    $paramDatabaseNames,

    [Parameter(Mandatory)]
    [string]
    $paramPrimarySqlNode,

    [Parameter(Mandatory)]
    [string]
    $paramSecondarySqlNodes,

    [switch]
    $paramCreateDatabases,

    [Parameter(Mandatory=$false)]
    [string]
    $paramCreateDatabasesSqlScriptFileNames,

    [Parameter(Mandatory)]
    [string]
    $paramStorageAccountName,

    [Parameter(Mandatory)]
    [string]
    $paramStorageAccountKey,

    [Parameter(Mandatory)]
    [string]
    $paramStorageAccountBackupContainer
)


Write-Output ""
Write-Output "---" 
Write-Output "Setting up SQL AlwaysOn High Availability Group..." 
Write-Output "Cluster: $paramClusterName, HA Group: $paramHaGroupName, Primary: $paramPrimarySqlNode, databases: $paramDatabaseNames"
Write-Output "---" 
Write-Output ""

#
# Import the SQL Utilities Module
#
Import-Module .\Util-SqlHelperFunctions.psm1

#
# Constants required in the script
#
$osqlPath = Get-OsqlPath

#
# Variables for the whole script
#
$databaseNames = ($paramDatabaseNames -split ";")
$scriptFiles = ($paramCreateDatabasesSqlScriptFileNames -split ";")
$secondaryNodes = ($paramSecondarySqlNodes -split ";")

#
# Creating databases if they do not exist, yet
#
if($paramCreateDatabases)
{
    Write-Output "---"
    Write-Output "Creating Databases with deployment scripts passed in..."
    Write-Output "---"

    if($paramCreateDatabasesSqlScriptFileNames -eq $null)
    {
        throw "Creating databases requires database *.sql deplyoment scripts to be passed in!"
    }
    if($paramCreateDatabasesSqlScriptFileNames.Length -eq 0)
    {
        throw "Creating databases requires database *.sql deployment scripts to be passed in!"
    }

    foreach($scriptName in $scriptFiles)
    {
        Write-Output ("Executing script " + $scriptName)
        & $osqlPath -S $paramPrimarySqlNode -E -i $scriptName
    }
}


#
# Setting up SQL Server for backup to blob storage
#

Write-Output "---"
Write-Output "Setting up backup for Azure storage account $paramStorageAccountName..."
Write-Output "---"

Write-Output ("Setting up backup credential on " + $paramPrimarySqlNode)

$createCredSql = "CREATE CREDENTIAL $paramStorageAccountName WITH IDENTITY='$paramStorageAccountName', SECRET='$paramStorageAccountKey'"
& $osqlPath -S $paramPrimarySqlNode -E -Q $createCredSql
foreach($secondarySqlNode in $secondaryNodes)
{
    Write-Output ("Setting up backup credential on " + $secondarySqlNode)
    & $osqlPath -S $secondarySqlNode -E -Q $createCredSql
}


#
# Backup the database to the BLOB storage account
#

Write-Output "---"
Write-Output "Backup databases to storage account $paramStorageAccountName..."
Write-Output "---"

foreach($dbName in $databaseNames)
{
    $query = "ALTER DATABASE $dbName SET RECOVERY FULL"
    Write-Output $query
    & $osqlPath -S $paramPrimarySqlNode -E -Q $query

    $backupUrl = "https://$paramStorageAccountName.blob.core.windows.net/$paramStorageAccountBackupContainer/$dbName.bak"
    Write-Output ("Backup DB URL: " + $backupUrl)
    
    $backupQuery = "BACKUP DATABASE [$dbName] TO URL = '$backupUrl' WITH CREDENTIAL = '$paramStorageAccountName', FORMAT"
    Write-Output ($backupQuery)
    & $osqlPath -S $paramPrimarySqlNode -E -Q $backupQuery
}

#
# Create the new AlwaysOn Availability Group if it does not exist, already
#

Write-Output "---"
Write-Output "Creating new SQL AlwaysOn AG $paramHaGroupName if it does not exist, yet..."
Write-Output "---"

Write-Output "Looking for existing SQL HA Group..."
$existingHAGroupDetails = Get-SQLHADGroupDetails -paramClusterName $paramClusterName -paramSqlInstanceToAdd $paramPrimarySqlNode -paramHaGroupName $paramHaGroupName
$primarySqlNode = $existingHAGroupDetails.PrimaryNode
$sqlHAGroupExists = $existingHAGroupDetails.HAGroupExists
Write-Output ("HA Group exists: $sqlHAGroupExists, primary node found: $primarySqlNode")

$dbListString = $paramDatabaseNames -replace ";", ", "
Write-Output "Databses: $dbListString"

if($sqlHAGroupExists -eq $false)
{
    Write-Output "Creating new SQL HA Group $paramHaGroupName..."
    $query = "CREATE AVAILABILITY GROUP $paramHaGroupName `
                                  FOR DATABASE $dbListString `
                                  REPLICA ON `
                                  '$paramPrimarySqlNode' WITH ( `
                                       ENDPOINT_URL = 'TCP://$paramSqlAlwaysOnLocalEndPoint', `
                                       Availability_Mode = $paramCommitMode, `
                                       Failover_Mode = $paramFailoverMode `
                                  )"
    Write-Output $query
    & $osqlPath -l 120 -S $paramPrimarySqlNode -E -Q $query
}
else
{
    Write-Output "Updating existing SQL HA Group $paramHaGroupName with new databases..."
    $query = "ALTER AVAILABILITY GROUP $paramHaGroupName `
                                 ADD DATABASE $dbListString"
    Write-Output $query
    & $osqlPath -l 120 -S $paramPrimarySqlNode -E -Q $query
}

Write-Output "---"
Write-Output "Backup Database Logs after databases added to HA group..."
Write-Output "---"

foreach($dbName in $databaseNames)
{
    $backupUrl = "https://$paramStorageAccountName.blob.core.windows.net/$paramStorageAccountBackupContainer/$dbName.log"
    Write-Output ("Backup DB URL: " + $backupUrl)
    
    $backupQuery = "BACKUP LOG [$dbName] TO URL = '$backupUrl' WITH CREDENTIAL = '$paramStorageAccountName', FORMAT"
    Write-Output ($backupQuery)
    & $osqlPath -S $paramPrimarySqlNode -E -Q $backupQuery
}

Write-Output ""
Write-Output "---" 
Write-Output "Done with creating AlwaysOn HA Group and joining databases." 
Write-Output "---" 
Write-Output ""

#
# END OF SCRIPT
# Next script - Sql-DatabaseJoinAlwaysOnSetup.ps1
#