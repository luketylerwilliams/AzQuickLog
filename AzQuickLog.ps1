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
Version   : 1.0
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

if ($script:scope.ToLower() -eq "resource group" -or $script:scope -eq 3) {
    # User provided option 3 / resource group
    Write-Host "Scope specified:" $script:scope -ForegroundColor Green
    $global:rgParentSub = Read-Host "Enter the parent subscription id for the resource group"
}
elseif (!$script:scope) {
    # Prompt user for input if no scope provided
    Write-Host "Scope Options: [1] Management group, [2] Subscription or [3] Resource Group" -ForegroundColor Yellow
    $script:scope = Read-Host "Enter the Scope" 
    if ($script:scope -eq 3) {
        $global:rgParentSub = Read-Host "Enter the parent subscription id for the resource group"
    }
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
$global:rgParentSub = ""

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
    if ($script:dsName.ToLower() -eq 'all') {
        Write-Host "Getting all resource diagnostic settings" -ForegroundColor Cyan
        foreach ($resource in $global:azResources) {
            try {
                $findDiag = Get-AzDiagnosticSetting -ResourceId $resource.ResourceId -Name $script:dsName -ErrorAction Stop
                Write-Host "Diagnostic Setting found - resource (" $resource.Name "), resource group (" $resource.ResourceGroupName ")" -ForegroundColor Green
                $global:resourcesWithDiag += $resource
                $resid = $resource.ResourceId
                $resSub = ($resid -split "/")[2]
                $global:resourcesWithDiagSubscriptions += $resSub
            }
            catch [System.Management.Automation.PSInvalidOperationException] {
                Write-Host "Diagnostic Setting not found - resource (" $resource.Name "), resource group (" $resource.ResourceGroupName ")" -ForegroundColor Red
            }
        }
    }
    else {
        Write-Host "Getting resource diagnostic settings with name: " $script:dsName -ForegroundColor Cyan
        foreach ($resource in $global:azResources) {
            try {
                $findDiag = Get-AzDiagnosticSetting -ResourceId $resource.ResourceId -Name $script:dsName -ErrorAction Stop
                Write-Host "Diagnostic Setting found - resource (" $resource.Name "), resource group (" $resource.ResourceGroupName ")" -ForegroundColor Green
                $global:resourcesWithDiag += $resource
                $resid = $resource.ResourceId
                $resSub = ($resid -split "/")[2]
                $global:resourcesWithDiagSubscriptions += $resSub
            }
            catch [System.Management.Automation.PSInvalidOperationException] {
                Write-Host "Diagnostic Setting not found - resource (" $resource.Name "), resource group (" $resource.ResourceGroupName ")" -ForegroundColor Red
            }
        } 
    }
    
    # Function completion, reshow menu
    if ($global:showSubMenu -eq 1) {
        Write-Host "`n --- Final Output ---" -ForegroundColor Cyan
        if ($global:resourcesWithDiag) {
            # If resources with matching diagnostic settings found then print in table format
            $global:resourcesWithDiag | Format-Table | Out-String
        }
        else {
            Write-Host "No resources with the specified diagnostic setting name:" $script:dsName -ForegroundColor Red
        }
        subMenu
    }
}

