<#
.SYNOPSIS
    Pulls the Microsoft 365 Apps security baseline from Intune and splits it into per-application JSON files.

.DESCRIPTION
    Reads the baseline straight from Microsoft Graph rather than from a checked-in copy, so
    re-running it after Microsoft ships a new baseline version picks up the new settings.

    The script finds the Microsoft 365 Apps for Enterprise Security Baseline under
    deviceManagement/configurationPolicyTemplates, reads its setting templates, and converts each
    one into the setting instance shape that deviceManagement/configurationPolicies expects. The
    result is written as a full policy JSON, then split into one file per application so the
    settings can be reviewed and deployed a piece at a time.

    Settings are matched to applications by the pattern table in $categories. Anything that matches
    no pattern, or more than one, is listed at the end so new settings are never dropped silently.

    Read-only against the tenant. Requires the Microsoft.Graph.Authentication module and the
    DeviceManagementConfiguration.Read.All scope.

.PARAMETER OutputDirectory
    Where the per-application JSON files are written. Defaults to the folder above this script,
    which is the "M365 Baseline" folder in this repository.

.PARAMETER TemplateDirectory
    Where the full baseline JSON is written. Defaults to the folder holding this script.

.PARAMETER BaselineVersion
    A specific baseline version to export, such as "Version 2512". Defaults to whichever version
    Intune currently marks active.

.PARAMETER PolicyName
    Name prefix for the generated policies. Each file gets "<PolicyName> - <Application>".

.PARAMETER TemplateDisplayName
    Display name of the baseline template to export.

.PARAMETER UseDeviceCode
    Sign in with a device code instead of a browser window. Needed in terminals where the Windows
    account broker cannot open its own window; the script also falls back to this on its own if the
    browser sign-in fails.

.NOTES
    Version: 2.0

.EXAMPLE
    .\M365 Baselines Export.ps1

    Exports the active baseline over the JSON files in this repository.

.EXAMPLE
    .\M365 Baselines Export.ps1 -BaselineVersion "Version 2306" -OutputDirectory C:\Temp\2306

    Exports a superseded version to a scratch folder, which is useful for diffing two versions.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDirectory,

    [Parameter()]
    [string]$TemplateDirectory,

    [Parameter()]
    [string]$BaselineVersion,

    [Parameter()]
    [string]$PolicyName = 'M365 Baseline',

    [Parameter()]
    [string]$TemplateDisplayName = 'Microsoft 365 Apps for Enterprise Security Baseline',

    [Parameter()]
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Stop'

if (-not $OutputDirectory)   { $OutputDirectory   = Split-Path -Path $PSScriptRoot -Parent }
if (-not $TemplateDirectory) { $TemplateDirectory = $PSScriptRoot }

# Which settings belong to which application, matched against settingDefinitionId. The patterns
# leave the version suffix off (access16 rather than access16v2) so a namespace bump in a future
# baseline still lands in the right file.
$categories = [ordered]@{
    'Access'                        = 'policy_config_access16'
    'Administrative_Templates'      = 'flash|jscript'
    'Excel'                         = 'policy_config_excel16'
    'Lync'                          = 'policy_config_lync16'
    'Microsoft_Office_2016'         = 'policy_config_office16(?!.*machine)'
    'Microsoft_Office_2016_Machine' = 'policy_config_office16.*machine'
    'Outlook'                       = 'policy_config_outlk16'
    'PowerPoint'                    = 'policy_config_ppt16'
    'Project'                       = 'policy_config_proj16'
    'Publisher'                     = 'policy_config_pub16'
    'Visio'                         = 'policy_config_visio16'
    'Word'                          = 'policy_config_word16'
}

# ── Graph helpers ────────────────────────────────────────────────────────────

function Connect-BaselineGraph {
    $scope = 'DeviceManagementConfiguration.Read.All'

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        Write-Host "Installing Microsoft.Graph.Authentication for the current user..." -ForegroundColor Cyan
        Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
    }

    Import-Module Microsoft.Graph.Authentication

    $context = Get-MgContext
    if ($context -and $context.Scopes -contains $scope) {
        Write-Host "Using existing Graph session for $($context.Account)." -ForegroundColor Green
        return
    }

    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

    if ($UseDeviceCode) {
        Connect-MgGraph -Scopes $scope -UseDeviceCode -NoWelcome
    }
    else {
        try {
            Connect-MgGraph -Scopes $scope -NoWelcome
        }
        catch {
            # Web Account Manager is the default broker on Windows and wants a parent window handle,
            # which it cannot get from a terminal with no GUI attached. Device code has no such need.
            Write-Host "Interactive sign-in did not work here ($($_.Exception.Message))." -ForegroundColor Yellow
            Write-Host "Falling back to device code." -ForegroundColor Yellow
            Connect-MgGraph -Scopes $scope -UseDeviceCode -NoWelcome
        }
    }

    Write-Host "Connected as $((Get-MgContext).Account)." -ForegroundColor Green
}

