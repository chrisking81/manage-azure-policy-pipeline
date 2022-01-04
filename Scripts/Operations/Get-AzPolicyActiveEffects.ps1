#Requires -PSEdition Core

# .\Scripts\Operations\Get-AzPolicyActiveEffects.ps1 -InformationAction Continue | ConvertTo-Csv | Out-File .\Output\effective-effects.csv

# Script uses the hashtable input to calculate the active (effective) effect paramters for the specified
# representative Policy Assignments and out puts the result as a CSV file
[CmdletBinding()]
param (
)

function Get-CombinedParameters {
    [CmdletBinding()]
    param (
        [hashtable] $parametersIn,
        [hashtable] $definedParameters
    )

    [hashtable] $combinedParameters = @{}
    foreach ($name in $definedParameters.Keys) {
        $definedParameter = $definedParameters.$name
        if ($parametersIn.ContainsKey($name)) {
            $combinedParameters.Add($name, @{
                    paramValue   = $parametersIn[$name].value
                    type         = "SetInAssignment"
                    defaultValue = $definedParameter.defaultValue
                })
        }
        else {
            $combinedParameters.Add($name, @{
                    paramValue   = $definedParameter.defaultValue
                    type         = "InititiativeDefaultValue"
                    defaultValue = $definedParameter.defaultValue
                })
        }
    }
    return $combinedParameters
}

function Get-ParmeterNameFromValueString {
    [CmdletBinding()]
    param (
        [string] $paramValue
    )
    
    if ($paramValue.StartsWith(("[parameters('")) -and $paramValue.EndsWith("')]")) {
        $value1 = $paramValue.Replace("[parameters('", "")
        $parameterName = $value1.Replace("')]", "")
        return $true, $parameterName
    }
    else {
        return $false, $paramValue
    }
}

function Get-PolicyEffectDetails {
    [CmdletBinding()]
    param (
        $policy
    )

    $effectValue = $policy.policyRule.then.effect
    $found, $parameterName = Get-ParmeterNameFromValueString -paramValue $effectValue

    $result = @{}
    if ($found) {
        $parameters = $policy.parameters | ConvertTo-HashTable
        if ($parameters.ContainsKey($parameterName)) {
            $parameter = $parameters.$parameterName
            $result = @{
                paramValue    = $parameter.defaultValue
                defaultvalue  = $parameter.defaultValue
                allowedValues = $parameter.allowedValues
                parameterName = $parameterName
                type          = "PolicyDefaultValue"
            }
        }
    }
    else {
        # Fixed value
        $result = @{
            fixedValue    = $effectValue
            defaultvalue  = $effectValue
            allowedValues = @( $effectValue )
            type          = "FixedByPolicyDefinition"
        }
    }
    return $result
}

