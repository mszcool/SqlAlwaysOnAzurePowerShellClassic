#
# Prepares the SQL Server nodes in general
# - Target:  SQL Server Nodes and Witness Node
# - Tasks:   Installs the clustering Windows Feature if requested
#            Installs the clustering command line interfaces
#            Downloads other scripts from Azure storage as needed
# - Note:    Should be executed as a "VM Extension script" to avoid later reboots of the machine
#

Param(
    [switch]
    $installClusterFeatureAsWell,

    [switch]
    $downloadFiles,

    [Parameter(Mandatory=$False)]
    [string]
    $downloadZipArchiveLink,

    [Parameter(Mandatory=$False)]
    [string]
    $targetDirectory = "C:\InstallScripts",

    [Parameter(Mandatory=$false)]
    [string]
    $targetZipArchiveName = "install.zip"
)


#
# Create the local directory as specified in the parameter
#

Write-Host "Check if there are files to get from BLOB storage..."
if($downloadFiles)
{
    Write-Host "Validating Input parameters for downloading files..."
    if([String]::IsNullOrEmpty($downloadZipArchiveLink)) {
        throw "Missing or invalid parameter downloadZipArchiveLink!"
    }
    if([String]::IsNullOrEmpty($targetDirectory)) {
        throw "Missing or invalid parameter targetDirectory!"
    }

    Write-Host "Creating local target directory $targetDirectory if needed..."
    $existingDirectory = Get-Item $targetDirectory -ErrorAction SilentlyContinue
    if($existingDirectory -eq $null) {
        Write-Host "Creating new directory..."
        New-Item $targetDirectory -Type Directory
    } else {
        Write-Host "Directory did exist, already!"
    }

    Write-Host "Downloading the file specified..."
    $targetZipFileName = [System.IO.Path]::Combine($targetDirectory, $targetZipArchiveName)
    Write-Host "Target file name: $targetZipFileName"
    Write-Host "Source URL: $downloadZipArchiveLink"
    Invoke-WebRequest "$downloadZipArchiveLink" -OutFile $targetZipFileName 
    Write-Host "Extracting ZIP file $targetZipFileName..."
    $shellObj = New-Object -ComObject Shell.Application
    $zipArchiveContent = $shellObj.NameSpace("$targetZipFileName")
    Write-Host "Opened ZIP file using the shell object, now extracting..."
    $itemsExtracted = 0
    foreach($item in $zipArchiveContent.items()) {
        Write-Host $item.Path
        $shellObj.NameSpace($targetDirectory).CopyHere($item)
        $itemsExtracted = $itemsExtracted + 1
    }
    Write-Host "Extracted $itemsExtracted items from ZIP archive!"
}
else {
    Write-Host "No files to download from BLOB storage due to missing switch downloadFilesAndScripts!"
}


#
# Installing the Windows Clustering Features
#

Write-Host "Checking if cluster feature is installed..."
$clusterFeature = Get-WindowsFeature -Name "Failover-Clustering"
Write-Host "Result of check: $clusterFeature.Installed"
if($clusterFeature.Installed -ne $True) {
	Write-Host "Installing Cluster Command Line Interface Features..."
    Install-WindowsFeature -Name RSAT-Clustering-PowerShell
    Install-WindowsFeature -Name RSAT-Clustering-CmdInterface
    if($installClusterFeatureAsWell) {
        Write-Host "Installing the Cluster Feature itself..."
        Install-WindowsFeature -Name Failover-Clustering
        Write-Host "Installation completed, restarting computer..."
        Restart-Computer -Force
    } else {
        Write-Host "Skipping Installation of the clustering feature due to missing parameter installClusterFeatureAsWell"
    }
} else {
    Write-Verbose "Windows Failover Cluster Feature installed, already!"
}