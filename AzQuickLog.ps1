<#
.Synopsis
A lightweight script for managing Azure resource diagnostic logs

.DESCRIPTION
A script used to remove the Diagnostic Settings for a particular Azure Resource or set of resources.
As part of the removal process, the report will log the following information:
    - Azure Resource Name
    - Diagnostic Settings Name
    - Removal Status
    - Storage account Name
    - Log Analytics Workspace
    - Event Hub Namespace

.Notes
Version   : 2.0
Author    : Luke Tyler Williams
Twitter   : @LT_Williams
Disclaimer: Please use this script at your own discretion, the author is not responsible for any result
Credits: Credits to Charbel Nemnom for logic around diagnostics setting removal // @CharbelNemnom // https://charbelnemnom.com

.PARAMETER scope
Specify the scope to which you are trying to select
#>
param (
    [Parameter()]
    [string]$scope,

    [Parameter()]
    [string]$scopeId,

    [Parameter()]
    [string]$dsName,

    [Parameter()]
    [string]$target
)

Write-Host '
$$$$$$\             $$$$$$\            $$\           $$\       $$\                          
$$  __$$\           $$  __$$\           \__|          $$ |      $$ |                         
$$ /  $$ |$$$$$$$$\ $$ /  $$ |$$\   $$\ $$\  $$$$$$$\ $$ |  $$\ $$ |      $$$$$$\   $$$$$$\  
$$$$$$$$ |\____$$  |$$ |  $$ |$$ |  $$ |$$ |$$  _____|$$ | $$  |$$ |     $$  __$$\ $$  __$$\ 
$$  __$$ |  $$$$ _/ $$ |  $$ |$$ |  $$ |$$ |$$ /      $$$$$$  / $$ |     $$ /  $$ |$$ /  $$ |
$$ |  $$ | $$  _/   $$ $$\$$ |$$ |  $$ |$$ |$$ |      $$  _$$<  $$ |     $$ |  $$ |$$ |  $$ |
$$ |  $$ |$$$$$$$$\ \$$$$$$ / \$$$$$$  |$$ |\$$$$$$$\ $$ | \$$\ $$$$$$$$\\$$$$$$  |\$$$$$$$ |
\__|  \__|\________| \___$$$\  \______/ \__| \_______|\__|  \__|\________|\______/  \____$$ |
                         \___|                                                     $$\   $$ |
                                                                                   \$$$$$$  |
                                                                                    \______/' -ForegroundColor Yellow
Write-Host '
-------------------------------USAGE-------------------------------
    Parameters:
        > -Scope <INPUT> | Specify the scope object. Options: Management group, Subscription or Resource Group. 
            >> If resource group is chosen then the parent subcription id must be provided.
            >> For example, setting the scope to a management group: 
                >>> .\AzQuicklog.ps1 -Scope "Management group"

        > -ScopeId <INPUT> | Specify the name of the scope object (case insensitive)
            >> For example, setting the scope to a management group called "lukeroot": 
                >>> .\AzQuicklog.ps1 -Scope "Management group" -ScopeId "lukeroot"

        > -DSName <INPUT> | DSName is short for Diagnostic Setting Name. This is the name of the diagnostics setting you wish to target. 
            >> Specify "All" to effect all diagnostic settings
            >> For example, setting the scope to a management group and targeting a diagnostic settings name of "lukepolicy":
                >>> .\AzQuicklog.ps1 -Scope "Management group" -ScopeId "lukeroot" -DSName "lukepolicy"
                
        > -Target <INPUT> | This parameter is optional. Leave blank is undesired. Options: Resource Type 
            >> Only provide the name of the resource type, e.g. for a Storage Account the resource type is "Microsoft.Storage/storageAccounts", provide "storageAccounts".
            >> For example, setting the scope to a management group, targeting a diagnostic settings name of "lukepolicy" and virtual machines:
                >>> .\AzQuicklog.ps1 -Scope "Management group" -ScopeId "lukeroot" -DSName "lukepolicy" -Target "VirtualMachines"

' -ForegroundColor Cyan