function Get-EffectiveAzPolicyEffectsList {
    [CmdletBinding()]
    param (
        [string] $AssignmentId,
        [hashtable] $PolicyDefinitions,
        [hashtable] $InitiativeDefinitions
    )
    
    # Write-Information "    $($assignmentId)"
    $splat = Split-AzPolicyAssignmentIdForAzCli -id $assignmentId
    $assignment = Invoke-AzCli policy assignment show -Splat $splat -AsHashTable

    $assignmentParameters = $assignment.parameters
    [hashtable[]] $effectiveEffectList = @()

    # This code could be broken up and optimized; however, the author believes that this long form is more readable
    if ($assignment.policyDefinitionId.Contains("policySetDefinition")) {
        # Initiative
        $initiativeDefinition = $initiativeDefinitions[$assignment.policyDefinitionId]
        $initiativeDefinitionParameters = $initiativeDefinition.parameters | ConvertTo-HashTable
        $initiativeParameters = Get-CombinedParameters -parametersIn $assignmentParameters -definedParameters $initiativeDefinitionParameters
        $policyDefinitionsInSet = $initiativeDefinition.policyDefinitions
        foreach ($policy in $policyDefinitionsInSet) {
            $policyDefinition = $PolicyDefinitions[$policy.policyDefinitionId]
            $effect = Get-PolicyEffectDetails -policy $policyDefinition
            $result = $null
            if ($effect.type -eq "FixedByPolicyDefinition") {
                # parameter is hard-coded into Policy definition
                $result = @{
                    paramValue                  = $effect.fixedValue
                    allowedValues               = @( $effect.fixedValue )
                    defaultValue                = $effect.fixedValue
                    definitionType              = $effect.type
                    assignmentName              = $assignment.name
                    assignmentDisplayName       = $assignment.displayName
                    assignmentDescription       = $assignment.description
                    initiativeId                = $initiativeDefinition.id
                    initiativeDisplayName       = $initiativeDefinition.displayName
                    initiativeDescription       = $initiativeDefinition.description
                    initiativeParameterName     = "na"
                    policyDefinitionReferenceId = $policy.policyDefinitionReferenceId
                    policyId                    = $policyDefinition.id
                    policyDisplayName           = $policyDefinition.displayName
                    policyDescription           = $policyDefinition.description
                }
            }
            else {
                $policyParameters = $policy.parameters | ConvertTo-HashTable
                if ($policyParameters.ContainsKey($effect.parameterName)) {
                    # parmeter value is specified in initiative
                    $param = $policyParameters[$effect.parameterName]
                    $paramValue = $param.value
                    # find the translated parameterName, found means it was parmeterized, not found means it is hard coded which would be weird, but legal
                    $found, $policyDefinitionParameterName = Get-ParmeterNameFromValueString -paramValue $paramValue
                    if ($found) {
                        $initiativeParameter = $initiativeParameters[$policyDefinitionParameterName]
                        $result = @{
                            paramValue                  = $initiativeParameter.paramValue
                            allowedValues               = $effect.allowedValues
                            defaultValue                = $initiativeParameter.defaultValue
                            definitionType              = $initiativeParameter.type
                            assignmentName              = $assignment.name
                            assignmentDisplayName       = $assignment.displayName
                            assignmentDescription       = $assignment.description
                            initiativeId                = $initiativeDefinition.id
                            initiativeDisplayName       = $initiativeDefinition.displayName
                            initiativeDescription       = $initiativeDefinition.description
                            initiativeParameterName     = $policyDefinitionParameterName
                            policyDefinitionReferenceId = $policy.policyDefinitionReferenceId
                            policyId                    = $policyDefinition.id
                            policyDisplayName           = $policyDefinition.displayName
                            policyDescription           = $policyDefinition.description
                        }
                    }
                    else {
                        $parameterName = $effect.parameterName
                        $initiativeParameter = $initiativeParameters.$parameterName
                        $result = @{
                            paramValue                  = $paramValue
                            allowedValues               = $effect.allowedValues
                            defaultValue                = $effect.defaultValue
                            definitionType              = "FixedByInitiativeDefinition"
                            assignmentName              = $assignment.name
                            assignmentDisplayName       = $assignment.displayName
                            assignmentDescription       = $assignment.description
                            initiativeId                = $initiativeDefinition.id
                            initiativeDisplayName       = $initiativeDefinition.displayName
                            initiativeDescription       = $initiativeDefinition.description
                            initiativeParameterName     = "na"
                            policyDefinitionReferenceId = $policy.policyDefinitionReferenceId
                            policyId                    = $policyDefinition.id
                            policyDisplayName           = $policyDefinition.displayName
                            policyDescription           = $policyDefinition.description
                        }
                    }
                }
                else {
                    # parameter is defined by Policy definition default
                    $result = @{
                        paramValue                  = $effect.paramValue
                        allowedValues               = $effect.allowedValues
                        defaultValue                = $effect.defaultValue
                        definitionType              = $effect.type
                        assignmentName              = $assignment.name
                        assignmentDisplayName       = $assignment.displayName
                        assignmentDescription       = $assignment.description
                        initiativeId                = $initiativeDefinition.id
                        initiativeDisplayName       = $initiativeDefinition.displayName
                        initiativeDescription       = $initiativeDefinition.description
                        initiativeParameterName     = "na"
                        policyDefinitionReferenceId = $policy.policyDefinitionReferenceId
                        policyId                    = $policyDefinition.id
                        policyDisplayName           = $policyDefinition.displayName
                        policyDescription           = $policyDefinition.description
                    }
                }
            }
            $effectiveEffectList += $result
        }
    }
    else {
        # Policy
        $policyDefinition = $PolicyDefinitions[$assignment.policyDefinitionId]
        $effect = Get-PolicyEffectDetails -policy $PolicyDefinition
        $result = $null
        if ($effect.type -eq "FixedByPolicyDefinition") {
            # parameter is hard-coded into Policy definition
            $result = @{
                paramValue                  = $effect.fixedValue
                allowedValues               = @( $effect.fixedValue )
                defaultValue                = $effect.fixedValue
                definitionType              = $effect.type
                assignmentName              = $assignment.name
                assignmentDisplayName       = $assignment.displayName
                assignmentDescription       = $assignment.description
                initiativeId                = "na"
                initiativeDisplayName       = "na"
                initiativeDescription       = "na"
                initiativeParameterName     = "na"
                policyDefinitionReferenceId = "na"
                policyId                    = $policyDefinition.id
                policyDisplayName           = $policyDefinition.displayName
                policyDescription           = $policyDefinition.description
            }
        }
        elseif ($assignmentParameters.ContainsKey($effect.parameterName)) {
            # parmeter value is specified in assignment
            $param = $policy.parameters[$effect.parameterName]
            $paramValue = $param.value
            # find the translated parmeterName, found means it was parmeterized, not found means it is hard coded which would be weird, nut legal
            $result = @{
                paramValue                  = $paramValue
                allowedValues               = $effect.allowedValues
                defaultValue                = $effect.defaultValue
                definitionType              = "SetInAssignment"
                assignmentName              = $assignment.name
                assignmentDisplayName       = $assignment.displayName
                assignmentDescription       = $assignment.description
                initiativeId                = "na"
                initiativeDisplayName       = "na"
                initiativeDescription       = "na"
                initiativeParameterName     = "na"
                policyDefinitionReferenceId = "na"
                policyId                    = $policyDefinition.id
                policyDisplayName           = $policyDefinition.displayName
                policyDescription           = $policyDefinition.description
            }
        }
        else {
            # parameter is defined by Policy definition default
            $result = @{
                paramValue                  = $effect.paramValue
                allowedValues               = $effect.allowedValues
                defaultValue                = $effect.defaultValue
                definitionType              = $effect.type
                assignmentName              = $assignment.name
                assignmentDisplayName       = $assignment.displayName
                assignmentDescription       = $assignment.description
                initiativeId                = "na"
                initiativeDisplayName       = "na"
                initiativeDescription       = "na"
                initiativeParameterName     = "na"
                policyDefinitionReferenceId = "na"
                policyId                    = $policyDefinition.id
                policyDisplayName           = $policyDefinition.displayName
                policyDescription           = $policyDefinition.description
            }
        }
        $effectiveEffectList += $result
    }
    return $effectiveEffectList
}

