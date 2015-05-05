#######################################################################################
# Number of helper functions for SQL AlwaysOn HA Setup and general SQL Configurations #
#######################################################################################

#
# Constants required in the script
#
$osqlPath = "C:\Program Files\Microsoft SQL Server\120\Tools\Binn\osql.exe"

function Get-OsqlPath()
{
    return $osqlPath
}


#
# General SQL Server Helper Methods
#
function RestartSqlServer()
{
    $list = Get-Service -Name MSSQL*

    foreach ($s in $list)
    {
        Set-Service -Name $s.Name -StartupType Automatic
        if ($s.Status -ne "Stopped")
        {
            $s.Stop()
            $s.WaitForStatus("Stopped")
            $s.Refresh()
        }
        if ($s.Status -ne "Running")
        {
            $s.Start()
            $s.WaitForStatus("Running")
            $s.Refresh()
        }
    }
}

function IsSQLLogin($SqlInstance, $Login )
{
	$query = & $osqlPath -S $SqlInstance -E -Q "select count(name) from master.sys.server_principals where name = '$Login'" -h-1
        return ($query[0].Trim() -eq "1")
}

function IsSrvRoleMember($SqlInstance, $Login, $Role )
{
	$query = & $osqlPath -S $SqlInstance -E -Q "select IS_srvRoleMember('$Role', '$Login')" -h-1
        return ($query[0].Trim() -eq "1")
}

function AddLoginIfNotExists($SqlInstance, $Login)
{
    Write-Verbose "Checking if Login exists..."
    Write-Verbose $Login
    $bCheck = IsSQLLogin -SqlInstance $SqlInstance -Login $Login
    If( $bCheck -eq $false ) {
        Write-Verbose "Login does not exist, creating login in SQL Server from Windows..."
        & $osqlPath -S $InstanceName -E -Q "Create Login [$ServiceAccount] From Windows"
    }
}

function AddServerRoleMemberIfNotAlready($SqlInstance, $Login, $Role)
{
    Write-Verbose "Checking if login is member of role..."
    Write-Verbose $Login
    Write-Verbose $Role
    $bCheck = IsSrvRoleMember -SqlInstance $SqlInstance -Login $Login -Role $Role
    if( $bCheck -eq $false) {
        Write-Verbose "Login is not member of role, adding it..."
        & $osqlPath -S $InstanceName -E -Q "Exec master.sys.sp_addsrvrolemember '$Login', '$Role'"
    }
}


#
# SQL Instance Name Functions
#

