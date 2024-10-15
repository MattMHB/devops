Import-Module -Name "Functions-AzureDevOps"
Import-Module AzTable

$PAT = Get-AutomationVariable -Name "PAT"
$StorageKey = Get-AutomationVariable -Name "Releases_StorageKey"

$project = Get-AutomationVariable -Name "project"
$organisation = Get-AutomationVariable -Name "organisation"
$StorageAccountName = Get-AutomationVariable -Name "Releases_StorageAccountName"

$organisationUrl = "https://dev.azure.com/$organisation/"
$base64AuthInfo = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($PAT)"))
$urlEncodedProject = [uri]::EscapeDataString($project) 

$StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageKey # Connect to the Storage Account

$tblReleaseDefinitions = (Get-AzStorageTable -Context $StorageContext | where {$_.name -eq "ReleaseDefinitions"}).CloudTable 
$tblReleases = (Get-AzStorageTable -Context $StorageContext | where {$_.name -eq "Releases"}).CloudTable 
$tblApprovedBuilds = (Get-AzStorageTable -Context $StorageContext | where {$_.name -eq "ApprovedBuilds"}).CloudTable 


$mcssReleaseDefinitions = Get-ReleaseDefinitions | Where-Object {$_.name -like "MCSS*" -and $_.name -notlike "*(release)" -and ($_.path -eq "\3.Application" -or $_.path -eq "\2.Database")}

$repos = Get-ListOfRepositoriesFromApprovedBuilds

foreach ($repo in $repos.GetEnumerator())
{
    #clear
    $branches = Get-BranchStats -projectId $repo.Value -repositoryId $repo.Name | Where-Object {$_.Name -notin "main","develop" -and $_.Name -notlike "release*" -and $_.Name -notlike "personal*" -and $_.Name -notlike "unit/mcss-5622-unlinklocations"}
    $repoName = Get-RepositoryNameFromId -projectId $repo.Value -repositoryId $repo.Name
    Write-Host $repoName
    Write-Host "-------------------------------------------------------"
    foreach ($branch in $branches)
    {
        # This might not work if commits are screwed
        if (Check-BranchContainsBranch -projectId $repo.Value -repositoryId $repo.Name -isBranch $branch.name -inBranch "main")
        {
            $branchContainsBranch = $true
        }
        else
        {
            $branchContainsBranch = $false
        }

        $fullBranchName = "refs/heads/"+$branch.name
        $releaseBranch = Get-AzTableRow -table $tblApprovedBuilds  -columnName "sourceBranch" -value $fullBranchName -operator Equal | Select-Object -First 1

        # These are the ones marked as released in the approved releases table
        if ($releaseBranch -ne "" -and $null -ne $releaseBranch)
        {
            $markedAsReleased = $true
        }
        else
        {
            $markedAsReleased = $false
        }

        # Edit this as req
        if (($markedAsReleased -eq $true) -or ($(Get-DaysSince $branch.commit.author.date) -gt 45))
        {
            Delete-Branch -projectId $repo.Value -repositoryId $repo.Name -branchName $branch.name
            Write-Host "Deleted - $($branch.name) in $($repoName) - $(Get-DaysSince $branch.commit.author.date) days"  
        }
        else
        {
            Write-Host "Not Deleted - $($branch.name) in $($repoName) - $(Get-DaysSince $branch.commit.author.date) days"
        }
    }
    Write-Host ""
}