if (!$script:scope) {
    # Prompt user for input if no scope provided
    Write-Host "Scope Options: [1] Management group, [2] Subscription or [3] Resource Group" -ForegroundColor Yellow
    $script:scope = Read-Host "Enter the Scope" 
} 
else {
    # User either specified 1 or 2
    Write-Host "Scope specified:" $script:scope -ForegroundColor Green
}
if (!$script:scopeId) { 
    # Prompt user for input if no scope id provided
    Write-Host "ScopeId (the management group id), For example: Global-UK or UK-Prod" -ForegroundColor Yellow
    $script:scopeId = Read-Host "Enter the Scope Id"
} 
else {
    # User specified scopeid
    Write-Host "ScopeID specified:" $script:scopeId -ForegroundColor Green
}
if (!$script:dsName) { 
    # Prompt user for input if no dsname provided
    Write-Host "DSName (diagnostic settings name)" -ForegroundColor Yellow
    $script:dsName = Read-Host "Enter the DSName"
} 
else {
    # User specified dsname
    Write-Host "DSName specified:" $script:dsName -ForegroundColor Green
}
# Prompt user for target input, will accept blank for all
Write-Host "Target, For example: VirtualMachine. Leave blank or type 'all' for all resources"  -ForegroundColor Yellow
$script:target = Read-Host "Enter the Target"
if (!$script:target) {
    $script:target = "all"
}


# Global variables for functions
$global:azResources = @()
$global:azSubs = @()
$global:auditLog = @()


## Global variables for subcription enumeration under a given management group
$WarningPreference = "Ignore"
$global:setScope = $script:scopeId
$global:scopeObject = @()
$global:scopeChildArray = @()
$global:returnScope = $script:scope
$global:subscriptionArray = @()
# Extra
$global:resourcesWithDiagSubscriptions = @()
$global:showSubMenu = 1
$global:resourcesWithDiag = @()
$global:foundDiagnosticSettings = @()
# Logic for reassessing after deletion
$global:deletionRan = 0


function ScopeSelection() {
    if ($script:scope.ToLower() -eq "management group" -or $script:scope -eq 1) {
        ResourcePopulateMultipleSubscriptions
    }
    elseif ($script:scope.ToLower() -eq "subscription" -or $script:scope -eq 2) {
        ResourcePopulateSingular
    }
    elseif ($script:scope.ToLower() -eq "resource group" -or $script:scope -eq 3) {
        ResourcePopulateSingular
    }
    else { 
        Write-Host "Invalid input please try again" -ForegroundColor Red
        break
    }
}

