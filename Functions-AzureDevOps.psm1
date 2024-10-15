
# Populate and update the build approvals table
function Populate-BuildApprovals-Table {
    $releases = Get-AzTableRow -table $tblReleases

    # Go through each release to identify the builds 
    # which have or are due to be approved
    foreach ($release in $releases)
    {
    try{

            ##  DONT CHECK IN
            <#
            if ($release.name -ne "Release-1033")
            {
                continue
            }
            else
            {
                Write-Host "found it"
            }
            #>

        try
        {
            $releaseDetail = Get-ReleaseForReleaseId $release.RowKey
        }
        catch
        {
            if(-NOT $_.ErrorDetails.Message -like "*ReleaseNotFoundException*")
            {
                throw
            }
            else
            {
                Write-Host "Deleting release" $release.RowKey". Release no longer available"
                $release | Remove-AzTableRow -table $tblReleases
            }

            continue
        }

        # The build might be from either mcss or intersoft-dev-common project so we need to grab this
        # to use in the url when we grab the build and PR details
        $projectReferenceId = ($releaseDetail.artifacts.definitionReference | Where-Object {$_.definition -NotLike "*knmanifest*"}).project.id

        # Get the build info for the main artifact (not the knmanifest)
        $build = ($releaseDetail.artifacts.definitionReference | Where-Object {$_.definition -NotLike "*knmanifest*"}).version

        # If there is not a test environment (i.e. A release pipeline). These should be 
        # filtered out before this point
        if (($releaseDetail.environments | Where-Object {$_.name -eq "TestingComplete"}) -eq $null)
        {
            Write-Host "Skipping release "$release.RowKey". No TestingComplete environment exists"
            continue
        }

        # If the status of the test environment release is in the list then skip this release
        # These releases could have failed testing, been release by accident (cancelled) or released to a specific environment
        # which isn't the test environment
        if (($releaseDetail.environments | Where-Object {$_.name -eq "TestingComplete"}).status -in "inProgress", "pending", "notStarted", "rejected")
        {
            Write-Host "Skipping release "$release.RowKey". Not yet approved"
            continue
        }

        # Get the pre deployment approvals section
        $testEnvironmentApprovals = ($releaseDetail.environments | Where-Object {$_.name -eq "TestingComplete"} ).preDeployApprovals        

        # The list of approval dates. There can be multiple approval dates and we want the latest try
        $approvalDates = ($testEnvironmentApprovals | Where-Object {$_.status -eq "approved"}) | Sort-Object -Property trialNumber -Descending
        
        # If there is no approval date then blank out the variable else
        # take the latest approval date and set the pending date to the same
        if ($approvalDates -eq $null)
        {
            $approvedOnDate = ""
        }
        else
        {
            $approvedOnDate = $approvalDates[0].modifiedOn
        }

        # Get the row from the ApprovedBuilds table
        $approvedBuildRow = Get-AzTableRow -table $tblApprovedBuilds  -columnName "buildid" -value $build.id -operator Equal
        
        #($testEnvironmentApprovals | Where-Object {$_.status -eq "approved"})

        #If we don't already have an approval build row stored then add it
        #If we do have it without an approval date and now there is an approval date
        #update the approval date
        if($null -eq $approvedBuildRow)
        {
            $buildInfo = Get-BuildForBuildId $projectReferenceId $build.id
            $pullRequests = (Get-PullRequests $projectReferenceId $buildInfo.repository.id).value
            $pullRequest = $pullRequests | Where-Object {$_.lastMergeCommit.commitId -eq $buildInfo.sourceVersion}

            # If there is no pull request then this is a 
            # manual build
            if ($pullRequest -ne $null)
            {
                Add-AzTableRow `
                        -table $tblApprovedBuilds `
                        -partitionKey $release.RowKey `
                        -rowKey ($build.id) -property @{
                                                         "approvedDate"=$approvedOnDate;                                                    
                                                         "buildid"=$build.id;
                                                         "buildname"=$build.name;
                                                         "repositoryName"=$buildInfo.repository.name;
                                                         "repositoryId"=$buildInfo.repository.id;
                                                         "prDescription"=(iif ($pullRequest.description -eq $null) "No description" $pullRequest.description);
                                                         "commitId"=$buildInfo.sourceVersion;
                                                         "pullRequestId"=$pullRequest.pullRequestId;
                                                         "sourceBranch"=$pullRequest.sourceRefName;
                                                         "releasePullDate"="";
                                                         "releaseBranch"=""
                                                        }
                Write-Host "Added release" $release.RowKey

            }
        }                       
        else 
        {
            if($approvedBuildRow.approvedDate -eq "" -and $approvedOnDate -ne "")
            {
                $approvedBuildRow.approvedDate = $approvedOnDate
                $approvedBuildRow | Update-AzTableRow -table $tblApprovedBuilds

                Write-Host "Updating release" $release.RowKey". Approved"
            }
        }
        }
        catch
        {
            Write-Host "Error processing release" $release.RowKey
        }        
    }
}

Function iif($If, $IfTrue, $IfFalse) {
    If ($If) {If ($IfTrue -is "ScriptBlock") {&$IfTrue} Else {$IfTrue}}
    Else {If ($IfFalse -is "ScriptBlock") {&$IfFalse} Else {$IfFalse}}
}

function Populate-Releases-Table {
    foreach ($releaseDefinition in $mcssReleaseDefinitions)
    {
        $releaseDefinitionName = $releaseDefinition.name
        $releasesForDefinition = Get-ReleasesForDefinitionId $releaseDefinition.id

        Write-Host "Retrieved "$releasesForDefinition.Count" releases definitionId "$releaseDefinition.id

        foreach ($release in $releasesForDefinition)
        {
            $releaseName = $release.name
            if ((Get-AzTableRow -table $tblReleases -partitionKey $releaseDefinition.id -RowKey $release.id) -eq $null)
            {
                Add-AzTableRow `
                    -table $tblReleases `
                    -partitionKey $releaseDefinition.id `
                    -rowKey ($release.id) -property @{"name"=$release.name;"createdOn"=$release.createdOn;"createdBy"=$release.createdBy.uniqueName;"url"=$release.url}

                Write-Output "Added $releaseDefinitionName : $releaseName to releases table"
            }
            else
            {
                Write-Output "Skipping $releaseDefinitionName : $releaseName. Already exists"
            }
        }
    }
}


function Populate-ReleaseDefinitions-Table {
    foreach ($releaseDefinition in $mcssReleaseDefinitions)
    {
        $releaseDefinitionName = $releaseDefinition.name
        if ((Get-AzTableRow -table $tblReleaseDefinitions -partitionKey "1" -RowKey $releaseDefinition.id) -eq $null)
        {
            Add-AzTableRow `
                -table $tblReleaseDefinitions `
                -partitionKey "1" `
                -rowKey ($releaseDefinition.id) -property @{"name"=$releaseDefinition.name;"url"=$releaseDefinition.url}

            Write-Output "Added $releaseDefinitionName to release definitions table"
        }
        else
        {
            Write-Output "Skipping $releaseDefinitionName Already exists"
        }
    }
}

# Go through ApprovedBuilds and get a hashtable
# of repository Ids and the project id they belong to
# Name = RepositoryId, Value = ProjectId
function Get-ListOfRepositoriesFromApprovedBuilds
{
    $repositoryNames = @{}
    $populatedRepositoryNames = @{}
    $releaseRows = Get-AzTableRow -Table $tblApprovedBuilds

    foreach ($row in $releaseRows)
    {
        if (-NOT $repositoryNames.ContainsKey($row.repositoryName))
        {
            $repositoryNames.Add($row.repositoryName,"")
        }
        
    }

    foreach ($repositoryName in $repositoryNames.Keys)
    {        
        $customFilter = "(repositoryName eq '$repositoryName')"
        $rows = Get-AzTableRow -table $tblApprovedBuilds -ColumnName "repositoryName" -Operator Equal -Value $repositoryName

        $row = $rows | Sort-Object -Property pullRequestId -Descending | Select-Object -First 1

        $populatedRepositoryNames.Add($row.repositoryId, (Get-ProjectIdFromReleaseId $row.PartitionKey))
    }


    return $populatedRepositoryNames
}

function Get-PullRequests {
    param ($projectReferenceId, $repositoryId)

    $url = "https://dev.azure.com/$organisation/$projectReferenceId/_apis/git/repositories/$repositoryId/pullrequests?api-version=7.0&searchCriteria.status=all"    
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"

    return $result
}

function Get-Commit {
    param ($repositoryId, $commitId)
    
    $url = "https://dev.azure.com/$organisation/$urlEncodedProject/_apis/git/repositories/$repositoryId/commits/$commitId"+"?api-version=7.0"    
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"

    return $result
}

function Get-BuildForBuildId {
    param ($projectReferenceId, $buildId)
    
    $url = "https://dev.azure.com/$organisation/$projectReferenceId/_apis/build/builds/$buildId"+"?api-version=7.0"    
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"
    
    return $result
}

function Get-ProjectIdFromReleaseId {
    param ($releaseId)
    
    $release = Get-ReleaseForReleaseId $releaseId

    $result = ($release.artifacts.definitionReference | Where-Object {$_.definition -NotLike "*knmanifest*"}).project.id
    
    return $result
}

function Get-ReleaseForReleaseId {
    param ($releaseId)
    
    $url = "https://vsrm.dev.azure.com/$organisation/$urlEncodedProject/_apis/release/releases/$releaseId"
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"
    
    return $result
}


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

# The most you can get in 1 go is 100 using the top option which is not enough
function Get-Releases {
    
    $url = "https://vsrm.dev.azure.com/$organisation/$urlEncodedProject/_apis/release/releases?api-version=7.0"
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"
    
    return $result.value
}


function Get-Projects {
    
    $url = "https://dev.azure.com/$organisation/_apis/projects?api-version=7.0"
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"
    
    return $result.value
}

function Get-RepositoriesForProjectId {
    param($projectId)
    
    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories?api-version=7.0"
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"
    
    return $result.value
}

function Get-RepositoryId-From-RepositoryName
{
    param($organisation, $projectName, $repositoryName)

    $urlEncodedProject = [uri]::EscapeDataString($projectName) 

    $url = "https://dev.azure.com/$organisation/$urlEncodedProject/_apis/git/repositories?api-version=7.0"
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"

    $repository = $result.value | Where-Object {$_.name -eq $repositoryName}

    return $repository.id
}

function Get-ProjectIdForRepositoryId {
    param($repositoryId)

    Get-Projects | ForEach-Object { 
                                if ((Get-RepositoriesForProjectId $_.id | Where-Object {$_.Id -eq $repositoryId}) -ne $null) 
                                { return $_.Id } 
                              }
}

function Get-ProjectName-From-ProjectId
{
    param($projectId)

    Get-Projects | ForEach-Object { 
                                if ($_.Id -eq $projectId) 
                                { return $_.name } 
                              }
}

function Get-ProjectId-From-ProjectName
{
    param($projectName)

    Get-Projects | ForEach-Object { 
                                if ($_.name -eq $projectName) 
                                { return $_.Id } 
                              }
}

# Work out the next release number to use based on the date and the last release number
function Get-NextReleaseNumber
{
    param($currentReleaseNumber)

    if ($currentReleaseNumber -like (Get-Date -Format yyyy.MM.dd)+"*")
    {
        return (Get-Date -Format yyyy.MM.dd)+"."+([int]($currentReleaseNumber.Split("."))[3]+1).ToString()
    }
    else
    {
        return (Get-Date -Format yyyy.MM.dd)+".0"
    }

}

# Get the current release number from the variable group
function Get-CurrentReleaseNumber
{
    param($project = "DevOps")

    $urlEncodedProject = [uri]::EscapeDataString($project)
    $variableGroup = ((az pipelines variable-group list --org $organisationUrl --project $project --output json --only-show-errors) | ConvertFrom-json) | Where-Object {$_.name -eq "AutomatedReleases"}

    $groupId = $variableGroup.id
    $url = "https://dev.azure.com/$organisation/$urlEncodedProject/_apis/distributedtask/variablegroups/$groupId" + "?api-version=7.0"
    $result=Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json" 

    return $result.variables.currentRelease.value
}

# Update the variable group with the new release number
function Update-CurrentReleaseNumber
{
    param($newReleaseNumber, $project = "DevOps")

    $urlEncodedProject = [uri]::EscapeDataString($project)
    $variableGroup = ((az pipelines variable-group list --org $organisationUrl --project $project --output json --only-show-errors) | ConvertFrom-json) | Where-Object {$_.name -eq "AutomatedReleases"}

    $groupId = $variableGroup.id
    $url = "https://dev.azure.com/$organisation/$urlEncodedProject/_apis/distributedtask/variablegroups/$groupId" + "?api-version=7.0"
    $result=Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json" 

    $result.variables.currentRelease.value = $newReleaseNumber

    $body = $result | ConvertTo-Json -Depth 10
    $updateurl = "https://dev.azure.com/$organisation/$urlEncodedProject/_apis/distributedtask/variablegroups/$groupId" + "?api-version=7.0"

    Invoke-RestMethod -Uri $updateurl -Headers @{Authorization = "Basic {0}" -f $base64AuthInfo} -ContentType "application/json" -Method put -Body $body
}

# Update the variable group setting mergeToMain which is the variable to determine if the merge to main process runs
function Set-MergeToMain
{
    param($value, $project = "DevOps")

    $urlEncodedProject = [uri]::EscapeDataString($project)
    $variableGroup = ((az pipelines variable-group list --org $organisationUrl --project $project --output json --only-show-errors) | ConvertFrom-json) | Where-Object {$_.name -eq "AutomatedReleases"}

    $groupId = $variableGroup.id
    $url = "https://dev.azure.com/$organisation/$urlEncodedProject/_apis/distributedtask/variablegroups/$groupId" + "?api-version=7.0"
    $result=Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json" 

    $result.variables.mergeToMain.value = $value

    $body = $result | ConvertTo-Json -Depth 10
    $updateurl = "https://dev.azure.com/$organisation/$urlEncodedProject/_apis/distributedtask/variablegroups/$groupId" + "?api-version=7.0"

    Invoke-RestMethod -Uri $updateurl -Headers @{Authorization = "Basic {0}" -f $base64AuthInfo} -ContentType "application/json" -Method put -Body $body
}

function Create-PullRequestFromTag
{
    param($projectId, $repositoryId, $sourceBranch, $sourceTag, $targetBranch, $title, $description, $deleteSourceBranch = "false")

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/pullrequests?api-version=7.0"

    # Get the commit ID for the tag
    $tagUrl = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/refs?filter=tags/$sourceTag&api-version=7.0"
    $tagResponse = Invoke-RestMethod -Uri $tagUrl -ContentType "application/json" -headers $headers -Method GET
    $tagCommitId = $tagResponse.value[0].objectId

    $body = 
    @{
        sourceRefName = "refs/heads/$sourceBranch"
        targetRefName = "refs/heads/$targetBranch"
        title = $title
        description = $description
        commitId = $tagCommitId  # Use the commit ID of the tag
        deleteSourceBranch = $deleteSourceBranch
        completionOptions = 
        @{ 
            mergeStrategy = "noFastForward"
         }
    } | ConvertTo-Json -Depth 5

    try
    {
        $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -Body $body -headers $headers -Method POST
        return $response.pullRequestId
    }
    catch 
    {
        if(-NOT $_.ErrorDetails.Message -like "*GitPullRequestExistsException*")
        {
            throw
        }
    }
}

function Create-PullRequest
{
    param($projectId, $repositoryId, $sourceBranch, $targetBranch, $title, $description, $deleteSourceBranch = "false")

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/pullrequests?api-version=7.0"

    $body = 
    @{
        sourceRefName = "refs/heads/$sourceBranch"
        targetRefName = "refs/heads/$targetBranch"
        title = $title
        description = $description

        deleteSourceBranch = $deleteSourceBranch
        completionOptions = 
        @{ 
            mergeStrategy = "noFastForward"
        
         }
    } | ConvertTo-Json -Depth 5

    try
    {
        $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -Body $body -headers $headers -Method POST
        return $response.pullRequestId
    }
    catch 
    {
        if(-NOT $_.ErrorDetails.Message -like "*GitPullRequestExistsException*")
        {
            throw
        }
    }
}

function Set-PullRequestAutoComplete
{
    param($projectId, $repositoryId, $pullRequestId, $reviewerId, $deleteSourceBranch = "false")

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId"+"?api-version=7.0"

    $body = @{
            deleteSourceBranch = $deleteSourceBranch
            completionOptions = 
                @{ 
                    mergeStrategy = "noFastForward"
        
                 }
                autoCompleteSetBy =
                @{ 
                    id = "$reviewerId"       
                 }
            } | ConvertTo-Json -Depth 5        

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -Body $body -headers $headers -Method PATCH
}

function Approve-PullRequest
{
    param($projectId, $repositoryId, $pullRequestId, $reviewerId)

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId/reviewers/$reviewerId"+"?api-version=5.0" 

    $body = '{"vote": 10}'       

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -Body $body -headers $headers -Method PUT
}

function Abandon-PullRequest
{
    param($projectId, $repositoryId, $pullRequestId, $reviewerId)

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/pullRequests/$pullRequestId"+"?api-version=7.0"

    $body = @{
            Status = "abandoned"
            } | ConvertTo-Json -Depth 5        

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -Body $body -headers $headers -Method PATCH
}

function Check-BranchExists
{
    param($projectId, $repositoryId, $branchName)
    
    $response = Get-BranchStats -projectId $projectId -repositoryId $repositoryId | Where-Object {$_.name -eq $branchName}

    return $response -ne $null
}


function Get-ReleaseBranch
{
    param($projectId, $repositoryId)
    
    $response = Get-BranchStats -projectId $projectId -repositoryId $repositoryId | Where-Object {$_.name -like "release/*"}

    if ($response.Count -gt 1)
    {
        throw "More than 1 release branch exists"
    }

    return $response.name
}

# Get the latest release branch name
function Get-LatestReleaseBranchName
{
    param($projectId, $repositoryId)

    $response = Get-BranchStats -projectId $projectId -repositoryId $repositoryId | Where-Object {$_.name -like "release/*"} | Sort-Object -Property name -Descending

    if ($response.Count -eq 0) {
        return $null
    }

    return $response[0].name
}

# Get the latest hotfix branch name
function Get-LatestHotfixBranchName
{
    param($projectId, $repositoryId)

    $response = Get-BranchStats -projectId $projectId -repositoryId $repositoryId | Where-Object {$_.name -like "hotfix/*"} | Sort-Object -Property name -Descending

    if ($response.Count -eq 0) {
        return $null
    }

    return $response[0].name
}

# Check that the last commit datetime is before the release creation datetime for the branch
function Check-NoAdditionalCommits
{
    param($projectId, $repositoryId, $branchName, $releaseId)    

    $lastCommitDatetime = (Get-CommitsForBranch -projectId $projectId -repositoryId $repositoryId -branch $branchName)[0].author.date
    $releaseCreatedOnDatetime = (Get-ReleaseForReleaseId $releaseId).createdOn

    if ((NEW-TIMESPAN –Start $releaseCreatedOnDatetime –End $lastCommitDatetime).Seconds -gt 0)
    {
	    return $false
    }
    else
    {
	    return $true
    }
}


function Check-BranchNotAhead
{
    param($projectId, $repositoryId, $branchName)    


    if ((Get-BranchStats -projectId $projectId -repositoryId $repositoryId | Where-Object {$_.name -eq $branchName}).aheadCount -eq 0)
    {
	    return $true
    }
    else
    {
	    return $false
    }
}

function Create-ReleaseBranch
{
    param($projectId, $repositoryId, $branchName, $baseBranch = "main")    

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    # Get ID of the base branch
    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/refs?filter=heads/$baseBranch&api-version=5.1"
    $baseBranchResponse = (Invoke-RestMethod -Uri $url -ContentType "application/json" -headers $headers -Method GET).value | Where-Object {$_.name -eq "refs/heads/$baseBranch"}   

    # Create a new branch
    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/refs?api-version=5.1"
    $body = ConvertTo-Json @(
    @{
        name = "refs/heads/$branchName"
        newObjectId = $baseBranchResponse.objectId
        oldObjectId = "0000000000000000000000000000000000000000"
    })

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -Body $body -headers $headers -Method POST
}

function Remove-RefsHeads{
    param($branch)

    $result = ($branch).substring(11,($branch).Length-11)

    return $result
}

function LockBranch
{
    param($projectId, $repositoryId, $branch, $isLocked)    

    if ($isLocked -eq $true)
    {
        $body = '{"isLocked": true}'
    }
    else
    {
        $body = '{"isLocked": false}'
    }

    $branch = "heads/" + $branch

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    # Create a new branch
    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/refs?filter=$branch&api-version=7.0"        

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -Body $body -headers $headers -Method PATCH

    return $response
}

function Get-CommitsForBranch
{
    param($projectId, $repositoryId, $branch)    

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/commits?searchCriteria.showOldestCommitsFirst=false&searchCriteria.itemVersion.version=$branch&api-version=7.1-preview.1"        

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -headers $headers -Method GET

    return $response.value
}

function Check-BranchContainsBranch
{
    param($projectId, $repositoryId, $isBranch, $inBranch)    

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/diffs/commits?baseVersion=$isBranch&targetVersion=$inBranch&api-version=7.1-preview.1"        

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -headers $headers -Method GET

    if ($response.behindCount -eq 0)
    {
        return $true
    }
    else
    {
        return $false
    }
}

function Get-BranchStats
{
    param($projectId, $repositoryId)    

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/stats/branches?api-version=6.1-preview.1"        

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -headers $headers -Method GET

    return $response.value
}

function Get-PullRequestById
{
    param($projectId, $pullRequestId)    

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/pullrequests/$($pullRequestId)?api-version=7.1-preview.1"        

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -headers $headers -Method GET

    return $response
}

function Delete-Branch
{
    param($projectId, $repositoryId, $branchName)    

    $branch = "refs/heads/"+$branchName

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    # Get ID of the branch
    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/refs?filter=heads/$branchName&api-version=4.1"
    $branchObjectId = ((Invoke-RestMethod -Uri $url -ContentType "application/json" -headers $headers -Method GET).value | Where-Object {$_.name -eq $branch}).objectId

    if ($branchObjectId -eq $null)
    {
        $errorMessage = "The branch "+ $branch + " doesn't exist"
        throw $errorMessage
    }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/refs?api-version=7.1-preview.1"        

    $body =
    @{
        name = $branch
        oldObjectId = $branchObjectId
        newObjectId = "0000000000000000000000000000000000000000"
    } | ConvertTo-Json -Depth 5

    $body = '['+$body+']'

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -headers $headers -Body $body -Method POST

    return $response.value
}

function Set-BranchTag
{
    param($projectId, $repositoryId, $branchName, $tag, $description)

    $branch = "refs/heads/"+$branchName

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    # Get ID of the branch
    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/refs?filter=heads/$branchName&api-version=4.1"
    $branchObjectId = (Invoke-RestMethod -Uri $url -ContentType "application/json" -headers $headers -Method GET).value.objectId

    if ($branchObjectId -eq $null)
    {
        $errorMessage = "The branch "+ $branch + " doesn't exist"
        throw $errorMessage
    }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/annotatedtags?api-version=7.0"

    $body = 
    @{
        name = $tag
        taggedObject = @{
                            objectId = $branchObjectId
                        }
        message = $description
    } | ConvertTo-Json -Depth 5

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -headers $headers -Body $body -Method POST

    return $response.value
}

function Get-RepositoryNameFromId
{
    param($projectId, $repositoryId)    

    $headers = @{ Authorization = "Basic $base64AuthInfo" }

    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId"+"?api-version=6.1-preview.1"

    $response = Invoke-RestMethod -Uri $url -ContentType "application/json" -headers $headers -Method GET

    return $response.name
}

function Get-RoleDefinitions {    
    
    $url = "https://vsrm.dev.azure.com/$organisation/$urlEncodedProject/_apis/release/definitions?api-version=7.1-preview.4"
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"
    
    return $result.value
}

function Get-All-Refs {
    param ($organisation, $projectId, $repositoryId)
    $url = "https://dev.azure.com/$organisation/$projectId/_apis/git/repositories/$repositoryId/refs?api-version=5.1"
    $result = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"

    return $result.value
}

function Get-All-Branches {
    param ($organisation, $projectId, $repositoryId)
    
    $url="https://dev.azure.com/intersoft-uk/$projectId/_apis/sourceProviders/tfsgit/branches?repository=$repositoryId"+"&api-version=5.1"

    $branches = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"

    return $branches.value
}


function Get-All-Branch-Stats {
    param ($organisation, $projectId, $repositoryId)
    
    $url="https://dev.azure.com/intersoft-uk/_apis/git/repositories/$repositoryId/stats/branches?api-version=6.1-preview.1"

    $branchStats = Invoke-RestMethod -Uri $url -Headers @{Authorization = ("Basic {0}" -f $base64AuthInfo)} -Method get -ContentType "application/json"

    return $branchStats.value

}

# Function to get pipelines for a specific repository
function Get-PipelinesForRepo {
    param(
        [string]$ProjectName,
        [string]$RepoName
    )
    
    $pipelines = az pipelines list --project $ProjectName --repository $RepoName --output json | ConvertFrom-Json
    return $pipelines
}

# Function to get all repositories and pipelines
function Get-AllReposAndPipelines {
    param (
        [string[]]$ProjectNames = @("MCSS","Intersoft Common Services")
    )

    # Initialize an empty array to store the pipeline objects
    $allPipelines = @()

    # Loop through each project
    foreach ($project in $ProjectNames) {
        Write-Host "Processing project: $project"
        
        # Get all repositories for the project
        $repos = (az repos list --project $project --output json | ConvertFrom-Json) | Where-Object { $_.name -notin "mcss-backupx","mcss-certificateautomation", "mcss-devops", "mcss-infrastructure", "devops", "intersoft-nuget-library", "visual-studio-templates", "intersoft-setup"}
        
        # Loop through each repository
        foreach ($repo in $repos) {
            Write-Host "Processing repository: $($repo.name)"
            
            # Get pipelines for the repository
            $pipelines = Get-PipelinesForRepo -ProjectName $project -RepoName $repo.name
            
            # Add pipeline objects to the array
            foreach ($pipeline in $pipelines) {
                $pipelineObject = [PSCustomObject]@{
                    ProjectName = $project
                    RepoName = $repo.name
                    RepoId = $repo.id
                    PipelineName = $pipeline.name
                    PipelineId = $pipeline.id
                }
                $allPipelines += $pipelineObject
            }
        }
    }    

    return $allPipelines
}

function Get-DaysSince {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DateString
    )

    try {
        # Parse the input date string using the correct format
        $date = [DateTime]::ParseExact($DateString, "MM/dd/yyyy HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)

        # Get the current date
        $currentDate = Get-Date

        # Calculate the difference in days
        $daysPassed = ($currentDate - $date).Days

        return $daysPassed
    }
    catch {
        Write-Error "Error processing date: $_"
        return $null
    }
}

