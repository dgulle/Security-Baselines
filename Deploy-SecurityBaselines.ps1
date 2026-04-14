<#
.SYNOPSIS
  Deploys (or inventories via -DryRun) Intune baseline policies from the Security-Baselines repository.

.DESCRIPTION
  Downloads the Security-Baselines repository from GitHub (or uses -SourcePath), reads the
  selected baseline JSON files (Windows 24H2/25H2, Edge v128, M365), and creates or updates
  Intune Settings Catalog device management configuration policies via Microsoft Graph.

  By default, existing policies with the same name are skipped. Use -UpdateExisting to
  update policies in place.

  Use -DryRun to connect to Microsoft Graph with read-only permissions, detect which policies
  already exist by name, and show what would be created/updated/assigned without making changes.

    Temporary files are automatically cleaned up after deployment.

.PARAMETER InstallWindows
  Deploy Windows 11 Security Baseline policies (24H2 or 25H2). Use -WindowsVersion to choose.

.PARAMETER WindowsVersion
  Select which Windows baseline folder to deploy when -InstallWindows is used.
  Valid values: 24H2, 25H2. Default: 25H2.

.PARAMETER InstallEdge
    Deploy Microsoft Edge v128 Security Baseline policies (7 policies).

.PARAMETER InstallM365
    Deploy Microsoft 365 Apps Security Baseline policies (12 policies).

.PARAMETER InstallAll
    Deploy all available Security Baseline policies (Windows, Edge, and M365).

.PARAMETER SourcePath
  Use a local repository path instead of downloading from GitHub (e.g. the root of this repo).

.PARAMETER Force
  Skip the interactive confirmation prompt.

.PARAMETER DryRun
  Connects to Microsoft Graph using read-only scope and performs an inventory run:
  - Builds an index of existing configuration policies
  - Evaluates each selected JSON policy file by policy name
  - Reports whether it would create, update, skip, and/or assign
  No changes are made in Intune.

.PARAMETER UpdateExisting
  If a policy already exists, update it instead of skipping.

.PARAMETER KeepTemplateReference
  Keep templateReference from the JSON instead of forcing Settings Catalog (templateReference cleared).

.PARAMETER GroupAssignmentId
    The Object ID of an Entra ID security group. If specified, all created policies
    will be assigned to this group.

.OUTPUTS
  Status messages on screen.
  Log file at "$env:TEMP\Deploy-SecurityBaselines.log"

.NOTES
  Version:        1.1.0
  Author:         Dustin Gullett / Thiago Beier
  Creation Date:  03/17/2026
  Purpose/Change: Unified deployment + inventory script for all security baselines (adds -DryRun, -WindowsVersion, -SourcePath, -UpdateExisting, and Connect-MgGraph -NoWelcome support).

.EXAMPLE
  .\Deploy-SecurityBaselines.ps1 -InstallAll
  Deploys all baselines (Windows, Edge, and M365).

.EXAMPLE
  .\Deploy-SecurityBaselines.ps1 -InstallWindows -InstallEdge
  Deploys only Windows and Edge baselines.

.EXAMPLE
  .\Deploy-SecurityBaselines.ps1 -InstallAll -GroupAssignmentId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  Deploys all baselines and assigns them to the specified Entra ID group.

.EXAMPLE
  .\Deploy-SecurityBaselines.ps1 -InstallM365 -GroupAssignmentId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  Deploys only M365 baselines and assigns them to the specified group.

.EXAMPLE
  .\Deploy-SecurityBaselines.ps1 -InstallAll -Force -DryRun
  Connects read-only and reports what would be created/updated/assigned (no changes).

.EXAMPLE
  .\Deploy-SecurityBaselines.ps1 -InstallWindows -WindowsVersion 24H2
  Deploys the Windows 11 v24H2 baseline policies.
#>
[CmdletBinding()]
param (
  [switch]$InstallWindows,
  [switch]$InstallEdge,
  [switch]$InstallM365,
  [switch]$InstallAll,

  [Parameter(HelpMessage = "Select which Windows baseline folder to deploy when -InstallWindows is used.")]
  [ValidateSet('24H2', '25H2')]
  [string]$WindowsVersion = '25H2',

  [Parameter(HelpMessage = "Use a local repository path instead of downloading from GitHub (e.g. the root of this repo).")]
  [string]$SourcePath,

  [Parameter(HelpMessage = "Skip the interactive confirmation prompt.")]
  [switch]$Force,

  [Parameter(HelpMessage = "Do not connect to Graph or create/update policies; only show what would happen.")]
  [switch]$DryRun,

  [Parameter(HelpMessage = "If a policy already exists, update it instead of skipping.")]
  [switch]$UpdateExisting,

  [Parameter(HelpMessage = "Keep templateReference from JSON (deploy as baseline-derived) instead of forcing Settings Catalog.")]
  [switch]$KeepTemplateReference,

  [Parameter(HelpMessage = "Entra ID security group Object ID to assign created policies to.")]
  [string]$GroupAssignmentId
)