function DSNameSelectionGet() {
    Write-Host "Getting resources with diagnostic settings:" -ForegroundColor Cyan
    Write-Host "------ NAME: (" $script:dsName ")" -ForegroundColor Cyan
    Write-Host "------ SCOPEID: (" $script:scopeId ")" -ForegroundColor Cyan
    Write-Host "------ TARGET: (" $script:target ")" -ForegroundColor Cyan

    $jobs = @()
    $processedResources = [hashtable]::Synchronized(@{})

    foreach ($resource in $global:azResources) {
        $job = Start-Job -ScriptBlock {
            param($resource, $dsName, $processedResources)

            # Check if the resource has already been processed
            if ($processedResources.ContainsKey($resource.ResourceId)) {
                return
            }
            
            # Mark the resource as processed
            $processedResources[$resource.ResourceId] = $true

            if ($resource.ResourceType -eq 'Microsoft.Storage/storageAccounts') {
                $accountResID = $resource.ResourceId
                $blobResID = $resource.ResourceId + "/blobServices/default"
                $fileResID = $resource.ResourceId + "/fileServices/default"
                $queueResID = $resource.ResourceId + "/queueServices/default"
                $tableResID = $resource.ResourceId + "/tableServices/default"

                $resourceIds = @($accountResID, $blobResID, $fileResID, $queueResID, $tableResID)

                foreach ($resId in $resourceIds) {
                    try {
                        Get-AzDiagnosticSetting -ResourceId $resId -Name $dsName -ErrorAction Stop -verbose
                        Write-Host "Diagnostic Setting found - resource ID (" $resId "), resource type (" $resource.ResourceType "), resource group (" $resource.ResourceGroupName ")" -ForegroundColor Green

                        [PSCustomObject]@{
                            Resource = $resource
                            ResId    = $resId
                            Type     = "Found"
                        }
                    }
                    catch {
                        [PSCustomObject]@{
                            Resource = $resource
                            ResId    = $resId
                            Type     = "NotFound"
                        }
                    }
                }
            }
            else {
                try {
                    Get-AzDiagnosticSetting -ResourceId $resource.ResourceId -Name $dsName -ErrorAction Stop -verbose
                    Write-Host "Diagnostic Setting found - resource (" $resource.Name "), resource type (" $resource.ResourceType "), resource group (" $resource.ResourceGroupName ")" -ForegroundColor Green

                    [PSCustomObject]@{
                        Resource = $resource
                        ResId    = $resource.ResourceId
                        Type     = "Found"
                    }
                }
                catch {
                    Write-Host "Diagnostic Setting not found - resource (" $resource.Name "), resource type (" $resource.ResourceType "), resource group (" $resource.ResourceGroupName ")" -ForegroundColor Red

                    [PSCustomObject]@{
                        Resource = $resource
                        ResId    = $resource.ResourceId
                        Type     = "NotFound"
                    }
                }
            }
        } -ArgumentList $resource, $script:dsName, $processedResources

        $jobs += $job
    }

    $results = Receive-Job -Job $jobs -Wait -AutoRemoveJob

    foreach ($result in $results) {
        if ($result.Type -eq "Found") {
            $global:resourcesWithDiag += $result.Resource
            $global:foundDiagnosticSettings += $result.ResId
            $resSub = ($result.ResId -split "/")[2]
            $global:resourcesWithDiagSubscriptions += $resSub
        }
    }

    if ($global:showSubMenu -eq 1) {
        Write-Host "`n --- Final Output ---" -ForegroundColor Cyan
        if ($global:foundDiagnosticSettings) {    
            Write-Host "`n --- Specific Diagnostic Settings ---" -ForegroundColor Cyan
            $global:foundDiagnosticSettings | Format-Table | Out-String
            Write-Host "--- Specific Resources ---" -ForegroundColor Cyan
            $global:resourcesWithDiag | Format-Table | Out-String
        }
        else {
            Write-Host "No resources with the specified diagnostic setting name:" $script:dsName -ForegroundColor Red
        }
        subMenu
    }
}

function TargetSelection() {
    if (!$script:target) {
        Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "No target provided, getting all resources" -ForegroundColor Yellow
        $global:azResources += Get-AzResource
        $script:target = "all"
    }
    elseif ($script:target -eq "all") {
        Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "Target is ALL, getting all resources" -ForegroundColor Yellow
        $global:azResources += Get-AzResource
        $script:target = "all"
    }
    else {
        Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "Target provided, getting specified type of resources" -ForegroundColor Green
        $global:azResources += Get-AzResource | Where-Object {$_.ResourceType.split('/')[-1] -eq "$script:target"}
    }
}

function ResourcePopulateSingular() {
    if ($script:scope.ToLower() -eq "subscription" -or $script:scope -eq 2) {
        # Set the context to the subscription scope provided
        Set-AzContext -SubscriptionId $script:scopeId
        TargetSelection
        # Function completion, reshow menu
        subMenu
    }
    elseif ($script:scope.ToLower() -eq "resource group" -or $script:scope -eq 3) {
        # Get resource group subscription context
        $getRGSub = Get-AzResourceGroup -Name $script:scopeId | Select-Object -ExpandProperty ResourceId
        $rgSubId = ($getRGSub -split "/")[2]
         # Set the context to the subscription which the resource group is located in
        Set-AzContext -SubscriptionId $rgSubId
        TargetSelection
        # Function completion, reshow menu
        subMenu
    }
}

