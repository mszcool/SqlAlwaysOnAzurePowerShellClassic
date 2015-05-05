@{
	GeneralConfig = @{
			# General settings (e.g. retry times or wait times etc.)
			RetryCount = 32						# This combination waits a bit more than
			RetryIntervalSec = 60				# 30 min. which is typically the time it takes to setup e.g. VPN Gateways at max.
			RemotePowerShellLocalPort = "5986"

			# Subscription and Region Details
			DefaultSubscriptionName = "YOUR SUBSCRIPTION NAME GOES HERE"
			DefaultPrimaryRegion = "North Europe"
			DefaultSecondaryRegion = "West Europe"

			# VM Image Details
			VMImageFamilyDefault = "Windows Server 2012 R2 Datacenter"
			VMImageFamilySql = "SQL Server 2014 RTM Enterprise on Windows Server 2012 R2"
			
			# Availability Set Configurations for SQL Servers
			DefaultAdDcAvailabilitySetName = "ADDCServers"
			DefaultSQLAvailablitySetName = "SQLServers"

			# Storage details for VHDs and backups
			VMVHDADContainerName = "advhdst0"
			VMVHDSQLContainerName = "sqlvhdt0"

			# Details for setup scripts downloaded to VMs via VM Extensions
			SetupScriptsDirectory = ".\VmSetupScripts"
			SetupScriptsStorageContainerName = "setupscriptfiles"
			SetupScriptsZipArchiveName = "SetupScripts.zip"
			SetupScriptsVmTargetDirectory = "C:\SetupScripts"

			# Map script names for setup steps for easier changes later on
			SetupScriptVmExtensionClusterNode = "Pre-NodeGeneralPrep.ps1"
			SetupADForest = "Ad01-AdForestSetup.ps1"
			SetupADSecondaryDC = "Ad02-AdSecondaryDcSetup.ps1"
			SetupSqlAllNodes = "Sql01-AllSqlNodes.ps1"
			SetupSqlPrimaryNode = "Sql02-PrimarySqlNode.ps1"
			SetupSqlSecondaryNodes = "Sql03-SecondarySqlNodes.ps1"
			SetupSqlWitnessNode = "Sql04-WitnessSqlNode.ps1"
		}
	ClusterConfig = @{
		ClusterName = "AGCluster"
		AzureClusterName = "sql1"
		ClusterIP = "10.1.2.100"
		PrimaryNetwork = "Cluster Network 1"
		SecondaryNetwork = "Cluster Network 2"
		WitnessShare = "sqlwitness"
		WitnessFolder = "C:\sqlwitness"
	}
	AvailabilityGroupConfig = @{
		AGName = "mszcoolAG"
		AGListenerPrimaryRegionIP = "10.1.2.4"
		AGListenerPrimaryRegionSubnetMask = "255.255.255.0"
		AGListenerSecondaryRegionIP = "10.2.2.4"
		AGListenerSecondaryRegionSubnetMask = "255.255.255.0"
		AGSqlEndpointName = "Sql1433"		
		AGEndpointName = "Endpoint1"
		AGSqlPort = "1433"
		AGEndpointPort = "5022"
		AGProbePort = "59999"
		AGSqlDataDriveLetter = "S"
		AGSqlDataDirectoryName = "DATA"
		AGSqlLogDirectoryName = "LOG"
		AGSqlBackupDirectoryName = "BACKUP"
		AGSqlDatabaseBackupContainerName = "sqlbackups"
		AGSqlDatabaseNames = "SqlDemoDb1;SqlDemoDb2"				
		AGSqlDatabaseCreateScripts = "Sql-Samples-DatabaseSetupDemoDbs.sql"
	}
	VNetConfig = @{
		PrimaryRegionAddressSpace = "10.1.0.0/16"
		SecondaryRegionAddressSpace = "10.2.0.0/16"
		PrimaryRegionVPNGWIP = "1.1.1.1"
		PrimaryRegionVPNGWSubnet = "10.1.0.0/24"
		SecondaryRegionVPNGWIP = "2.2.2.2"
		SecondaryRegionVPNGWSubnet = "10.2.0.0/24"
		DomainControllerSubnetName = "DCs"
		DomainControllerSubnetAddressSpacePrimary = "10.1.1.0/24"
		DomainControllerSubnetAddressSpaceSecondary = "10.2.1.0/24"
		SQLServerSubnetName = "SQL"
		SQLServerSubnetAddressSpacePrimary = "10.1.2.0/24"
		SQLServerSubnetAddressSpaceSecondary = "10.2.2.0/24"
		FallbackDNS = "8.8.8.8"
		VNETVPNKey = "123asd123"
	}
	AllNodes = @(
		@{
			Role = "PrimaryDC"		# Don't change, can only appear once
            NodeName = "addc1"
			IP = "10.1.1.6"
			Subnet = "DCs"
			Location = "1"
		},
		@{
			Role = "SecondaryDC"	# Don't change
            NodeName = "addc2"
			IP = "10.1.1.7"
			Subnet = "DCs"
			Location = "1"
		},
		@{
			Role = "SecondaryDC"	# Don't change
            NodeName = "addc3"
			IP = "10.2.1.6"
			Subnet = "DCs"
			Location = "2"
		},
		@{
			Role = "SqlWitness"		# Don't change
            NodeName = "sqlwitness"
			IP = "10.1.2.8"
			Subnet = "SQL"
			Location = "1"
		},
		@{
			Role = "PrimarySqlNode"		# Don't change, can only appear once
            NodeName = "sql1"
			IP = "10.1.2.6"
			Subnet = "SQL"
			Location = "1"
			StorageSpaces = @{
				DataDiskSizeGB = 1024
				DataDiskStripes = 8
			}
			Sql = @{
				DbDrive = "X:"
				DbPath = "X:\DATA"
				InstanceName = "sql1"
			}
		}
		@{
			Role = "SecondarySqlNode"		# Don't change
            NodeName = "sql2"
			IP = "10.1.2.7"
			Subnet = "SQL"
			Location = "1"
			StorageSpaces = @{
				DataDiskSizeGB = 1024
				DataDiskStripes = 8
			}
			Sql = @{
				DbDrive = "X:"
				DbPath = "X:\DATA"
				InstanceName = "sql2"
				CommitMode = "Synchronous_Commit"
				FailoverMode = "Automatic"
			}
		}
		@{
			Role = "SecondarySqlNode"		# Don't change
            NodeName = "sql3"
			IP = "10.2.2.6"
			Subnet = "SQL"
			Location = "2"
			StorageSpaces = @{
				DataDiskSizeGB = 1024
				DataDiskStripes = 8
			}			
			Sql = @{
				DbDrive = "X:"
				DbPath = "X:\DATA"
				InstanceName = "sql3"
				CommitMode = "Asynchronous_Commit"
				FailoverMode = "Manual"
			}
		}
	)
}