# ── Validate parameters ─────────────────────────────────────────────────────
if (-not ($InstallWindows -or $InstallEdge -or $InstallM365 -or $InstallAll)) {
  Write-Host ""
  Write-Host "ERROR: You must specify at least one baseline to install." -ForegroundColor Red
  Write-Host ""
  Write-Host "Usage examples:" -ForegroundColor Yellow
  Write-Host "  .\Deploy-SecurityBaselines.ps1 -InstallAll" -ForegroundColor White
  Write-Host "  .\Deploy-SecurityBaselines.ps1 -InstallWindows" -ForegroundColor White
  Write-Host "  .\Deploy-SecurityBaselines.ps1 -InstallWindows -InstallEdge" -ForegroundColor White
  Write-Host "  .\Deploy-SecurityBaselines.ps1 -InstallAll -GroupAssignmentId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'" -ForegroundColor White
  Write-Host ""
  exit 1
}

if ($InstallAll) {
  $InstallWindows = $true
  $InstallEdge = $true
  $InstallM365 = $true
}

# ── Logging ──────────────────────────────────────────────────────────────────
$logFilePath = "$env:TEMP\Deploy-SecurityBaselines.log"

function Write-Log {
  param (
    [string]$Message,
    [string]$Color = "White"
  )
  Write-Host $Message -ForegroundColor $Color
  try {
    Add-Content -Path $logFilePath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message" -ErrorAction Stop
  }
  catch {
    Write-Warning "Unable to write to log file: $logFilePath"
  }
}

function Escape-ODataString {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )
  # OData string literals use single quotes, and single quotes are escaped by doubling.
  return $Value -replace "'", "''"
}