function ResourcePopulateMultipleSubscriptions() {
    # Get all Azure Subscriptions
    Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "Enumerating through management groups and subscriptions" -ForegroundColor Yellow
    getScope
    # Iterate through array and check if the subscription is valid
    foreach ($sub in $global:scopeChildArray) {
        try {
            $testSub = Get-AzSubscription -SubscriptionId $sub -ErrorAction Stop
            $global:subscriptionArray += $sub
        }
        catch [System.Management.Automation.PSArgumentException] {
            continue
        } 
        catch { 
            continue
        }
    }
    # Loop through all Azure Subscriptions and get the resources
    Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "Beginning loop through subscriptions to get all resources" -ForegroundColor Yellow

    foreach ($azSub in $global:subscriptionArray) {
        try {
            Write-Host "Setting context to Subscription:" $azSub
            Set-AzContext -Subscription $azSub -ErrorAction Stop | Out-Null
            TargetSelection
        }
        catch { 
            continue
        }  
    } 
    # Function completion, reshow menu
    subMenu
}

function hasChildren() {
    try {
        $getChildren = $global:scopeObject | Select-Object -ExpandProperty Children
        $getScopeId = $global:scopeObject | Select-Object -ExpandProperty Name
        $global:scopeChildArray += $getScopeId
        if ($getChildren.count -ne 0) {
            Write-Host "Scope has children"
            foreach ($child in $getChildren) {
                $global:scopeChildArray += $child.Name   
                $global:setScope = $child.Name
                getScope
            }  
        }
        else {
            Write-Host "Provided Scope does not have any children"
        }
    }
    catch {
        Write-Host "Problem with finding child objects"
    }
}

function getScope() {
    try {
        $global:scopeObject = Get-AzManagementGroup -GroupId $global:setScope -Expand -Recurse -ErrorAction Ignore
        hasChildren
    }
    catch {
        Write-Host "Problem with scope"
    }
}

function RemoveFunc() {
    if (!$global:foundDiagnosticSettings) {
        DSNameSelectionGet
    }
    $logPath = ".\AuditLogs"
    if (!(Test-Path $logPath)) {
        New-Item -Path $logPath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
    }

    switch ($script:scope.ToLower()) {
        { $_ -eq "managment group" -or $_ -eq "1" } {
            Write-Host "Removing Diagnostic setting name: ($($script:dsName.Trim())) from management group scope ($($azSub.Trim()))" -Foregroundcolor Red
            foreach ($azSub in $global:resourcesWithDiagSubscriptions) {
                Write-Host "Removing Diagnostic setting name: ($($script:dsName.Trim())) from subscription ($($azSub.Trim()))" -Foregroundcolor Red
                Set-AzContext $azSub | Out-Null
                RemoveDiag $logPath
            }
        }
        { $_ -eq "subscription" -or $_ -eq "2" } {
            Set-AzContext -SubscriptionId $script:scopeId | Out-Null
            Write-Host "Removing Diagnostic setting name: ($($script:dsName.Trim())) from subscription ($($script:scopeId.Trim()))" -Foregroundcolor Red
            RemoveDiag $logPath
        }
        default {
            $getRGSub = Get-AzResourceGroup -Name $script:scopeId | Select-Object -ExpandProperty ResourceId
            $rgSubId = ($getRGSub -split "/")[2]
            Set-AzContext -SubscriptionId $rgSubId | Out-Null
            Write-Host "Removing Diagnostic setting name: ($($script:dsName.Trim())) from resource group ($($script:scopeId.Trim()))" -Foregroundcolor Red
            RemoveDiag $logPath
        }
    }
    Write-Host "Complete! Logs saved to $logPath\...`n" -Foregroundcolor Green
    $global:showSubMenu = 1
    $global:deletionRan = 1
    subMenu
}

