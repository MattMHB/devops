$resourceGroupName = Get-AutomationVariable -Name "ResourceGroup"
$serverNamePrimary = Get-AutomationVariable -Name "ServerNamePrimary"
$elasticPoolName = Get-AutomationVariable -Name "ElasticPoolName"
$MinDTU = Get-AutomationVariable -Name "MinDTU"

$serverName = $serverNamePrimary

enum availableDTU {
    DTU125 = 125
    DTU250 = 250
    DTU500 = 500
    DTU1000 = 1000
    DTU1500 = 1500
    DTU2000 = 2000
}


# Get the current DTU
$elasticPool = Get-AzSqlElasticPool -ResourceGroupName $resourceGroupName -ServerName $serverName -ElasticPoolName $elasticPoolName
$currentDTU = $elasticPool.Dtu

# Using the currentDTU and the availableDTU enum, if the current DTU is not on the lowest setting and isn't already set to the $MinDTU then find the next lowest DTU
if($currentDTU -ne [availableDTU]::DTU125 -and $currentDTU -ne $MinDTU) {
    $setDTU = [availableDTU]::GetNames([availableDTU]) | Where-Object { [availableDTU]::$_ -lt $currentDTU } | Select-Object -Last 1
}
else {
    $setDTU = $MinDTU
}

Set-AzSqlElasticPool -ResourceGroupName $resourceGroupName -ServerName $serverName -ElasticPoolName $elasticPoolName -Dtu $setDTU -DatabaseDtuMax $setDTU -DatabaseDtuMin $setDTU