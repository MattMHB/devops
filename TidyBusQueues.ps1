param (
    [string]$subscriptionName,
    [string]$resourceGroupName,
    [string]$namespaceName
)

$systemManagedIdentityId = Get-AutomationVariable -Name "systemManagedIdentityId"
$tenantId = Get-AutomationVariable -Name "TenantId"

# Login to Azure
try
{ 
    "Logging in to Azure..." 
    Connect-AzAccount -Identity -AccountId $systemManagedIdentityId
} 
catch { 
    Write-Error -Message $_.Exception 
    throw $_.Exception 
}

# Set context to the correct subscription
Set-AzContext -SubscriptionName "$subscriptionName" -Tenant "$tenantId"

# Get all queues in the namespace
$queues = Get-AzServiceBusQueue -ResourceGroupName $resourceGroupName -NamespaceName $namespaceName

# List to store error queues with more than 1000 messages
$errorQueues = @()

foreach ($queue in $queues) {
    # Get the queue details
    $queueDetails = Get-AzServiceBusQueue -ResourceGroupName $resourceGroupName -NamespaceName $namespaceName -Name $queue.Name

    if ($queueDetails.MessageCount -gt 1000) {
        $errorQueues += $queue.Name
    }
}

if ($errorQueues.Count -gt 0) {
    Write-Output "Error queues with more than 1000 messages:"
    $errorQueues | ForEach-Object { Write-Output $_ }
} else {
    Write-Output "No error queues with more than 1000 messages found."
}

foreach ($queue in $queues) {
    # Get the queue details
    $queueDetails = Get-AzServiceBusQueue -ResourceGroupName $resourceGroupName -NamespaceName $namespaceName -Name $queue

    if ($queueDetails) {
        # Purge the queue by receiving and discarding all messages
        while ($true) {
            $messages = Receive-AzServiceBusQueueMessage -ResourceGroupName $resourceGroupName -NamespaceName $namespaceName -QueueName $queue -MaxMessageCount 100 -PeekLock

            if ($messages.Count -eq 0) {
                break
            }

            foreach ($message in $messages) {
                Complete-AzServiceBusQueueMessage -ResourceGroupName $resourceGroupName -NamespaceName $namespaceName -QueueName $queue -LockToken $message.LockToken
            }
        }

        Write-Output "Purged all messages from queue: $queue"
    } else {
        Write-Output "Queue $queue not found."
    }
}

Write-Output "Purge operation completed."