function Get-GraphCollection {
    param([Parameter(Mandatory)][string]$Uri)

    $items = @()
    while ($Uri) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject
        $items += $response.value
        $Uri = $response.'@odata.nextLink'
    }
    return $items
}

# ── Template to policy conversion ────────────────────────────────────────────

# Setting templates describe a setting and its baseline-recommended value; policies carry the value
# itself. The two shapes differ enough that each supported type needs its own mapping. An unknown
# type throws rather than being skipped, so a new setting kind in a future baseline is loud.
function ConvertTo-SettingInstance {
    param([Parameter(Mandatory)][psobject]$Template)

    $templateType = $Template.'@odata.type'

    if ($templateType -like '*ChoiceSettingInstanceTemplate') {
        $valueTemplate = $Template.choiceSettingValueTemplate
        $default       = $valueTemplate.defaultValue

        if (-not $default) {
            throw "Choice setting '$($Template.settingDefinitionId)' has no default value to export."
        }

        $children = @()
        foreach ($child in @($default.children)) {
            if ($child) { $children += , (ConvertTo-SettingInstance -Template $child) }
        }

        return [ordered]@{
            '@odata.type'                     = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
            settingDefinitionId               = $Template.settingDefinitionId
            settingInstanceTemplateReference  = [ordered]@{
                settingInstanceTemplateId = $Template.settingInstanceTemplateId
            }
            choiceSettingValue                = [ordered]@{
                value                         = $default.settingDefinitionOptionId
                settingValueTemplateReference = [ordered]@{
                    settingValueTemplateId = $valueTemplate.settingValueTemplateId
                    useTemplateDefault     = $false
                }
                children                      = @($children)
            }
        }
    }

    if ($templateType -like '*SimpleSettingInstanceTemplate') {
        $valueTemplate = $Template.simpleSettingValueTemplate
        $default       = $valueTemplate.defaultValue

        if (-not $default) {
            throw "Simple setting '$($Template.settingDefinitionId)' has no default value to export."
        }

        $valueType = switch -Wildcard ($valueTemplate.'@odata.type') {
            '*IntegerSettingValueTemplate' { '#microsoft.graph.deviceManagementConfigurationIntegerSettingValue' }
            '*StringSettingValueTemplate'  { '#microsoft.graph.deviceManagementConfigurationStringSettingValue' }
            default {
                throw "Setting '$($Template.settingDefinitionId)' uses value template '$($valueTemplate.'@odata.type')', which this script does not handle yet."
            }
        }

        return [ordered]@{
            '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
            settingDefinitionId              = $Template.settingDefinitionId
            settingInstanceTemplateReference = [ordered]@{
                settingInstanceTemplateId = $Template.settingInstanceTemplateId
            }
            simpleSettingValue               = [ordered]@{
                '@odata.type'                 = $valueType
                value                         = $default.constantValue
                settingValueTemplateReference = [ordered]@{
                    settingValueTemplateId = $valueTemplate.settingValueTemplateId
                    useTemplateDefault     = $false
                }
            }
        }
    }

    throw "Setting '$($Template.settingDefinitionId)' uses instance template '$templateType', which this script does not handle yet."
}