function RemoveDiag($logPath) {
    foreach ($azResource in $global:foundDiagnosticSettings) {
        $resourceId = $azResource
        $azDiagSettings = Get-AzDiagnosticSetting -ResourceId $resourceId | Where-Object {$_.Name -eq $script:dsName}
        foreach ($azDiag in $azDiagSettings) {
            $properties = @{
                StorageAccount = if ($azDiag.StorageAccountId) { $azDiag.StorageAccountId.Split('/')[-1] } else { $null }
                LogAnalytics = if ($azDiag.WorkspaceId) { $azDiag.WorkspaceId.Split('/')[-1] } else { $null }
                EventHub = if ($azDiag.EventHubAuthorizationRuleId) { $azDiag.EventHubAuthorizationRuleId.Split('/')[-3] } else { $null }
            }

            $azDiagid = $azdiag.id -replace "(?=/providers/microsoft.insights).*"
            try {
                Write-Host "Removing Diagnostic setting name: ($($script:dsName.Trim())) from resource id  ($resourceId)" -Foregroundcolor Red
                $removeDiag = Remove-AzDiagnosticSetting -ResourceId $azDiagid -Name $script:dsName
                $removeDiag = New-Object pscustomobject
                $removeDiag | Add-Member -NotePropertyName StatusCode -NotePropertyValue "Success"
            }
            catch {
                $removeDiag = New-Object pscustomobject
                $removeDiag | Add-Member -NotePropertyName StatusCode -NotePropertyValue "ErrorResponseException"
            }

            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $azAuditLog = @(
                "Timestamp: $timestamp",
                "Action: Remove",
                "Azure Resource Id: $($resourceId)",
                "Diagnostic setting name: $($script:dsName)",
                "Removal Status: $($removeDiag.StatusCode)",
                "Previous Storage Account Name: $($properties.StorageAccount)",
                "Previous Log Analytics workspace: $($properties.LogAnalytics)",
                "Previous Event Hub Namespace: $($properties.EventHub)",
                " "
            )

            $resourceSubscription = ($resourceId -split "/")[2]
            $fileNamePath = "$logPath\$resourceSubscription"
            $azAuditLog >> .\$fileNamePath.txt
        }
    }
}

function DeleteWhatIf {
    # If array is not empty
    if (!$global:foundDiagnosticSettings) { 
        $global:showSubMenu = 0
        DSNameSelectionGet
    }
    Write-Host '------ WhatIf Overview ------
    Scope: '$script:scope'
    ScopeId: '$script:scopeId'
    DSName: '$script:dsName'
    Target: '$script:target'
    Action: Removal
    Subscriptions affected: 
    '($global:resourcesWithDiagSubscriptions | Format-Table | Out-String).Trim()'
    Resources affected:
    '($global:resourcesWithDiag | Format-Table | Out-String).Trim()'
    ' -ForegroundColor yellow    
    $global:showSubMenu = 1
    subMenu
}

function printResources() {
    if ($global:azResources) {
        $global:azResources | Format-Table
    }
    else {
        Write-Host "No resources captured with given parameters`n" -ForegroundColor Red
    }
    # Function completion, reshow menu
    subMenu
}

function subMenu() {
    Write-Host "============= MENU ==============" -ForegroundColor Yellow
    Write-Host 'Choose from the following:
1: Print resources found in specified scope
2: Find all resources with diagnostic setting name: (' $script:dsName.Trim() ') and target: (' $script:target ')
3: Print Removal WhatIf overview
4: Delete the specified diagnostic settings from resources: (' $script:dsName.Trim() ') and target: (' $script:target ')
Q: Press "Q" to quit' -ForegroundColor Cyan
    $selection = Read-Host "Please make a selection"
    switch ($selection)
    {
        '1' {
            printResources
        } '2' {
            DSNameSelectionGet
        } '3' {
            # Logic for reassessing resources after deletion ran previously
            if ($global:deletionRan -eq 1) {
                $global:resourcesWithDiag = @()
                $global:resourcesWithDiagSubscriptions = @()
            }
            DeleteWhatIf
        } '4' {
            if ($global:deletionRan -eq 1) {
                $global:resourcesWithDiag = @()
                $global:resourcesWithDiagSubscriptions = @()
            }
            RemoveFunc
        } 'Q' {
            'You chose to quit'
            return
        }
    }
}

function Main() {
    # Login with Connect-AzAccount if you're not using Cloud Shell
    try {
       Connect-AzAccount -ErrorAction Stop | Out-Null
    }
    catch {
        try { 
            Write-Host "--- Az Module not installed ---" -ForegroundColor Red
            $selection = Read-Host "Install now? y/n"
            switch ($selection)
            {
                'y' {
                    Write-Host "--- Installing ---" -ForegroundColor yellow
                    Install-Module -Name Az -Repository PSGallery -Force
                } 'n' {
                    'You chose to quit'
                    break
                }
            }
            
        }
        catch {
            # Break if user authentication cancelled
            Write-Host "User authentication cancelled, script stopping" -ForegroundColor Red
            break
        }
        
    }
    ScopeSelection
}

. Main