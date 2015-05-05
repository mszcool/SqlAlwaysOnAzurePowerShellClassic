#
# SQL Server Basic Configuration
# - Target:  All nodes running the SQL Server Service
# - Tasks:   Adds domain admin to SQL Server Sys Admins
#            Sets up firewall rules for SQL Server, SQL AlwaysOn and Azure Load Balancer Probes
#            Installs FailoverClusters Windows Feature including PowerShell and CLI
# - Note:    THIS SCRIPT MUST BE EXECUTED AS LOCAL ADMIN since the domain admin does not have
#            access to SQL Server at this time, yet!
#

Param
(
    [Parameter(Mandatory = $True)]
    [string]
    $domainNameShort, 

    [Parameter(Mandatory = $True)]
    [string]
    $domainNameLong,

    [Parameter(Mandatory = $True)]
    [string]
    $domainAdminUser,

    [Parameter(Mandatory)]
    [string]
    $dataDriveLetter,

    [Parameter(Mandatory)]
    [string]
    $dataDirectoryName,

    [Parameter(Mandatory)]
    [string]
    $logDirectoryName,

    [Parameter(Mandatory)]
    [string]
    $backupDirectoryName
)

Write-Output ""
Write-Output "---" 
Write-Output "Setting up SQL Server Machine (data directories, firewall rules, SQL Admin user)..." 
Write-Output "---" 
Write-Output ""


#
# Module Imports
#
Import-Module .\Util-CredSSP.psm1
Import-Module .\Util-SqlHelperFunctions.psm1

$osqlPath = Get-OsqlPath