. "$PSScriptRoot/../Helpers/Get-AllAzPolicyInitiativeDefinitions.ps1"
. "$PSScriptRoot/../Utils/Invoke-AzCli.ps1"
. "$PSScriptRoot/../Utils/Split-AzPolicyAssignmentIdForAzCli.ps1"
. "$PSScriptRoot/../Utils/ConvertTo-HashTable.ps1"


# Get definitions
$envTagList, $repAssignments, $rootScope = . "$PSScriptRoot/Get-RepresentativeAssignments.ps1"
$collections = Get-AllAzPolicyInitiativeDefinitions -RootScope $rootScope -byId
$allPolicyDefinitions = $collections.builtInPolicyDefinitions + $collections.existingCustomPolicyDefinitions
$allInitiativeDefinitions = $collections.builtInInitiativeDefinitions + $collections.existingCustomInitiativeDefinitions


# Collect raw data
$data = @{}

# Precedence for Effects (should only happen if Disabled in one Assignment and other effect in a different assignment):
#     Append, Deny, Audit, Disabled
#     DeployIfNotExists, AuditIfNotExists, Disabled
# Effect captilazition (varies greatly) is unified for comparisons
$rankedEffects = @{
    disabled          = 0
    audit             = 1
    auditifnotexists  = 1
    deny              = 2
    deployifnotexists = 2
    modify            = 2
    append            = 3
}

Write-Information "==================================================================================================="
Write-Information "Processing"
Write-Information "==================================================================================================="

