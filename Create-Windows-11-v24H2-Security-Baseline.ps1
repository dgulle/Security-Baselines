<#
.SYNOPSIS
  Creates Windows 11 v24H2 Security Baseline policies in Intune from GitHub files projets from Dustin Gullett
  https://www.linkedin.com/in/dustin-gullett-83607b1ba/ ,   https://github.com/dgulle/Security-Baselines
  Post reference: https://zerototrust.tech/rolling-out-intune-security-baselines-without-causing-a-workplace-uprising/

.DESCRIPTION
    Downloads the Security-Baselines repository from GitHub, extracts the Windows Baseline 24H2
    JSON files, and creates a new Intune device management configuration policy for each one.
    Existing policies with the same name are skipped. A log file and final summary are produced.

.PARAMETER FolderPath
    The local folder used to download and extract the GitHub archive.
    Default: C:\temp\Windows 11 v24H2 Security Baseline

.PARAMETER FileUrl
    The URL of the GitHub zip archive to download.
    Default: https://github.com/dgulle/Security-Baselines/archive/refs/heads/master.zip

.OUTPUTS
  Status messages on screen.
  Log file at "$env:TEMP\Create-Windows-11-v24H2-Security-Baseline.log"

.NOTES
  Version:        2.0.0
  Author:         Thiago Beier
  Creation Date:  02/18/2025
  Purpose/Change: Rewritten for clarity and improved user experience.
  Updated Date:   03/12/2026

.EXAMPLE
  .\Create-Windows-11-v24H2-Security-Baseline.ps1
  Runs with default settings after user confirmation.

.EXAMPLE
  .\Create-Windows-11-v24H2-Security-Baseline.ps1 -FolderPath "C:\MyBaselines" -FileUrl "https://github.com/dgulle/Security-Baselines/archive/refs/heads/master.zip"
  Runs with custom folder path and URL.
#>
[CmdletBinding()]
param (
  [Parameter(HelpMessage = "Local folder for downloading and extracting the GitHub archive.")]
  [string]$FolderPath = "C:\temp\Windows 11 v24H2 Security Baseline",

  [Parameter(HelpMessage = "URL of the GitHub zip archive to download.")]
  [string]$FileUrl = "https://github.com/dgulle/Security-Baselines/archive/refs/heads/master.zip"
)

# ── Logging ──────────────────────────────────────────────────────────────────
$logFilePath = "$env:TEMP\Create-Windows-11-v24H2-Security-Baseline.log"

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

# ── Step 1 – Confirm settings ───────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Windows 11 v24H2 Security Baseline – Intune Policy Setup  " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Log "Step 1: Review settings"
Write-Host "  Folder path : $FolderPath" -ForegroundColor Yellow
Write-Host "  File URL    : $FileUrl"    -ForegroundColor Yellow
Write-Host ""

$proceed = Read-Host "Continue with these settings? (Y/N)"
if ($proceed -notin @('Y', 'y')) {
  $newFolder = Read-Host "  Enter folder path (press Enter to keep default)"
  if ($newFolder) { $FolderPath = $newFolder }

  $newUrl = Read-Host "  Enter file URL (press Enter to keep default)"
  if ($newUrl) { $FileUrl = $newUrl }

  Write-Host ""
  Write-Host "  Updated folder path : $FolderPath" -ForegroundColor Yellow
  Write-Host "  Updated file URL    : $FileUrl"    -ForegroundColor Yellow
  Write-Host ""

  $confirm = Read-Host "Proceed with updated settings? (Y/N)"
  if ($confirm -notin @('Y', 'y')) {
    Write-Log "Script aborted by user." "Red"
    exit
  }
}

Write-Log "Settings confirmed." "Green"

# ── Step 2 – Download and extract the baseline archive ───────────────────────
Write-Log "Step 2: Download and extract baseline archive" "Cyan"

$destinationZip = Join-Path $FolderPath "master.zip"

# Create folder if needed
if (-not (Test-Path -Path $FolderPath)) {
  Write-Log "  Creating folder: $FolderPath" "Cyan"
  New-Item -Path $FolderPath -ItemType Directory -Force | Out-Null
}

try {
  Write-Log "  Downloading $FileUrl ..." "Cyan"
  Invoke-WebRequest -Uri $FileUrl -OutFile $destinationZip -UseBasicParsing -ErrorAction Stop
  Write-Log "  Download complete." "Green"
}
catch {
  Write-Log "  ERROR: Failed to download file – $_" "Red"
  exit 1
}

