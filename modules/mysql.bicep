@description('Deploy in VNet')
param vnet bool

@description('Location for all resources.')
param location string

@description('Database administrator login name')
@minLength(1)
param administratorLogin string

@description('Database administrator password')
@minLength(8)
@secure()
param administratorLoginPassword string

@description('Firewall rules')
resource allowAllWindowsAzureIps 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2021-12-01-preview' = if (!vnet) {
    name: 'AllowAllWindowsAzureIps'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
}

@description('Provide the tier of the specific SKU. High availability is available only in the GeneralPurpose and MemoryOptimized SKUs.')
@allowed([
  'Burstable'
  'Generalpurpose'
  'MemoryOptimized'
])
param serverEdition string = 'Burstable'

@description('Provide Server version')
@allowed([
  '5.7'
  '8.0.21'
])
param serverVersion string = '8.0.21'

@description('The availability zone information for the server.')
param availabilityZone string = '1'

@description('Provide the high availability mode for a server: Disabled, SameZone, or ZoneRedundant.')
@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundant'
])
param haEnabled string = 'Disabled'

@description('Provide the availability zone of the standby server.')
param standbyAvailabilityZone string = '2'

param storageSizeGB int = 20
param storageIops int = 360
@allowed([
  'Enabled'
  'Disabled'
])
param storageAutogrow string = 'Enabled'

@description('The name of the sku, e.g. Standard_D32ds_v4.')
param skuName string = 'Standard_B1ms'

param backupRetentionDays int = 7
@allowed([
  'Disabled'
  'Enabled'
])
param geoRedundantBackup string = 'Disabled'

@description('Server Name for Azure database for MySQL')
var serverName = 'ctfd-mysqlserver-${uniqueString(resourceGroup().id)}'

@description('Database Name for Azure database for MySQL')
var databaseName = 'ctfd-mysqldb-${uniqueString(resourceGroup().id)}'

@description('Name of the key vault')
param keyVaultName string

@description('Name of the connection string secret')
param ctfDbSecretName string

@description('Log Anaytics Workspace Id')
param logAnalyticsWorkspaceId string

resource server 'Microsoft.DBforMySQL/flexibleServers@2021-12-01-preview' = {
  location: location
  name: serverName
  sku: {
    name: skuName
    tier: serverEdition
  }
  properties: {
    createMode: 'Default'
    version: serverVersion
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    availabilityZone: availabilityZone
    highAvailability: {
      mode: haEnabled
      standbyAvailabilityZone: standbyAvailabilityZone
    }
    storage: {
      storageSizeGB: storageSizeGB
      iops: storageIops
      autoGrow: storageAutogrow
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: geoRedundantBackup
    }
  }
}

resource database 'Microsoft.DBforMySQL/flexibleServers/databases@2021-12-01-preview' = {
  parent: server
  name: databaseName
  properties: {
    charset: 'utf8'
    collation: 'utf8_general_ci'
  }
}

module privateEndpointModule 'privateendpoint.bicep' = if (vnet) {
  name: 'MySQLPrivateEndpointDeploy'
  params: {
    virtualNetworkName: virtualNetworkName
    subnetName: internalResourcesSubnetName
    resuorceId: server.id
    resuorceGroupId: 'mySQLServer'
    privateDnsZoneName: 'privatelink.mysql.database.azure.com'
    privateEndpointName: 'mysql_private_endpoint'
    location: location
  }
}

module cacheSecret 'keyvaultsecret.bicep' = {
  name: 'MySQLKeyDeploy'
  params: {
    keyVaultName: keyVaultName
    secretName: ctfDbSecretName
    secretValue: 'mysql+pymysql://${administratorLogin}@${serverName}:${administratorLoginPassword}@${serverName}.mysql.database.azure.com/ctfd?ssl_ca=/opt/certificates/DigiCertGlobalRootCA.crt.pem'
  }
}

resource diagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${serverName}-diagnostics'
  scope: server
  properties: {
    logs: [
      {
        category: null
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          days: 5
          enabled: false
        }
      }
    ]
    workspaceId: logAnalyticsWorkspaceId
  }
}
