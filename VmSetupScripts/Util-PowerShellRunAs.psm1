#
# Utility for enabling Credential Security Support Provider (CredSSP)
# Required for enabling delegation of credentials to/from clients/servers
#
function Invoke-PoSHRunAs
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [String]
        $FileName,

        [Parameter(Mandatory)]
        [String]
        $Arguments,

        [Parameter(Mandatory)]
        [PSCredential]
        $Credential, 

        [Parameter(Mandatory=$false)]
        [String]
        $LogPath = ".\",

        [Parameter(Mandatory=$false)]
        $WaitMaxAttempts = 100,

        [Parameter(Mandatory=$false)]
        $WaitIntervalInSecs = 60,

        [Switch]
        $NeedsToRunAsProcess,

        [Switch]
        $NeedsToEnableWinRM
    )

    Write-Host "Running script $FileName under user " + ($Credential.UserName)

    $IsVerbosePresent = ($PSBoundParameters["Verbose"] -eq $true)
    Write-Verbose -Message "Running Verbose: $IsVerbosePresent"


    try {
        Write-Verbose -Message "Creating temporary script file to allow advanced parameters..."
        $scriptPath = [System.IO.Path]::GetDirectoryName($FileName)
        $tempScriptsDir = [System.IO.Path]::Combine($scriptPath, "TempScripts")
        $scriptName = [System.IO.Path]::GetFileName($FileName)
        $tempScript = [System.IO.Path]::Combine($tempScriptsDir, "runas-$scriptName")

        if(-not (Test-Path -Path $tempScriptsDir)) 
        {
            Write-Verbose -Message "Creating Temp Scripts Path $tempScriptsDir..."
            New-Item -ItemType Directory $tempScriptsDir
        }
        if(-not (Test-Path -Path $LogPath)) 
        {
            Write-Verbose -Message "Creating Log Path $LogPath..."
            New-Item -ItemType Directory $LogPath
        }

        $command = "$FileName $Arguments -ErrorAction Stop"
        if($NeedsToRunAsProcess) {
            $stdOutLog = [System.IO.Path]::Combine($LogPath, [System.IO.Path]::GetFileName($FileName) + ".out.log")
            Write-Verbose -Message "Log File Path for further details: $stdOutLog"
            $command += " >> $stdOutLog"
            if(Test-Path $stdOutLog) {
                Remove-Item $stdOutLog -ErrorAction Ignore
            }
        }
        if(Test-Path $tempScript) {
            Remove-Item $tempScript -ErrorAction Stop
        }
        "cd $scriptPath" >> $tempScript
        $command >> $tempScript

        if($NeedsToRunAsProcess) {
            Write-Verbose "Setting up schedule task parameters..."
            $taskUser = $Credential.UserName
            $taskPwd = $Credential.GetNetworkCredential().Password
            $taskDate = ((Get-Date).AddHours(10).ToString("MM/dd/yyyy")) # ((Get-Culture).DateTimeFormat.ShortDatePattern))
            $taskTime = ((Get-Date).AddHours(10).ToString("HH:mm"))
            $taskName = [System.IO.Path]::GetFileName($FileName).Trim() + "-Task"
            $taskSchedCmd = "C:\windows\System32\schtasks.exe"
            
            Write-Verbose "Adding the task to the task scheduler..."
            & $taskschedcmd /create /sc ONCE /tn "$taskName" /tr "powershell.exe  -Command `"&{$tempScript}`"" /ru $taskUser /rp $taskPwd /s $env:COMPUTERNAME /st $taskTime /sd $taskDate /F

            Write-Verbose "Manually Executing the task using PowerShell Task Cmdlets"
            $taskScheduledStartDate = Get-Date
            Start-ScheduledTask -TaskName $taskName
            Write-Verbose -Message "Task started, start date: $taskScheduledStartDate" 

            Write-Verbose "Waiting for the scheduled task to complete..."
            $waitAttempts = 0
            do {
                $taskDetails = Get-ScheduledTask -TaskName $taskName
                if($taskDetails.State -eq "Running") {
                    $waitAttempts += 1
                    Write-Verbose -Message "Sleeping for $WaitIntervalInSecs until next check. Attempts so far: $waitAttempts"
                    if($waitAttempts -ge $WaitMaxAttempts) {
                        throw "Task failed to complete within the maximum wait time frame!"
                    } else {
                        Start-Sleep $WaitIntervalInSecs
                    }
                }
            } while ($taskDetails.State -eq "Running")

            $taskLastRuntimeInfo = Get-ScheduledTaskInfo -TaskName $taskName
            $taskLastRuntimeDate = $taskLastRuntimeInfo.LastRunTime
            $taskLastRuntimeExitCode = $taskLastRuntimeInfo.LastTaskResult
            Write-Verbose -Message "Checking task info: $taskLastRuntimeDate, $taskLastRuntimeExitCode"
            if($taskLastRuntimeExitCode -ne 0) {
                throw "Failed executing the last setup task with exit code non zero. Please review details in task scheduler!"
            } else {
                Write-Host "Successfully executed task!"
            }

            Write-Verbose "Deleting the scheduled task..."
            & $taskSchedCmd /delete /tn "$taskName" /f
        } else {
            if($NeedsToEnableWinRM) {
                Enable-PSRemoting -Force
            }
            Invoke-Command `
                -ScriptBlock { ` 
                    Write-Verbose -Message "Calling Start-Process with powershell.exe..."
                    Write-Verbose -Message "Temp Script Name: $Using:tempScript"
                    Write-Verbose -Message "Temp Script Content: $Using:command"
                    & $Using:tempScript
                } `
                -Credential $Credential `
                -Computer ($env:COMPUTERNAME)
            if($NeedsToEnableWinRM) { 
                Disable-PSRemoting -Force
            }            
        }

        if(-not [String]::IsNullOrEmpty($tempScript)) {
            if(Test-Path $tempScript) {
                Remove-Item $tempScript -ErrorAction Ignore
            }
        }
    } catch {
        if(-not [String]::IsNullOrEmpty($tempScript)) {
            if(Test-Path $tempScript) {
                Remove-Item $tempScript -ErrorAction Ignore
            }
        }
        Write-Error $_.Exception.Message
        Write-Error $_.Exception.ItemName
        throw "Failed running PowerShell under different user, please review errors earlier!"
    }
}