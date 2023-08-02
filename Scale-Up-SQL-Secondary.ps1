$resourceGroupName = Get-AutomationVariable -Name "ResourceGroup"
$serverNameSecondary = Get-AutomationVariable -Name "ServerNameSecondary"
$elasticPoolName = Get-AutomationVariable -Name "ElasticPoolName"
$MaxDTU = Get-AutomationVariable -Name "MaxDTU"

$serverName = $serverNameSecondary

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

# Using the currentDTU and the availableDTU enum, if the current DTU is not on the highest setting and isn't already set to the $MaxDTU then find the next highest DTU
if($currentDTU -ne [availableDTU]::DTU2000 -and $currentDTU -ne $MaxDTU) {
    $setDTU = [availableDTU]::GetNames([availableDTU]) | Where-Object { [availableDTU]::$_ -gt $currentDTU } | Select-Object -First 1
}
else {
    $setDTU = $MaxDTU
}

Set-AzSqlElasticPool -ResourceGroupName $resourceGroupName -ServerName $serverName -ElasticPoolName $elasticPoolName -Dtu $setDTU -DatabaseDtuMax $setDTU -DatabaseDtuMin $setDTU