function Get-ExistingConfigurationPolicyByName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$PolicyName
  )

  $escapedName = Escape-ODataString -Value $PolicyName
  $filter = "name eq '$escapedName'"
  $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$select=id,name&`$filter=$([uri]::EscapeDataString($filter))"

  try {
    $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
    if ($null -ne $response.value -and $response.value.Count -gt 0) {
      return $response.value[0]
    }
  }
  catch {
    Write-Log "      WARNING: Failed to query existing policies (will attempt create) - $_" "Yellow"
  }

  return $null
}

function Get-ExistingConfigurationPolicyIndex {
  $index = @{}
  $uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies?`$select=id,name&`$top=999"

  try {
    while ($uri) {
      $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
      foreach ($p in @($response.value)) {
        if ($p.name -and $p.id) {
          $index[$p.name] = $p.id
        }
      }
      $uri = $response.'@odata.nextLink'
    }
  }
  catch {
    Write-Log "  WARNING: Failed to build existing policy index - $_" "Yellow"
  }

  return $index
}

function Remove-JsonReadOnlyFields {
  param(
    [Parameter(Mandatory = $true)]
    [object]$JsonObject
  )

  foreach ($prop in @(
      '@odata.context',
      'id',
      'createdDateTime',
      'lastModifiedDateTime',
      'settingCount',
      'creationSource',
      'priorityMetaData'
    )) {
    $null = $JsonObject.PSObject.Properties.Remove($prop)
  }

  return $JsonObject
}

# ── Display settings ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Security Baselines - Intune Policy Deployment              " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$selectedBaselines = @()
if ($InstallWindows) { $selectedBaselines += "Windows 11 v$WindowsVersion" }
if ($InstallEdge) { $selectedBaselines += "Microsoft Edge v128" }
if ($InstallM365) { $selectedBaselines += "Microsoft 365 Apps" }

Write-Log "  Baselines selected : $($selectedBaselines -join ', ')" "Yellow"

if ($GroupAssignmentId) {
  Write-Log "  Group assignment   : $GroupAssignmentId" "Yellow"
}
else {
  Write-Log "  Group assignment   : None (policies will be unassigned)" "Yellow"
}

Write-Host ""

if (-not $Force) {
  $proceed = Read-Host "Continue with these settings? (Y/N)"
  if ($proceed -notin @('Y', 'y')) {
    Write-Log "Script aborted by user." "Red"
    exit
  }
}

# ── Step 1 - Download and extract ────────────────────────────────────────────
Write-Log "Step 1: Acquire baseline files" "Cyan"

$tempFolder = $null

if ($SourcePath) {
  if (-not (Test-Path -Path $SourcePath -PathType Container)) {
    Write-Log "  ERROR: SourcePath not found - $SourcePath" "Red"
    exit 1
  }

  $repoRoot = (Resolve-Path -Path $SourcePath).Path
  Write-Log "  Using local source path: $repoRoot" "Green"
}
else {
  $fileUrl = "https://github.com/dgulle/Security-Baselines/archive/refs/heads/master.zip"
  $tempFolder = Join-Path $env:TEMP "SecurityBaselines_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
  $destinationZip = Join-Path $tempFolder "master.zip"

  New-Item -Path $tempFolder -ItemType Directory -Force | Out-Null

  try {
    Write-Log "  Downloading repository archive..." "Cyan"
    Invoke-WebRequest -Uri $fileUrl -OutFile $destinationZip -UseBasicParsing -ErrorAction Stop
    Write-Log "  Download complete." "Green"
  }
  catch {
    Write-Log "  ERROR: Failed to download - $_" "Red"
    exit 1
  }

  try {
    Write-Log "  Extracting archive..." "Cyan"
    Expand-Archive -Path $destinationZip -DestinationPath $tempFolder -Force -ErrorAction Stop
    Write-Log "  Extraction complete." "Green"
  }
  catch {
    Write-Log "  ERROR: Failed to extract - $_" "Red"
    exit 1
  }

  $repoRoot = Join-Path $tempFolder "Security-Baselines-master"
}

# ── Step 2 - Microsoft Graph module ──────────────────────────────────────────
Write-Log "Step 2: Verify Microsoft.Graph.Beta module" "Cyan"

$moduleName = "Microsoft.Graph.Beta"
$module = Get-InstalledModule -Name $moduleName -ErrorAction SilentlyContinue

if (-not $module) {
  Write-Log "  $moduleName is not installed. Installing for current user..." "Yellow"
  try {
    Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    Write-Log "  $moduleName installed successfully." "Green"
  }
  catch {
    Write-Log "  ERROR: Failed to install $moduleName - $_" "Red"
    exit 1
  }
}
else {
  Write-Log "  $moduleName is already installed." "Green"
}

try {
  # Remove any previously loaded Microsoft.Graph modules to avoid assembly version conflicts
  Write-Log "  Removing any previously loaded Microsoft.Graph modules..." "Cyan"
  Get-Module Microsoft.Graph* | Remove-Module -Force -ErrorAction SilentlyContinue

  # Clean up duplicate Microsoft.Graph.Authentication versions that cause assembly conflicts
  $authVersions = Get-Module -Name Microsoft.Graph.Authentication -ListAvailable
  if ($authVersions.Count -gt 1) {
    Write-Log "  Multiple versions of Microsoft.Graph.Authentication detected. Cleaning up old versions..." "Yellow"
    $latest = $authVersions | Sort-Object Version -Descending | Select-Object -First 1
    foreach ($oldVersion in ($authVersions | Where-Object { $_.Version -ne $latest.Version })) {
      try {
        Uninstall-Module -Name Microsoft.Graph.Authentication -RequiredVersion $oldVersion.Version -Force -ErrorAction SilentlyContinue
        Write-Log "    Removed Microsoft.Graph.Authentication v$($oldVersion.Version)" "Yellow"
      }
      catch {
        Write-Log "    Could not remove Microsoft.Graph.Authentication v$($oldVersion.Version) - $_" "Yellow"
      }
    }
  }

  # Import Authentication module first so the correct version is loaded before dependent modules
  Write-Log "  Importing Microsoft.Graph.Authentication..." "Cyan"
  Import-Module Microsoft.Graph.Authentication -Force -ErrorAction Stop

  Write-Log "  Importing Microsoft.Graph.Beta.DeviceManagement..." "Cyan"
  Import-Module Microsoft.Graph.Beta.DeviceManagement -Force -ErrorAction Stop

  Write-Log "  Connecting to Microsoft Graph..." "Cyan"
  if ($DryRun) {
    Write-Log "  Dry run enabled: connecting with read-only scope." "Yellow"
    $scopes = @(
      "DeviceManagementConfiguration.Read.All"
    )
  }
  else {
    $scopes = @(
      "DeviceManagementConfiguration.Read.All",
      "DeviceManagementConfiguration.ReadWrite.All"
    )
  }
  if ($GroupAssignmentId) {
    $scopes += "Group.Read.All"
  }

  $connectParams = @{
    Scopes      = $scopes
    ErrorAction = 'Stop'
  }
  if ((Get-Command Connect-MgGraph -ErrorAction SilentlyContinue).Parameters.ContainsKey('NoWelcome')) {
    $connectParams.NoWelcome = $true
  }

  Connect-MgGraph @connectParams
}
catch {
  Write-Log "  ERROR: Failed to import module or connect to Microsoft Graph - $_" "Red"
  Write-Log "  TIP: Try running 'Uninstall-Module Microsoft.Graph -AllVersions -Force' and 'Update-Module Microsoft.Graph.Beta -Force', then re-run in a new PowerShell session." "Yellow"
  exit 1
}

# ── Helper function - Deploy baseline policies ──────────────────────────────
function Deploy-BaselinePolicies {
  param (
    [string]$BaselineName,
    [string]$JsonPath,
    [string]$GroupId,
    [hashtable]$ExistingPolicyIndex,
    [switch]$UpdateExisting,
    [switch]$DryRun,
    [switch]$KeepTemplateReference
  )

  Write-Log ""
  Write-Log "  -- $BaselineName --" "Cyan"

  if (-not (Test-Path -Path $JsonPath)) {
    Write-Log "    ERROR: Path not found - $JsonPath" "Red"
    return @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0 }
  }

  # Get JSON files from the root of the baseline directory only (not subdirectories)
  $jsonFiles = Get-ChildItem -Path $JsonPath -Filter *.json -File | Sort-Object -Property Name
  Write-Log "    Found $($jsonFiles.Count) policy file(s)" "Green"

  $result = @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0 }

  foreach ($file in $jsonFiles) {
    try {
      $jsonContent = Get-Content -Path $file.FullName -Raw -ErrorAction Stop

      $jsonObject = $jsonContent | ConvertFrom-Json

      $desiredPolicyName = $jsonObject.name
      if ([string]::IsNullOrWhiteSpace($desiredPolicyName)) {
        $desiredPolicyName = $file.BaseName
      }

      Write-Log "    Processing: $desiredPolicyName" "Cyan"

      # Check for existing policy with the same name
      $existingPolicyId = $null
      if ($ExistingPolicyIndex -and $ExistingPolicyIndex.ContainsKey($desiredPolicyName)) {
        $existingPolicyId = $ExistingPolicyIndex[$desiredPolicyName]
      }

      if (-not $KeepTemplateReference) {
        # Strip templateReference so policies are created as Settings Catalog, not Security Baselines
        $jsonObject.templateReference = @{
          templateId             = ""
          templateFamily         = "none"
          templateDisplayName    = $null
          templateDisplayVersion = $null
        }
      }

      $jsonObject = Remove-JsonReadOnlyFields -JsonObject $jsonObject
      $jsonContent = $jsonObject | ConvertTo-Json -Depth 100

      if ($existingPolicyId) {
        if (-not $UpdateExisting) {
          Write-Log "      Skipped - policy already exists." "Yellow"
          $result.Skipped++
          continue
        }

        if ($DryRun) {
          Write-Log "      DRY RUN: Would update existing policy ($existingPolicyId)." "Yellow"
          $result.Updated++
        }
        else {
          Invoke-MgGraphRequest -Method PATCH `
            -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$existingPolicyId" `
            -Body $jsonContent -ContentType "application/json" -ErrorAction Stop

          Write-Log "      Updated successfully." "Green"
          $result.Updated++
        }
      }
      else {
        if ($DryRun) {
          Write-Log "      DRY RUN: Would create policy." "Yellow"
          $result.Created++
          $newPolicyId = $null
        }
        else {
          # Use direct Graph request so the JSON is sent as-is (avoids BodyParameter type coercion issues)
          $newPolicy = Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" `
            -Body $jsonContent -ContentType "application/json" -ErrorAction Stop

          $newPolicyId = $newPolicy.id
          if ($ExistingPolicyIndex -and $newPolicyId) {
            $ExistingPolicyIndex[$desiredPolicyName] = $newPolicyId
          }

          Write-Log "      Created successfully." "Green"
          $result.Created++
        }
      }

      # Assign to group if specified
      if ($GroupId) {
        $policyIdForAssign = $existingPolicyId
        if (-not $policyIdForAssign) {
          $policyIdForAssign = $newPolicyId
        }

        if (-not $policyIdForAssign) {
          Write-Log "      WARNING: Cannot assign (no policy id available)." "Yellow"
          continue
        }

        try {
          $assignBody = @{
            assignments = @(
              @{
                target = @{
                  "@odata.type" = "#microsoft.graph.groupAssignmentTarget"
                  groupId       = $GroupId
                }
              }
            )
          } | ConvertTo-Json -Depth 10

          if ($DryRun) {
            Write-Log "      DRY RUN: Would assign to group $GroupId" "Yellow"
          }
          else {
            Invoke-MgGraphRequest -Method POST `
              -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/$policyIdForAssign/assign" `
              -Body $assignBody -ContentType "application/json" -ErrorAction Stop

            Write-Log "      Assigned to group $GroupId" "Green"
          }
        }
        catch {
          Write-Log "      WARNING: Created but failed to assign - $_" "Yellow"
        }
      }
    }
    catch {
      Write-Log "      ERROR: Failed to create policy - $_" "Red"
      $result.Failed++
    }
  }

  return $result
}