function Write-JsonFile {
    param(
        [Parameter(Mandatory)][object]$InputObject,
        [Parameter(Mandatory)][string]$Path
    )

    $json = $InputObject | ConvertTo-Json -Depth 100

    # The previous version of this script had to patch up empty children arrays that came out as ""
    # instead of [], which Intune rejects on import. Building the objects here rather than round
    # tripping them through ConvertFrom-Json should avoid it, but the guard costs nothing.
    $json = $json -replace '"children"\s*:\s*""', '"children": []'

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

# ── Locate the baseline template ─────────────────────────────────────────────

Connect-BaselineGraph

Write-Host "Looking up '$TemplateDisplayName'..." -ForegroundColor Cyan

$allTemplates = Get-GraphCollection -Uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates'
$candidates   = @($allTemplates | Where-Object { $_.displayName -eq $TemplateDisplayName })

if (-not $candidates) {
    throw "No template named '$TemplateDisplayName' was found in this tenant."
}

if ($BaselineVersion) {
    $template = $candidates | Where-Object { $_.displayVersion -eq $BaselineVersion } | Select-Object -First 1
    if (-not $template) {
        $available = ($candidates.displayVersion | Sort-Object) -join ', '
        throw "Version '$BaselineVersion' was not found. Available versions: $available"
    }
}
else {
    $template = $candidates |
        Where-Object { $_.lifecycleState -eq 'active' } |
        Sort-Object version -Descending |
        Select-Object -First 1

    if (-not $template) {
        throw "No active version of '$TemplateDisplayName' was found. Pass -BaselineVersion to export a superseded one."
    }
}

Write-Host "Found $($template.displayVersion) ($($template.id)), $($template.settingTemplateCount) settings, lifecycle '$($template.lifecycleState)'." -ForegroundColor Green

# ── Read and convert the settings ────────────────────────────────────────────

Write-Host "Reading setting templates..." -ForegroundColor Cyan

$settingTemplates = @(Get-GraphCollection -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicyTemplates/$($template.id)/settingTemplates?`$top=500")

if ($settingTemplates.Count -ne $template.settingTemplateCount) {
    Write-Warning "Template reports $($template.settingTemplateCount) settings but $($settingTemplates.Count) were returned."
}

# Sorted so that re-running against an unchanged baseline produces a byte-identical file and the
# git diff shows only real setting changes.
$ordered = $settingTemplates |
    Sort-Object { $_.settingInstanceTemplate.settingDefinitionId }

$settings = @()
$index    = 0
foreach ($settingTemplate in $ordered) {
    $settings += , [ordered]@{
        id              = "$index"
        settingInstance = ConvertTo-SettingInstance -Template $settingTemplate.settingInstanceTemplate
    }
    $index++
}

Write-Host "Converted $($settings.Count) settings." -ForegroundColor Green

$templateReference = [ordered]@{
    templateId             = $template.id
    templateFamily         = $template.templateFamily
    templateDisplayName    = $template.displayName
    templateDisplayVersion = $template.displayVersion
}

# ── Write the full baseline ──────────────────────────────────────────────────

foreach ($directory in @($TemplateDirectory, $OutputDirectory)) {
    if (-not (Test-Path -Path $directory -PathType Container)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
        Write-Host "Created $directory" -ForegroundColor Cyan
    }
}

$fullBaseline = [ordered]@{
    description       = ''
    name              = $PolicyName
    platforms         = $template.platforms
    technologies      = $template.technologies
    templateReference = $templateReference
    roleScopeTagIds   = @('0')
    settings          = @($settings)
}

$templatePath = Join-Path -Path $TemplateDirectory -ChildPath 'M365 Baseline Template.json'
Write-JsonFile -InputObject $fullBaseline -Path $templatePath
Write-Host "Wrote $templatePath ($($settings.Count) settings)." -ForegroundColor Green

# ── Split by application ─────────────────────────────────────────────────────

$assignments = @{}

foreach ($categoryName in $categories.Keys) {
    $pattern  = $categories[$categoryName]
    $filtered = @($settings | Where-Object { $_.settingInstance.settingDefinitionId -imatch $pattern })

    foreach ($setting in $filtered) {
        $definitionId = $setting.settingInstance.settingDefinitionId
        if (-not $assignments.ContainsKey($definitionId)) { $assignments[$definitionId] = @() }
        $assignments[$definitionId] += $categoryName
    }

    # Renumber within the file so each policy's setting ids start at 0.
    $renumbered = @()
    $position   = 0
    foreach ($setting in $filtered) {
        $renumbered += , [ordered]@{
            id              = "$position"
            settingInstance = $setting.settingInstance
        }
        $position++
    }

    $categoryPolicy = [ordered]@{
        description       = ''
        name              = "$PolicyName - $categoryName"
        platforms         = $template.platforms
        technologies      = $template.technologies
        templateReference = $templateReference
        roleScopeTagIds   = @('0')
        settings          = @($renumbered)
    }

    $outputFile = Join-Path -Path $OutputDirectory -ChildPath "$categoryName.json"
    Write-JsonFile -InputObject $categoryPolicy -Path $outputFile

    Write-Host ("  {0,-30} {1,3} settings" -f $categoryName, $filtered.Count) -ForegroundColor Green
}

# ── Report anything the patterns did not cover cleanly ───────────────────────

$unmatched = @($settings | Where-Object { -not $assignments.ContainsKey($_.settingInstance.settingDefinitionId) })
$duplicated = @($assignments.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 })

Write-Host ""
Write-Host "$($template.displayVersion): $($settings.Count) settings, $(($settings.Count - $unmatched.Count)) written to application files." -ForegroundColor Cyan

if ($unmatched.Count -gt 0) {
    Write-Warning "$($unmatched.Count) setting(s) matched no application pattern and are only in the full baseline file:"
    foreach ($setting in $unmatched) {
        Write-Warning "  $($setting.settingInstance.settingDefinitionId)"
    }
}

if ($duplicated.Count -gt 0) {
    Write-Warning "$($duplicated.Count) setting(s) matched more than one application pattern and appear in each:"
    foreach ($entry in $duplicated) {
        Write-Warning "  $($entry.Key) -> $($entry.Value -join ', ')"
    }
}

if ($unmatched.Count -eq 0 -and $duplicated.Count -eq 0) {
    Write-Host "Every setting landed in exactly one application file." -ForegroundColor Green
}