function Get-PureInstanceName ($InstanceName)
{
    $list = $InstanceName.Split("\")
    if ($list.Count -gt 1)
    {
        $list[1]
    }
    else
    {
        "MSSQLSERVER"
    }
}

function Get-SQLInstanceName ($node, $InstanceName)
{
    $pureInstanceName = Get-PureInstanceName -InstanceName $InstanceName

    if ("MSSQLSERVER" -eq $pureInstanceName)
    {
        $node
    }
    else
    {
        $node + "\" + $pureInstanceName
    }
}

function Get-SqlServiceName ($InstanceName)
{
    $list = $InstanceName.Split("\")
    if ($list.Count -gt 1)
    {
        "MSSQL$" + $list[1]
    }
    else
    {
        "MSSQLSERVER"
    }
}

function Get-InstanceSqlSmoPath ($InstanceName)
{
    if ( ([String]$InstanceName).Contains("\") -eq $True )
    {
        return "SQLSERVER:\SQL\$InstanceName"
    } 
    else 
    {
        return "SQLSERVER:\SQL\$InstanceName\DEFAULT"
    }
}

function Get-SqlInstanceExists($InstanceName)
{
    $list = Get-Service -Name MSSQL*
    $retInstanceName = $null

    $pureInstanceName = Get-PureInstanceName -InstanceName $InstanceName

    if ($pureInstanceName -eq "MSSQLSERVER")
    {
        if ($list.Name -contains "MSSQLSERVER")
        {
            $retInstanceName = $InstanceName
        }
    }
    elseif ($list.Name -contains $("MSSQL$" + $pureInstanceName))
    {
        Write-Verbose -Message "SQL Instance $InstanceName is present"
        $retInstanceName = $pureInstanceName
    }

    return ($retInstanceName -ne $null)
}


#
# SQL HA Group Helper Functions
#

function IsHAEnabled($SqlInstance)
{
	$query = & $osqlPath -S $SqlInstance -E -Q "select ServerProperty('IsHadrEnabled')" -h-1
	return ($query[0].Trim() -eq "1")
}

function Get-SQLHAGroupExists($InstanceName, $Name)
{
	Write-Verbose -Message "Check HAG $Name including instance $InstanceName ..."
	$query = & $osqlPath -l 120  -S $InstanceName -E -Q "select count(name) from master.sys.availability_groups where name = '$Name'" -h-1
    
    Write-Verbose -Message "SQL: $query"
    
    [bool] [int] ([String] $query[0]).Trim()
}

function Get-SQLHAGroupListenerExists($InstanceName, $ListenerName) {
    Write-Verbose -Message "Check HAG Listener $ListenerName on SQL Server Instance $InstanceName..."
    $query = & $osqlPath -l 120 -S $InstanceName -E -Q "select count(dns_name) from master.sys.availability_group_listeners where dns_name='$ListenerName'" -h-1

    Write-Verbose -Message "SQL: $query"

    [bool] [int] ([String] $query[0]).Trim()
}

function Get-SQLHAGroupIsPrimaryReplica($InstanceName, $Name)
{
	$query = & $osqlPath -l 120  -S $InstanceName -E -Q "select count(replica_id) from sys.dm_hadr_availability_replica_states s `
							inner join sys.availability_groups g on g.group_id = s.group_id `
							where g.name = '$Name' and s.role_desc = 'PRIMARY' and s.is_local = 1" -h-1
	[bool] [int] ([String] $query[0]).Trim()
}

function Get-SQLHAGroupReplicaExists($InstanceName, $Name, $PrimaryInstanceName)
{
	$query = & $osqlPath -l 120  -S $PrimaryInstanceName -E -Q "select count(replica_id) from sys.availability_replicas r `
                                   inner join sys.availability_groups g on g.group_id = r.group_id `
                                   where g.name = '$Name' and r.replica_server_name = '$InstanceName' " -h-1
	[bool] [int] ([String] $query[0]).Trim()
}

function Get-SQLHADGroupDetails($paramClusterName, $paramSqlInstanceToAdd, $paramHaGroupName)
{
    $primarySqlNode = ""
    $sqlHAGroupExists = $false

    Write-Verbose -Message ("Getting nodes for Cluster $paramClusterName")
    $clusterNodes = Get-ClusterNode -Cluster $paramClusterName
    foreach($clusterNode in $clusterNodes)
    {
        Write-Verbose -Message ("Checking Node $clusterNode.Name...")
        $sqlInstanceName = Get-SQLInstanceName -node $clusterNode.Name -InstanceName $paramSqlInstanceToAdd
    
        Write-Verbose -Message ("Checking if node is a SQL Server  node or a witness node...")
    
        $sqlPureInstanceName = Get-PureInstanceName -InstanceName $sqlInstanceName

        $sqlServiceExists = Get-SqlInstanceExists -InstanceName $sqlInstanceName
        if($sqlServiceExists)
        {
            Write-Verbose "Server runs SQL Service, checking HA Group status..."

            $sqlHACheck = Get-SQLHAGroupExists -InstanceName $sqlInstanceName -Name $paramHaGroupName
            if($sqlHACheck) {
                Write-Verbose -Message "Found SQL HA Group $paramHaGroupName on node $sqlInstanceName!"
                $sqlHAGroupExists = $true

                Write-Verbose -Message "Checking if node is the primary replica..."
                $sqlPrimaryReplicaCheck = Get-SQLHAGroupIsPrimaryReplica -InstanceName $sqlInstanceName -Name $paramHaGroupName
                if($sqlPrimaryReplicaCheck)
                {
                    Write-Verbose -Message "Found primary replica node on $sqlInstanceName!"
                    $primarySqlNode = $sqlInstanceName
                }
            }
        } 
        else 
        {
            Write-Warning -Message "Node $clusterNode.Name does not run SQL Service, must be a SQL Witness Node..."
        }
    }

    $retObject = @{ 
                    HAGroupExists = $sqlHAGroupExists 
                    PrimaryNode = $primarySqlNode 
                  }

    return $retObject
}