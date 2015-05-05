# Sql Server AlwaysOn Cross-Region Setup
# Fully Automated with PowerShell

This end-2-end sample script package (see LICENSE)  provides an end-2-end automated deployment for SQL Server AlwaysOn Availability Groups with Azure Virtual Machines running in two Data Centers (two Regions) for High Availability. The script still makes use of traditional Azure Service Management since we needed something based on released technology at this time for the affected project.

To make use of the script, perform the following steps:
-------------------------------------------------------
- Create *.sql database scripts that create or restore your databases from backups or plain T-SQL scripts
  * Backups could be e.g. restored from Azure Store using the apropriate SQL Server functions
  * Look here for details: http://azure.microsoft.com/en-us/documentation/articles/storage-use-storage-sql-server-backup-restore/
- Copy the *.sql files into the `.\VmSetupScripts` sub-directory to have them moved to the VMs as part of the provisioning scripts.
- Execute `.\Prep-ProvisionMachine.ps1` to setup PowerShell Modules as well as certificates on your machine
  * `.\Prep-ProvisionMachine.ps1 -importDefaultCertificate` installs the default certificate
  * `.\Prep-ProvisionMachine.ps1 -overwriteExistingCerts` creates a new certificate using makecert.exe
- Execute `$domainCreds = Get-Credential` and enter the wanted domain admin credentials for the resulting Active Directory setup.
  * Note: for simplicty the scripts also run the SQL Server Service under that account.
  * If you want to customize this, I am happy to accept pull requests. You should find all you need to do that in the existing code:)
- Execute `Add-AzureAccount` to setup your Azure Subscription (if not done, yet)
- Customize the main configuration file `.\Main-ProvisionConfig.psd1` with your subscription data, SQL Databases and SQL Database script names
- Now Execute the Main Script to start provisioning as shown below

`.\Main-ProvisionCrossRegionAlwaysOn.ps1 -SetupSQLVMs -SetupSQLAG -UploadSetupScripts -ServiceName "mszsqlagustest" -StorageAccountNamePrimaryRegion "mszsqlagusprim" -StorageAccountNameSecondaryRegion "mszsqlagussec" -RegionPrimary "East US" -RegionSecondary "East US 2" -DomainAdminCreds $domainCreds -DomainName "msztest.local" -DomainNameShort "msztest" -Verbose`

Further details on my blog:
---------------------------
A more complete documentation with some additional thoughts is available on my blog. Please follow the link below for details:

http://blog.mszcool.com/index.php/2015/05/azure-vms-sql-server-alwayson-setup-across-multiple-data-centers-fully-automated-classic-service-management/

