<#
.SYNOPSIS
    Downloads and processes Microsoft Edge security baseline settings by category.
.DESCRIPTION
    This script downloads the Edge baseline template from GitHub, 
    parses it, and exports separate configuration files by category.
.PARAMETER OutputDirectory
    The base directory where all files will be stored.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDirectory = "C:\Edge_Baselines"
)

# Setup paths and URLs
$templateDirectory = Join-Path -Path $OutputDirectory -ChildPath "Template"
$localFile = Join-Path -Path $templateDirectory -ChildPath "Edge_Baseline_v128.json"
$githubUrl = "https://raw.githubusercontent.com/dgulle/Security-Baselines/refs/heads/master/Edge%20Baseline/Baseline%20Template%20and%20Script/Edge%20Baseline%20-%20v128.json"

Write-Host "Processing Edge baseline JSON..." -ForegroundColor Cyan

# Create directories if they don't exist
if (-not (Test-Path -Path $templateDirectory -PathType Container)) {
    Write-Verbose "Creating template directory: $templateDirectory"
    New-Item -Path $templateDirectory -ItemType Directory -Force | Out-Null
    Write-Host "Created template directory: $templateDirectory" -ForegroundColor Cyan
}

# Download baseline template
try {
    Write-Host "Downloading baseline template from GitHub..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $githubUrl -OutFile $localFile -UseBasicParsing -ErrorAction Stop
    Write-Host "Successfully downloaded baseline template to $localFile" -ForegroundColor Green
}
catch {
    Write-Error "Failed to download baseline template from GitHub: $_"
    exit 1
}

# Load the Edge Baseline JSON file
try {
    $baselineJson = Get-Content -Path $localFile -Raw -ErrorAction Stop
    $baseline = $baselineJson | ConvertFrom-Json
    Write-Verbose "Successfully loaded baseline JSON"
}
catch {
    Write-Error "Failed to load or parse the baseline template: $_"
    exit 1
}

# Define categories and patterns for filtering settings
$categories = @{
    "Extensions" = "extensions"
    "HTTP authentication" = "httpauthentication"
    "Native Messaging" = "nativemessaging"
    "Private Network Request Settings" = "privatenetworkrequestsettings"
    "SmartScreen settings" = "smartscreen"
    "Typosquatting Checker settings" = "typosquattingchecker"
    "Microsoft Edge" = "toolbarbuttonenabled|internetexplorerintegration|sslerroroverrideallowed|dynamiccodesettings|applicationboundencryptionenabled|browserlegacyextensionpointsblockingenabled|siteperprocess|sharedarraybufferunrestrictedaccessallowed"
}

# Process each category and export to JSON
foreach ($categoryName in $categories.Keys) {
    Write-Verbose "Processing category: $categoryName"
    $pattern = $categories[$categoryName]
    $filteredSettings = @($baseline.settings | Where-Object {
        $_.settingInstance.settingDefinitionId -imatch $pattern
    })
    
    $categoryObject = [PSCustomObject]@{
        description       = $baseline.description
        name              = "$($baseline.name) - $categoryName"
        platforms         = $baseline.platforms
        technologies      = $baseline.technologies
        templateReference = $baseline.templateReference
        roleScopeTagIds   = $baseline.roleScopeTagIds
        settings          = $filteredSettings
    }
    
    $outputPath = Join-Path -Path $OutputDirectory -ChildPath "$($baseline.name)_$categoryName.json"
    $categoryObject | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputPath
    Write-Host "Exported $categoryName settings to $outputPath" -ForegroundColor Green
}