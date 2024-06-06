# Import the module
Import-Module -Name "Functions-ReleaseProcess"

Clear-Host # Clear the console window

param (
    [string]$PAT = Get-AutomationVariable -Name "PAT",
    [string]$project = Get-AutomationVariable -Name "project",
    [string]$organisation = Get-AutomationVariable -Name "organisation",
    [boolean]$openAllReleases = Get-AutomationVariable -Name "openAllReleases",
    [boolean]$listOnly = Get-AutomationVariable -Name "listOnly"
)

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

Write-Host "Opening the following websites in Chrome:"
$websiteList | ForEach-Object {
    Write-Host $_.Name
}

Write-Host
Write-Host "Excluded websites:"

$excludedList | ForEach-Object {
    Write-Host $_.Name
}

if ($listOnly -eq $true) {
    break
}

# Open the websites in Chrome
$argumentList = "--new-window "
$sortedWebsites | ForEach-Object {
    $argumentList += $_.Url + " "
}
Start-Process -FilePath Chrome -ArgumentList $argumentList
