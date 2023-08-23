$resourceGroupName = Get-AutomationVariable -Name "ResourceGroup"
$dbResourceGroupName = Get-AutomationVariable -Name "dbResourceGroup"
$serverNameSecondary = Get-AutomationVariable -Name "ServerNameSecondary"
$elasticPoolName = Get-AutomationVariable -Name "ElasticPoolName"
$MinDTU = Get-AutomationVariable -Name "MinDTU"

$serverName = $serverNameSecondary

enum availableDTU {
    DTU125 = 125
    DTU250 = 250
    DTU500 = 500
    DTU1000 = 1000
    DTU1500 = 1500
    DTU2000 = 2000
}

enum maxDatabaseDTU {
    DTU125 = 125
    DTU250 = 250
    DTU500 = 500
    DTU1000 = 1000
    DTU1500 = 1000
    DTU2000 = 1750
}

# Check if there is a deployment in progress, if there is then exit
if ((Get-AzResourceGroupDeployment -ResourceGroupName $dbResourceGroupName | Where-Object {$_.ProvisioningState -eq "Running"}).count -gt 0) {
    Write-Output "Deployment in progress, exiting"
    exit
}

# Get the current DTU
$elasticPool = Get-AzSqlElasticPool -ResourceGroupName $dbResourceGroupName -ServerName $serverName -ElasticPoolName $elasticPoolName
$currentDTU = $elasticPool.Dtu

# Using the currentDTU and the availableDTU enum, if the current DTU is not on the lowest setting and isn't already set to the $MinDTU then find the next lowest DTU
if($currentDTU -ne [availableDTU]::DTU125 -and $currentDTU -ne $MinDTU) {
    $requiredDTU = [availableDTU]::GetNames([availableDTU]) | Where-Object { [availableDTU]::$_ -lt $currentDTU } | Select-Object -Last 1
    $setDTUvalue = [availableDTU]::$requiredDTU.value__
    $setDatabaseDTUvalue = [maxDatabaseDTU]::$requiredDTU.value__
}
else {
    $setDTUvalue = $MinDTU
    $setDatabaseDTUvalue = [maxDatabaseDTU]::([availableDTU]::GetNames([availableDTU]) | Where-Object { [availableDTU]::$_ -eq $MinDTU } | Select-Object -First 1).value__
}

Write-Output "Setting DTU to $setDTUvalue and Database DTU to $setDatabaseDTUvalue"
Set-AzSqlElasticPool -ResourceGroupName $dbResourceGroupName -ServerName $serverName -ElasticPoolName $elasticPoolName -Dtu $setDTUvalue -DatabaseDtuMax $setDatabaseDTUvalue -DatabaseDtuMin $setDatabaseDTUvalue