foreach ($envTag in $envTagList) {
    $assignmentIds = $repAssignments.$envTag
    Write-Information "Processing environment $envTag"
    foreach ($assignmentId in $assignmentIds) {
        # Flat List of entries (each a hashtable of information)
        Write-Information "   Assignment $assignmentId"
        $list = Get-EffectiveAzPolicyEffectsList -AssignmentId $assignmentId -PolicyDefinitions $allPolicyDefinitions -InitiativeDefinitions $allInitiativeDefinitions
        foreach ($item in $list) {
            $policyId = $item.policyId
            if ($data.ContainsKey($policyId)) {
                [hashtable] $policyEntry = $data.$policyId
                if ($policyEntry.ContainsKey($envTag)) {
                    # Previously processed this envTag for this policyId -> reconcile Effect parameter
                    $oldEffectiveParameter = $policyEntry.$envTag
                    $oldEffect = $oldEffectiveParameter.paramValue.ToLower()
                    $oldEffectRank = -1 # should not be possible
                    if ($rankedEffects.ContainsKey($oldEffect)) {
                        $oldEffectRank = $rankedEffects.$oldEffect
                    }
                    $newEffect = $item.paramValue.ToLower
                    $newEffectRank = -1 # should not be possible
                    if ($rankedEffects.ContainsKey($newEffect)) {
                        $newEffectRank = $rankedEffects.$newEffect
                    }
                    if ($newEffectRank -gt $oldEffectRank) {
                        $policyEntry[$envTag] = $item
                    }
                }
                else {
                    # First time we are processing this envTag for this policyId
                    $policyEntry.Add($envTag, $item)
                }
            }
            else {
                # First time we are processing this policyId
                $data.Add($policyId, @{ $envTag = $item })
            }
        }
    }
}

# Flatten (for Excel) 
Write-Information "Flattening the data for export to csv file"

# Fills in $activeEffects hashtable
$flatList = @()
foreach ($policyId in $data.Keys) {
    $dataEntry = $data.$policyId
    $policyDefinition = $allPolicyDefinitions.$policyId
    $displayName = $policyDefinition.displayName
    $description = $policyDefinition.description
    $category = $policyDefinition.metadata.category
    $dataEntry = $data.$policyId
    $flat = @{
        PolicyId    = $policyId
        Policy      = $displayName
        Description = $description
        Category    = $category
    }

    foreach ($envTag in $envTagList) {
        if ($dataEntry.ContainsKey($envTag)) {
            $entry = $dataEntry.$envTag
            $paramValue = $entry.paramValue
            $flat.Add($envTag, $paramValue)
        }
        else {
            # Ensures uniform columns
            $flat.Add($envTag, "na")
        }
    }

    if ($dataEntry.Count -gt 0) {
        foreach ($value in $dataEntry.Values) {
            $flat += @{
                InitiativeId                = $value.initiativeId
                InitiativeDisplayName       = $value.initiativeDisplayName
                InitiativeDescription       = $value.initiativeDescription
                InitiativeParameterName     = $value.initiativeParameterName
                PolicyDefinitionReferenceId = $value.policyDefinitionReferenceId
                AllowedValues               = $value.allowedValues | ConvertTo-Json -Compress
                DefaultValue                = $value.defaultValue
                DefinitionType              = $value.definitionType
            }
            break
        }
    }
    else {
        $flat += @{
            InitiativeId                = "na"
            InitiativeDisplayName       = "na"
            InitiativeDescription       = "na"
            InitiativeParameterName     = "na"
            PolicyDefinitionReferenceId = "na"
            AllowedValues               = "na"
            DefaultValue                = "na"
            DefinitionType              = "na"
        }
    }

    $flatObj = [PSCustomObject]$flat
    $flatList += $flatObj
}

$columns = @( "Category", "Policy", "Description" )
foreach ($envTag in $envTagList) {
    $columns += $envTag
}
$columns += @( "DefinitionType", "DefaultValue", "AllowedValues", "PolicyId", "InitiativeDisplayName", "PolicyDefinitionReferenceId", "InitiativeParameterName" )

$output = $flatlist | Sort-Object -Property Category, DisplayName
$output | Select-Object $columns