function TargetSelection() {
    if (!$script:target -or $script:target -eq "all") {
        Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
        Write-Host "No target provided, getting all resources" -ForegroundColor Yellow
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
            $testSub = Get-AzSubscription -SubscriptionId $sub -ErrorAction SilentlyContinue
            $global:subscriptionArray += $sub
        }
        catch [System.Management.Automation.PSArgumentException] {
            continue
        } 
    }
    # Loop through all Azure Subscriptions and get the resources
    Write-Host "--------------------------------------------------------------------" -ForegroundColor Yellow
    Write-Host "Beginning loop through subscriptions to get all resources" -ForegroundColor Yellow

    foreach ($azSub in $global:subscriptionArray) {
        Write-Host "Setting context to Subscription:" $azSub
        Set-AzContext -Subscription $azSub -ErrorAction SilentlyContinue | Out-Null
        TargetSelection
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
    # If array is not empty
    if (!$global:resourcesWithDiag) { 
        DSNameSelectionGet
    }
    if ($script:scope.ToLower() -eq "managment group" -or $script:scope -eq 1) {
        # Loop through all Azure Subscriptions
        foreach ($azSub in $global:resourcesWithDiagSubscriptions) {
            Write-Host "Removing Diagnostic setting name: (" $script:dsName.Trim() ") from subscription (" $azSub.Trim() ")" -Foregroundcolor Yellow
            Set-AzContext $azSub | Out-Null
            RemoveDiag
        }
        Write-Host "Complete! Logs saved to .\AuditLogs\<subscription-id>.txt`n" -Foregroundcolor Green
    }
    elseif ($script:scope.ToLower() -eq "subscription" -or $script:scope -eq 2) {
        # Set the context to the subscription scope provided
        Set-AzContext -SubscriptionId $script:scopeId
        Write-Host "Removing Diagnostic setting name: (" $script:dsName.Trim() ") from subscription (" $script:scopeId.Trim() ")" -Foregroundcolor Yellow
        foreach ($azDiag in $global:azResources) {
            RemoveDiag
        }
        Write-Host "Complete! Logs saved to .\AuditLogs\<subscription-id>.txt`n" -Foregroundcolor Green
    }
    else {
        # Else is equal to resource group or 3
        # Get resource group subscription context
        $getRGSub = Get-AzResourceGroup -Name $script:scopeId | Select-Object -ExpandProperty ResourceId
        $rgSubId = ($getRGSub -split "/")[2]
         # Set the context to the subscription which the resource group is located in
        Set-AzContext -SubscriptionId $rgSubId
        Write-Host "Removing Diagnostic setting name: (" $script:dsName.Trim() ") from resource group (" $script:scopeId.Trim() ")" -Foregroundcolor Yellow
        foreach ($azDiag in $global:azResources) {
            RemoveDiag
        }
        Write-Host "Complete! Logs saved to .\AuditLogs\<subscription-id>.txt`n" -Foregroundcolor Green
    }
    # Function completion, reshow menu
    $global:showSubMenu = 1
    $global:deletionRan = 1
    subMenu
}

function RemoveDiag() {
    try {
        $createDir = New-Item -Name "AuditLogs" -ItemType directory -ErrorAction SilentlyContinue
    }
    catch {
        continue
    }
    $resourceSubscription = ""
    foreach ($azResource in $global:resourcesWithDiag) {
        $resourceId = $azResource.ResourceId
        $azDiagSettings = Get-AzDiagnosticSetting -ResourceId $resourceId | Where-Object {$_.Name -eq $script:dsName}
        foreach ($azDiag in $azDiagSettings) {
            If ($azDiag.StorageAccountId) {
                [string]$storage = $azDiag.StorageAccountId
                [string]$storageAccount = $storage.Split('/')[-1]
            }
            If ($azDiag.WorkspaceId) {
                [string]$workspace = $azDiag.WorkspaceId
                [string]$logAnalytics = $workspace.Split('/')[-1]
            }
            If ($azDiag.EventHubAuthorizationRuleId) {
                [string]$eHub = $azDiag.EventHubAuthorizationRuleId
                [string]$eventHub = $eHub.Split('/')[-3]
            }
            # Remove diagnostic settings for the particular resource
            [string]$azDiagid = $azdiag.id -replace "(?=/providers/microsoft.insights).*"
            $removeDiag = Remove-AzDiagnosticSetting -ResourceId $azDiagid -Name $azDiag.Name
            if (!$removeDiag) {
                $removeDiag = New-Object pscustomobject
                $removeDiag | Add-Member -NotePropertyName StatusCode -NotePropertyValue "ErrorResponseException"
            }
            # Create log
            $azAuditLog =  @($("Azure Resource name: " + $azResource.Name), ("Diagnostic setting name: " + $azDiag.Name), `
                        ("Removal Status: " + $removeDiag.StatusCode), ("Storage Account Name: " + $storageAccount), `
                        ("Log Analytics workspace: " + $logAnalytics), ("Event Hub Namespace: " + $eventHub) )
            $azAuditLog += @(" ")
            # Acquire subscription id
            $resourceSubscription = ($resourceId -split "/")[2]
            # Save logs to AuditLogs folder in text file named by subscription id
            $fileNamePath = "AuditLogs\$resourceSubscription"
            $azAuditLog >> .\$fileNamePath.txt
        }  
    }
}

function DeleteWhatIf {
    # If array is not empty
    if (!$global:resourcesWithDiag) { 
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
            }
            DeleteWhatIf
        } '4' {
            if ($global:deletionRan -eq 1) {
                $global:resourcesWithDiag = @()
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
        # Break if user authentication cancelled
        Write-Host "User authentication cancelled, script stopping" -ForegroundColor Red
        break
    }
    ScopeSelection
}

. Main