try {
  Write-Log "  Extracting archive to $FolderPath ..." "Cyan"
  Expand-Archive -Path $destinationZip -DestinationPath $FolderPath -Force -ErrorAction Stop
  Write-Log "  Extraction complete." "Green"
}
catch {
  Write-Log "  ERROR: Failed to extract archive – $_" "Red"
  exit 1
}

# ── Step 3 – Ensure the Microsoft.Graph.Beta module is available ─────────────
Write-Log "Step 3: Verify Microsoft.Graph.Beta module" "Cyan"

$moduleName = "Microsoft.Graph.Beta"
$module = Get-InstalledModule -Name $moduleName -ErrorAction SilentlyContinue

if (-not $module) {
  Write-Log "  $moduleName is not installed. Installing for current user..." "Yellow"
  try {
    Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    Write-Log "  $moduleName installed successfully." "Green"
  }
  catch {
    Write-Log "  ERROR: Failed to install $moduleName – $_" "Red"
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
        Write-Log "    Could not remove Microsoft.Graph.Authentication v$($oldVersion.Version) – $_" "Yellow"
      }
    }
  }

  # Import Authentication module first so the correct version is loaded before dependent modules
  Write-Log "  Importing Microsoft.Graph.Authentication..." "Cyan"
  Import-Module Microsoft.Graph.Authentication -Force -ErrorAction Stop

  Write-Log "  Importing Microsoft.Graph.Beta.DeviceManagement..." "Cyan"
  Import-Module Microsoft.Graph.Beta.DeviceManagement -Force -ErrorAction Stop

  Write-Log "  Connecting to Microsoft Graph..." "Cyan"
  Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All", "DeviceManagementConfiguration.ReadWrite.All" -ErrorAction Stop
}
catch {
  Write-Log "  ERROR: Failed to import module or connect to Microsoft Graph – $_" "Red"
  Write-Log "  TIP: Try running 'Uninstall-Module Microsoft.Graph -AllVersions -Force' and 'Update-Module Microsoft.Graph.Beta -Force', then re-run in a new PowerShell session." "Yellow"
  exit 1
}

# ── Step 4 – Locate baseline JSON files ──────────────────────────────────────
Write-Log "Step 4: Locate baseline JSON files" "Cyan"

$baselinePath = Join-Path $FolderPath "Security-Baselines-master\Windows Baseline 24H2"

if (-not (Test-Path -Path $baselinePath)) {
  Write-Log "  ERROR: Baseline folder not found at $baselinePath" "Red"
  exit 1
}

$jsonFiles = Get-ChildItem -Path $baselinePath -Filter *.json -Recurse
Write-Log "  Found $($jsonFiles.Count) JSON baseline file(s) in $baselinePath" "Green"

if ($jsonFiles.Count -eq 0) {
  Write-Log "  No JSON files to process. Exiting." "Yellow"
  exit
}

# ── Step 5 – Create Intune policies ──────────────────────────────────────────
Write-Log "Step 5: Create Intune policies" "Cyan"

$created  = 0
$skipped  = 0

foreach ($file in $jsonFiles) {
  $policyName = $file.BaseName    # filename without extension

  Write-Log "  Processing: $policyName" "Cyan"

  # Check for existing policy
  $existingPolicy = Get-MgBetaDeviceManagementConfigurationPolicy |
    Where-Object { $_.Name -eq $policyName }

  if ($existingPolicy) {
    Write-Log "    Skipped – policy already exists." "Yellow"
    $skipped++
    continue
  }

  try {
    $jsonContent = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
    New-MgBetaDeviceManagementConfigurationPolicy -BodyParameter $jsonContent -ErrorAction Stop
    Write-Log "    Created successfully." "Green"
    $created++
  }
  catch {
    Write-Log "    ERROR: Failed to create policy – $_" "Red"
  }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Summary                                                    " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Log "  Policies created : $created"  "Green"
Write-Log "  Policies skipped : $skipped"  "Yellow"
Write-Log "  Total processed  : $($created + $skipped)" "Cyan"
Write-Log "  Log file         : $logFilePath" "Cyan"
Write-Host ""
Write-Log "Script execution completed." "Green"
