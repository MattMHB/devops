function Get-ReleaseDefinitions {    
    
    $url = "https://vsrm.dev.azure.com/$organisation/$urlEncodedProject/_apis/release/definitions?api-version=7.1-preview.4"
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"
    
    return $result.value
}

function Get-ReleasesForDefinitionId {
    param ($definitionId)
    
    $url = "https://vsrm.dev.azure.com/$organisation/$urlEncodedProject/_apis/release/releases?api-version=7.0&queryOrder=descending&definitionId=$definitionId"    
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"
    
    return $result.value
}

function Get-ReleaseForReleaseId {
    param ($releaseId)
    
    $url = "https://vsrm.dev.azure.com/$organisation/$urlEncodedProject/_apis/release/releases/$releaseId"
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"
    
    return $result
}

# Import the module
#Import-Module -Name "Functions-AzureDevOps"

$PAT = Get-AutomationVariable -Name "PAT"
$project = Get-AutomationVariable -Name "project"
$organisation = Get-AutomationVariable -Name "organisation"
$openAllReleases = Get-AutomationVariable -Name "openAllReleases"
$listOnly = Get-AutomationVariable -Name "listOnly"


$organisationUrl = "https://dev.azure.com/$organisation/"
$base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($PAT)"))
$urlEncodedProject = [uri]::EscapeDataString($project) 

# Object to hold website URLs
$websites = New-Object -TypeName PSObject

# Object to hold website URLs
$excluded = New-Object -TypeName PSObject

#$mcssReleaseDefinitions = Get-ReleaseDefinitions | Where-Object {$_.name -like "MCSS-PdfGenerator-CD-(Release)"}
$mcssReleaseDefinitions = Get-ReleaseDefinitions | Where-Object { $_.name -like "*(release)" }

# Get the last 5 releases for each release definition
ForEach ($mcssReleaseDefinition in $mcssReleaseDefinitions) {
    
    if ($openAllReleases) {
        $releaseInProgress = $true
    }
    else {
        foreach ($release in (Get-ReleasesForDefinitionId ($mcssReleaseDefinition.id) | Sort-Object -Property id -Descending | Select-Object -First 1)) {
            $releaseInProgress = $false
            $releaseDetail = Get-ReleaseForReleaseId ($release.id)
            $environments = @($releaseDetail.environments | Where-Object { $_.status -notin @("succeeded", "canceled", "notStarted", "rejected") })   # Maybe just change to -eq inProgress???
            if ($environments.count -gt 0) {
                $releaseInProgress = $true
                break
            }
        }
    }

    # If the release is in progress, then we add the website to the list
    if ($releaseInProgress) {
        $websites | Add-Member -MemberType NoteProperty -Name $mcssReleaseDefinition.name -Value $mcssReleaseDefinition._links.web.href
    }
    else {
        $excluded | Add-Member -MemberType NoteProperty -Name $mcssReleaseDefinition.name -Value $mcssReleaseDefinition._links.web.href
    }
}

# Convert the websites object to a list of objects
$websiteList = $websites.PSObject.Properties | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Url  = $_.Value
    }
}

$excludedList = $excluded.PSObject.Properties | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Name
        Url  = $_.Value
    }
}


# Sort the websites by name, but put the DB websites at the top and api, website or authentication at the bottom
$sortedWebsites = $websiteList | Sort-Object {
    if ($_.Name -like '*DB-*') {
        0
    }
    elseif ($_.Name -like '*api*' -or $_.Name -like '*website*' -or $_.Name -like '*authentication*') {
        3
    }
    elseif ($_.Name -like '*cronjob*') {
        2
    }
    else {
        1
    }
}

Write-Output "Opening the following websites in Chrome:"
$websiteList | ForEach-Object {
    Write-Output $_.Name
}

Write-Output
Write-Output "Excluded websites:"

$excludedList | ForEach-Object {
    Write-Output $_.Name
}

if ($listOnly -eq $true) {
    break
}
else {
    # Open the websites in Chrome
    $argumentList = "--new-window "
    $sortedWebsites | ForEach-Object {
        $argumentList += $_.Url + " "
    }
    Start-Process -FilePath Chrome -ArgumentList $argumentList
}