try {

    #
    # Setting up Credential Service Provider (for file share witness access)
    #
    Write-Output "---"
    Write-Output "Setting up CredSSP for file share witness trusted access..."
    Write-Output "---"

    Set-CredSSP -paramPresent -paramIsServer -Verbose:($PSBoundParameters['Verbose'] -eq $true)
    Set-CredSSP -paramPresent -paramDelegateComputers ("*." + $domainNameLong) -Verbose:($PSBoundParameters['Verbose'] -eq $true)


    #
    # Add the domain admin to the SQL Server Service Admins
    #
    Write-Output "---"
    Write-Output "Setting up domain admin user as SQL Admin..."
    Write-Output "---"

    $sqlStatement1 = "CREATE LOGIN [$domainAdminUser] FROM WINDOWS"
    $sqlStatement2 = "EXEC master..sp_addsrvrolemember @loginame = N'$domainAdminUser', @rolename = N'sysadmin'"

    Write-Output "Calling $osqlPath"
    Write-Output "- $sqlStatement1"
    & $osqlPath -l 120 -E -Q $sqlStatement1
    Write-Output "- $sqlStatement2"
    & $osqlPath -l 120 -E -Q $sqlstatement2


    #
    # Creating the Storage Spaces Pool for the data disks
    #
    Write-Output "---"
    Write-Output "Setting up Storage Spaces for the data drive..."
    Write-Output "---"

    Import-Module Storage;
    if((Get-StoragePool -FriendlyName "SqlDataDiskPool" -ErrorAction SilentlyContinue) -eq $null) {
        Stop-Service -Name ShellHWDetection
        $PoolCount = Get-PhysicalDisk -CanPool $True;
        $DiskCount = $PoolCount.count;
        $PhysicalDisks = Get-StorageSubSystem -FriendlyName "Storage Spaces*" | Get-PhysicalDisk -CanPool $True;
        New-StoragePool -FriendlyName "SqlDataDiskPool" -StorageSubsystemFriendlyName "Storage Spaces*" -PhysicalDisks $PhysicalDisks `
            | New-VirtualDisk -FriendlyName "Sql Data Disk" -Interleave 65536 -NumberOfColumns $DiskCount -ResiliencySettingName simple -UseMaximumSize `
            | Initialize-Disk -PartitionStyle GPT -PassThru | New-Partition -DriveLetter $dataDriveLetter -UseMaximumSize `
            | Format-Volume -FileSystem NTFS -NewFileSystemLabel "SqlDataDisk" -AllocationUnitSize 65536 -Confirm:$false;
        Start-Service -Name ShellHWDetection
    } else {
        Write-Output "SqlDataDiskPool does exist, already. Skipping Creation!"
    }


    #
    # Updating SQL Server Default Database Path
    #
    Write-Output "---"
    Write-Output "Setting default database directories..."
    Write-Output "---"

    $dataDirectory = $dataDriveLetter + ":\" + $dataDirectoryName
    Write-Output "Setting SQL default database directory to $dataDirectory"
    if( !(Test-Path -path $dataDirectory) )
    {
        Write-Output "Directory does not exist, creating it..."
        New-Item -ItemType Directory -Path $dataDirectory
    }
    $query = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultData', REG_SZ, N'$dataDirectory'"
    Write-Output $query
    & $osqlPath -l 120 -E -Q $query

    $logDirectory = $dataDriveLetter + ":\" + $logDirectoryName
    Write-Output "Setting SQL default log directory to $logDirectory"
    If( !(Test-Path -path $logDirectory) ) {
        Write-Output "Directory does not exist, creating it..."
        New-Item -ItemType Directory -Path $logDirectory
    }
    $query = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'DefaultLog', REG_SZ, N'$logDirectory'"
    Write-Output $query
    & $osqlPath -l 120 -E -Q $query

    $backupDirectory = $dataDriveLetter + ":\" + $backupDirectoryName
    Write-Output "Setting SQL default log directory to $backupDirectory"
    If( !(Test-Path -path $backupDirectory) ) {
        Write-Output "Directory does not exist, creating it..."
        New-Item -ItemType Directory -Path $backupDirectory
    }
    $query = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'BackupDirectory', REG_SZ, N'$backupDirectory'"
    Write-Output $query
    & $osqlPath -l 120 -E -Q $query

    Write-Output "---"
    Write-Output "Restarting SQL Server to apply settings..."
    Write-Output "---"

    RestartSqlServer


    #
    # Enabling Firewall Rules for sqlserver.exe and sqlbrowser.exe
    #
    Write-Output "---"
    Write-Output "Enabling SQL Server Firewall Rules"
    Write-Output "---"

    $sqlServerProcessExe = Join-Path ${Env:ProgramFiles} -ChildPath "Microsoft SQL Server\MSSQL12.MSSQLSERVER\MSSQL\Binn\sqlservr.exe"
    $sqlServerBrowserExe = Join-Path ${env:ProgramFiles(x86)} -ChildPath "Microsoft SQL Server\90\Shared\sqlbrowser.exe"
    Write-Output "    $sqlServerProcessExe"
    Write-Output "    $sqlServerBrowserExe"

    $sqlFirewallRule = Get-NetFirewallRule -Name "SQL Server Incoming Connections" -ErrorAction SilentlyContinue
    if($sqlFirewallRule -eq $null) {
        New-NetFirewallRule -Name "SQL Server Incoming Connections" `
                            -Description "Allow all incoming connections to SQL Server" `
                            -DisplayName "SQL Server Incoming Connections" `
                            -Enabled True `
                            -Action Allow `
                            -Profile Any `
                            -Protocol "TCP" `
                            -Program $sqlServerProcessExe
    } else {
        Write-Verbose ("Firewall Rule '" + $sqlFirewallRule.DisplayName + "' exists, already!")
    }

    $sqlBrowserFirewallRule = Get-NetFirewallRule -Name "SQL Server Browser Incoming Connections" -ErrorAction SilentlyContinue
    if($sqlBrowserFirewallRule -eq $null) {
        New-NetFirewallRule -Name "SQL Server Browser Incoming Connections" `
                            -Description "Allow all incoming connections to SQL Server Browser" `
                            -DisplayName "SQL Server Browser Incoming Connections" `
                            -Enabled True `
                            -Action Allow `
                            -Profile Any `
                            -Protocol "TCP" `
                            -Program $sqlServerBrowserExe
    } else {
        Write-Verbose ("Firewall Rule '" + $sqlServerBrowserExe.DisplayName + "' exists, already!")
    }

    $sqlAzureProbeFirewallRule = Get-NetFirewallRule -Name "SQL Server Azure Probe Port" -ErrorAction SilentlyContinue
    if($sqlAzureProbeFirewallRule -eq $null) {
        New-NetFirewallRule -Name "SQL Server Azure Probe Port" `
                            -Description "Enables Probe Port for Always-On Listener on Azure ILB (Internal Load Balancer)" `
                            -DisplayName "SQL Server Azure ILB Probe Port" `
                            -Enabled True `
                            -Action Allow `
                            -Profile Any `
                            -Protocol "TCP" `
                            -LocalPort 59999 `
                            -RemotePort 59999
    } else {
        Write-Verbose ("Firewall Rule '" + $sqlAzureProbeFirewallRule.DisplayName + "' exists, already!")
    }

    $sqlAlwaysOnFirewallRule = Get-NetFirewallRule -Name "SQL Server AlwaysOn HA EndPoint" -ErrorAction SilentlyContinue
    if($sqlAlwaysOnFirewallRule -eq $null) {
        New-NetFirewallRule -Name "SQL Server AlwaysOn HA EndPoint" `
                            -Description "Enables Port for Always-On HA" `
                            -DisplayName "SQL Server AlwaysOn HA EndPoint" `
                            -Enabled True `
                            -Action Allow `
                            -Profile Any `
                            -Protocol "TCP" `
                            -LocalPort 5022 `
                            -RemotePort 5022
    } else {
        Write-Verbose ("Firewall Rule '" + $sqlAlwaysOnFirewallRule.DisplayName + "' exists, already!")
    }

    Write-Output "Done setting up fire wall rules!"


    #
    # Adding the Windows Server Cluster Feature
    #
    Write-Output "---"
    Write-Output "Adding the Windows Server Clustering Feature (needed for SQL AlwaysOn)"
    Write-Output "---"

    $clusterFeature = Get-WindowsFeature -Name "Failover-Clustering"
    if($clusterFeature.Installed -ne $True) {
        Install-WindowsFeature -Name RSAT-Clustering-PowerShell
        Install-WindowsFeature -Name RSAT-Clustering-CmdInterface
        Install-WindowsFeature -Name Failover-Clustering
        Restart-Computer -Force
    } else {
        Write-Output "Windows Failover Cluster Feature installed, already"
    }
} catch {
    Write-Output "!!!!!!!!!! ERROR !!!!!!!!!!"
    Write-Output $_.Exception.Message
    Write-Output $_.Exception.ItemName
    throw "Failed setting up SQL Server AlwaysOn Availability Groups. Please review earlier error messages for details!"
}



Write-Output ""
Write-Output "---" 
Write-Output "Done with basic SQL Server Setup!" 
Write-Output "---" 
Write-Output ""

#
# END OF SCRIPT
# Next script - Sql-ClusterSetup.ps1
#
