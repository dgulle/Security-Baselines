<#
.SYNOPSIS
    Downloads and processes M365 Security Baseline templates into separate JSON files by category.
.DESCRIPTION
    This script downloads the M365 Security Baseline template from GitHub, then splits it into
    separate files based on application categories for easier management and implementation.
.NOTES
    Version: 1.0
.PARAMETER OutputDirectory
    The base directory where all files will be stored.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDirectory = "C:\M365_Baseline"
)


# Define the URL of the M365 Security Baseline JSON file on GitHub
$templateDirectory = Join-Path -Path $outputDirectory -ChildPath "Template"
$githubUrl = "https://raw.githubusercontent.com/dgulle/Security-Baselines/refs/heads/master/M365%20Baseline/Baseline%20Template%20and%20Script/M365%20Baselines%20Export.ps1"
$localFile = Join-Path -Path $templateDirectory -ChildPath "M365_Security_Baseline_Template.json"

Write-Host "Downloading baseline template from GitHub..." -ForegroundColor Cyan

try {
    # Create template directory if it doesn't exist
    if (-not (Test-Path -Path $templateDirectory -PathType Container)) {
        New-Item -Path $templateDirectory -ItemType Directory -Force | Out-Null
        Write-Host "Created template directory: $templateDirectory" -ForegroundColor Cyan
    }

    # Download the file from GitHub and save it locally
    Invoke-WebRequest -Uri $githubUrl -OutFile $localFile -UseBasicParsing -ErrorAction Stop
    Write-Host "Successfully downloaded baseline template to $localFile" -ForegroundColor Green
}
catch {
    Write-Error "Failed to download baseline template from GitHub: $_"
    exit 1
}

# Load the M365 Security Baseline JSON file from the local path
$baselineJson = Get-Content -Path $localFile -Raw 
$baseline = $baselineJson | ConvertFrom-Json

# Create output directory if it doesn't exist
if (-not (Test-Path -Path $outputDirectory -PathType Container)) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
    Write-Host "Created output directory: $outputDirectory" -ForegroundColor Cyan
}

# Define categories and patterns for filtering settings
$categories = @{
    "Access"            = "policy_config_access16"
    "Excel"             = "policy_config_excel16"
    "Word"              = "policy_config_word16"
    "PowerPoint"        = "policy_config_ppt16"
    "Outlook"           = "policy_config_outlk16"
    "Publisher"         = "policy_config_pub16"
    "Project"           = "policy_config_proj16"
    "Visio"             = "policy_config_visio16"
    "Lync"              = "policy_config_lync16"
    "Administrative_Templates" = "flash|jscript"
    "Microsoft_Office_2016" = "policy_config_office16(?!.*machine)"
    "Microsoft_Office_2016_Machine" = "policy_config_office16.*machine"
}

# Process each category and export to JSON
foreach ($categoryName in $categories.Keys) {
    $pattern = $categories[$categoryName]
    $filteredSettings = @($baseline.settings | Where-Object { 
        $_.settingInstance.settingDefinitionId -imatch $pattern 
    })

        $categoryObject = [PSCustomObject]@{
            description          = $baseline.description
            name                 = "$($baseline.name) - $categoryName"
            platforms            = $baseline.platforms
            technologies         = $baseline.technologies
            templateReference    = $baseline.templateReference
            roleScopeTagIds      = $baseline.roleScopeTagIds
            settings             = $filteredSettings
        }

        $jsonOutput = $categoryObject | ConvertTo-Json -Depth 10

        # For Outlook, perform additional string replacements for any remaining issues
        if ($categoryName -eq "Outlook") {
            # Fix empty string children
            $jsonOutput = $jsonOutput -replace '"children"\s*:\s*""', '"children": []'
            
            # Fix any remaining template references in @{} format
            $jsonOutput = $jsonOutput -replace '"settingValueTemplateReference"\s*:\s*"@\{[^}]+\}"', '"settingValueTemplateReference": null'
            
            Write-Host "Applied additional JSON string replacements for Outlook" -ForegroundColor Cyan
        }

        $outputFile = Join-Path -Path $outputDirectory -ChildPath "$categoryName.json"
        $jsonOutput | Out-File -FilePath $outputFile -Encoding utf8

        Write-Host "Successfully created '$outputFile' with $($filteredSettings.Count) settings." -ForegroundColor Green
    }
    