# ── Step 3 - Deploy selected baselines ──────────────────────────────────────
Write-Log "Step 3: Deploy selected baselines" "Cyan"

$totals = @{ Created = 0; Updated = 0; Skipped = 0; Failed = 0 }

$existingPolicyIndex = $null
Write-Log "  Building existing policy index..." "Cyan"
$existingPolicyIndex = Get-ExistingConfigurationPolicyIndex
Write-Log "  Existing policies indexed: $($existingPolicyIndex.Count)" "Green"

$baselines = @()
if ($InstallWindows) {
  $baselines += @{
    Name = "Windows 11 v$WindowsVersion"
    Path = Join-Path $repoRoot "Windows Baseline $WindowsVersion"
  }
}
if ($InstallEdge) {
  $baselines += @{
    Name = "Microsoft Edge v128"
    Path = Join-Path $repoRoot "Edge Baseline"
  }
}
if ($InstallM365) {
  $baselines += @{
    Name = "Microsoft 365 Apps"
    Path = Join-Path $repoRoot "M365 Baseline"
  }
}

foreach ($baseline in $baselines) {
  $result = Deploy-BaselinePolicies -BaselineName $baseline.Name -JsonPath $baseline.Path -GroupId $GroupAssignmentId -ExistingPolicyIndex $existingPolicyIndex -UpdateExisting:$UpdateExisting -DryRun:$DryRun -KeepTemplateReference:$KeepTemplateReference
  $totals.Created += $result.Created
  $totals.Updated += $result.Updated
  $totals.Skipped += $result.Skipped
  $totals.Failed += $result.Failed
}

