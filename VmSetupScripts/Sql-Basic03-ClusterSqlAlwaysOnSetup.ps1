#
# SQL Server AlwaysOn Availability Group Setup
# - Target:  All nodes running the SQL Server Service
# - Tasks:   Sets SQL Service up to run under SQL Server Service Account
#            Adds Login for new SQL Server Service Account
#            Enables SQL AlwaysOn on the SQL Server Service and adds AlwaysOn Endpoint
#
Param(
    [Parameter(Mandatory)]
    [string]
    $paramSqlInstanceName, 

    [Parameter(Mandatory)]
    [string]
    $paramSqlServiceUser,

    [Parameter(Mandatory)]
    [string]
    $paramSqlServicePasswordEnc,
    
    [Parameter(Mandatory)]
    [string]
    $paramSqlPwdEncCertName,

    [Parameter(Mandatory)]
    [string]
    $paramSqlEndpointName,

    [Parameter(Mandatory)]
    [ValidateRange(1000,9999)]
    [UInt32]
    $paramSqlEndpointPort
)


Write-Output ""
Write-Output "---" 
Write-Output "Enabling SQL Server AlwaysOn on SQL Server Instance $paramSqlInstanceName..." 
Write-Output "---" 
Write-Output ""


#
# Module Imports
#
Import-Module .\Util-SqlHelperFunctions.psm1 -Force
Import-Module .\Util-CertsPasswords.psm1 -Force

#
# Constants required in the script
#
$osqlPath = Get-OsqlPath

#
# Decrypt encrypted passwords using the passed certificate
#
Write-Verbose "Decrypting Password with Password Utility Module..."
$paramSqlServicePassword = Get-DecryptedPassword -certName $paramSqlPwdEncCertName -encryptedBase64Password $paramSqlServicePasswordEnc 
Write-Verbose "Successfully decrypted VM Extension passed password"
    

#
# #################################################################################
# Main Script Execution
# #################################################################################
#
try {
    Write-Output "Checking if SQL Server Instance Exists..."
    Write-Verbose $paramSqlInstanceName
    $bSqlInstanceExists = (Get-SqlInstanceExists -InstanceName $paramSqlInstanceName)
    if ( $bSqlInstanceExists -eq $false ) {
        throw "SQL Server Instance with name '" + $paramSqlInstanceName + "' not found!"
    }


    #
    # Add the Logins and configure role memberships
    #

    Write-Output "Setting up logins and role memberships..."

    $sqlServiceUserName = $paramSqlServiceUser
    $sqlServicePassword = $paramSqlServicePassword
    Write-Output "Account to use for SQL Server Service: "
    Write-Verbose $sqlServiceUserName
    AddLoginIfNotExists -SqlInstance $paramSqlInstanceName -Login $sqlServiceUserName
    AddServerRoleMemberIfNotAlready -SqlInstance $paramSqlInstanceName -Login 'NT AUTHORITY\SYSTEM' -Role 'sysadmin'
    AddServerRoleMemberIfNotAlready -SqlInstance $paramSqlInstanceName -Login $sqlServiceUserName -Role 'sysadmin'


    #
    # Setup SQL Service with Domain Account and Enable AlwaysOn
    #

    Write-Output "Setting up SQL Server Service for High Availability..."

    $sqlServiceName = Get-SqlServiceName -InstanceName $paramSqlInstanceName
    Write-Output "SQL Server Service Name: "
    Write-Verbose $sqlServiceName

    Write-Output "Getting Windows Service for SQL Server Service..."
    $sqlService = Get-WmiObject Win32_Service | ? { $_.Name -eq $sqlServiceName }
    if ( $sqlService -eq $null ) {
        throw "Unable to get SQL Server Service in Windows Services via WMI: " + $sqlServiceName
    }
    $sqlService.Change($null,$null,$null,$null,$null,$null,$sqlServiceUserName,$sqlServicePassword,$null,$null,$null)
    Write-Output ("SQL Server Service changed to run under " + $sqlServiceUserName)
    Write-Output "Restarting SQL Server Services..."
    RestartSqlServer
    Write-Output "Restarting SQL Server Services completed!"

    Write-Output "Checking if HA is enabled inside of SQL Server..."
    $bHaCheck = IsHAEnabled -SqlInstance $paramSqlInstanceName
    if ($bHaCheck -eq $false ) {
        Write-Output "HA/AlwaysOn not enabled, enabling it now..."
        Enable-SqlAlwaysOn -ServerInstance $paramSqlInstanceName -Force
        Write-Output "HA/AlwaysOn enabled, restarting SQL Server..."
        RestartSqlServer
        Write-Output "Restarting SQL Server completed!"
    }


    #
    # Configure SQL AlwaysOn Endpoints
    #

    Write-Output "Configuring SQL Server AlwaysOn Listener Endpoint..."
    Write-Output ("SQL Endpoint Name " + $paramSqlEndpointName)
    Write-Output ("SQL Endpoint Port " + $paramSqlEndpointPort)

    Write-Output "Testing endpoint $paramSqlEndpointName on instance $paramSqlInstanceName ..."
    $endpoint = & $osqlPath -S $paramSqlInstanceName -E -Q "select count(*) from master.sys.endpoints where name = '$paramSqlEndpointName'" -h-1
    $endpointCheck = ([bool] [int] $endpoint[0].Trim())
    if($endpointCheck -eq $false)
    {
        Write-Output "Endpoint not configured!"
        Write-Output "Configuring SQL HA AlwaysOn Endpoint $paramSqlEndpointName with port $paramSqlEndpointPort..."

        Write-Output "Creating endpoint and setting it..."
        $sqlSmoObjectPath = Get-InstanceSqlSmoPath -InstanceName $paramSqlInstanceName
        $newEndpoint = New-SqlHADREndpoint $paramSqlEndpointName -Port $paramSqlEndpointPort -Path $sqlSmoObjectPath
        Write-Output "Endpoint object created, now setting it..."
        Set-SqlHADREndpoint -InputObject $newEndpoint -State Started
        Write-Output "Successfully called Set-SqlHADREndpoint..."
        
        Write-Output "Granting connection point access to SQL Server service account..."
        $grantResults = & $osqlPath -S $InstanceName -E -Q "GRANT CONNECT ON ENDPOINT::[$paramSqlEndpointName] TO [$sqlServiceUserName]"
        Write-Output $grantResults[0].Trim()
    }
} catch {
    Write-Output "!!!!!!!!!! ERROR !!!!!!!!!!"
    Write-Output $_.Exception.Message
    Write-Output $_.Exception.ItemName
    throw "Failed setting up SQL Server AlwaysOn Availability Groups. Please review earlier error messages for details!"
}

Write-Output ""
Write-Output "---" 
Write-Output "Done with enabling SQL AlwaysOn on for $paramSqlInstanceName..." 
Write-Output "---" 
Write-Output ""


#
# END OF SCRIPT
# Next script - Sql-DatabaseCreateAlwaysOnS.ps1
#