# ── Step 4 - Cleanup ────────────────────────────────────────────────────────
Write-Log ""
Write-Log "Step 4: Cleanup temporary files" "Cyan"
if ($tempFolder) {
  try {
    Remove-Item -Path $tempFolder -Recurse -Force -ErrorAction Stop
    Write-Log "  Temporary files removed." "Green"
  }
  catch {
    Write-Log "  WARNING: Could not remove temp folder - $tempFolder" "Yellow"
  }
}
else {
  Write-Log "  No temp folder to clean up." "Green"
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Deployment Summary                                        " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Log "  Baselines deployed : $($selectedBaselines -join ', ')" "Cyan"
Write-Log "  Policies created   : $($totals.Created)"  "Green"
if ($totals.Updated -gt 0) {
  Write-Log "  Policies updated   : $($totals.Updated)"  "Green"
}
Write-Log "  Policies skipped   : $($totals.Skipped)"  "Yellow"
if ($totals.Failed -gt 0) {
  Write-Log "  Policies failed    : $($totals.Failed)"   "Red"
}
Write-Log "  Total processed    : $($totals.Created + $totals.Updated + $totals.Skipped + $totals.Failed)" "Cyan"
if ($GroupAssignmentId) {
  Write-Log "  Group assignment   : $GroupAssignmentId" "Cyan"
}
Write-Log "  Log file           : $logFilePath" "Cyan"
Write-Host ""
Write-Log "Deployment completed." "Green"
