<#
.SYNOPSIS
  Creates Windows 11 v24H2 Security Baseline policies in Intune from GitHub files projets from Dustin Gullett
  https://www.linkedin.com/in/dustin-gullett-83607b1ba/ ,   https://github.com/dgulle/Security-Baselines
  Post reference: https://www.getrubix.com/blog/rolling-out-intune-security-baselines-without-causing-a-workplace-uprising

.DESCRIPTION
    Read Security-Baselines-master\Windows Baseline 24H2 json files one by one
    Parse as $params variable
    Create new policy in Intune for each json file from Windows Baseline 24H2

.INPUTS
    -folderPath : The path to the folder where the GitHub file will be downloaded and extracted (optional)
        If not provided, the script will use a default path.
    -fileUrl : The GitHub raw file URL to download a zip file (optional)
        If not provided, the script will use a default URL.

.OUTPUTS
  Status messages on screen.
  Log file to "$env:TEMP\Create-Windows-11-v24H2-Security-Baseline.log" ,  %temp%\Create-Windows-11-v24H2-Security-Baseline.log

.NOTES
  Version:        1.0.1
  Author:         Thiago Beier
  Creation Date:  02/18/2025
  Purpose/Change: Updates suggested by Jessie S. (https://www.linkedin.com/in/jessies/)
  Updated Date:   02/18/2025

.EXAMPLE
  .\Create-Windows-11-v24H2-Security-Baseline.ps1 -folderPath "C:\Path\To\Download" -fileUrl "https://github.com/dgulle/Security-Baselines/archive/refs/heads/master.zip"
#>

param (
  [string]$folderPath = "C:\temp\Windows 11 v24H2 Security Baseline", # Default path for downloading and extracting the file
  [string]$fileUrl = "https://github.com/dgulle/Security-Baselines/archive/refs/heads/master.zip"  # Default GitHub file URL
)

# Log file location
$logFilePath = "$env:TEMP\Create-Windows-11-v24H2-Security-Baseline.log"

# Function to log messages to both console and log file
function Log-Message {
  param (
    [string]$message
  )

  # Write message to console
  Write-Host $message

  # Write message to log file
  Add-Content -Path $logFilePath -Value "$(Get-Date) - $message"
}

# Start logging
Log-Message "Starting script execution..."

# Ask user to confirm default parameters or input their own values
Log-Message "Current settings:"
Log-Message "Folder path: $folderPath"
Log-Message "File URL: $fileUrl"

$confirmation = Read-Host "Do you want to continue with the default settings? (Y/N)"

if ($confirmation -ne 'Y') {
  # Prompt for new values if user chooses not to continue with the default
  $folderPath = Read-Host "Enter the folder path for download and extraction (Default: C:\temp\Windows 11 v24H2 Security Baseline)"
  if (-not $folderPath) {
    $folderPath = "C:\temp\Windows 11 v24H2 Security Baseline"  # Revert to default if no input
  }
    
  $fileUrl = Read-Host "Enter the GitHub file URL to download (Default: https://github.com/dgulle/Security-Baselines/archive/refs/heads/master.zip)"
  if (-not $fileUrl) {
    $fileUrl = "https://github.com/dgulle/Security-Baselines/archive/refs/heads/master.zip"  # Revert to default if no input
  }
}

Log-Message "Using the following settings:"
Log-Message "Folder path: $folderPath"
Log-Message "File URL: $fileUrl"

# Function to download and extract GitHub file
function DownloadAndExtract-GitHubFile {
  param (
    [string]$fileUrl, # The GitHub raw file URL
    [string]$destinationFolder      # The folder where to download and extract the file
  )

  # Define the target file path
  $destinationPath = "$destinationFolder\master.zip"

  # Check if the destination folder exists, if not, create it
  if (-not (Test-Path -Path $destinationFolder)) {
    Log-Message "Folder does not exist. Creating folder: $destinationFolder"
    New-Item -Path $destinationFolder -ItemType Directory
  }
  else {
    Log-Message "Folder already exists: $destinationFolder"
  }

  # Download the file from GitHub to the target folder
  Log-Message "Downloading file from $fileUrl to $destinationPath"
  Invoke-WebRequest -Uri $fileUrl -OutFile $destinationPath

  Log-Message "Download complete!"

  # Extract the zip file to the root of the destination folder
  Log-Message "Extracting $destinationPath to $destinationFolder"
  Expand-Archive -Path $destinationPath -DestinationPath $destinationFolder -Force

  Log-Message "Extraction complete!"
}

# If the fileUrl and destinationFolder are provided, download and extract the GitHub file
if ($fileUrl -and $folderPath) {
  DownloadAndExtract-GitHubFile -fileUrl $fileUrl -destinationFolder $folderPath
}

# Check if Microsoft.Graph.Beta module is installed
$moduleName = "Microsoft.Graph.Beta"
$module = Get-InstalledModule -Name $moduleName -ErrorAction SilentlyContinue

# If the module is not installed, install it for the current user
if (-not $module) {
  Log-Message "$moduleName module is not installed. Installing for the current user..."
  Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber
}
else {
  Log-Message "$moduleName module is already installed."
  Import-Module Microsoft.Graph.Beta.DeviceManagement
  Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All", "DeviceManagementConfiguration.ReadWrite.All"
}

# Prompt user for path if it's not provided
$defaultPath = Join-Path $folderPath "Security-Baselines-master\Windows Baseline 24H2" #fixed by https://www.linkedin.com/in/jessies/
if (-not $defaultPath) {
  $defaultPath = Read-Host "Enter the path to the Windows Baseline 24H2 folder (Press Enter to use the default: $defaultPath)"
}

# If the user didn't enter a path, confirm using the default
if ($defaultPath) {
  $confirmation = Read-Host "The following path will be used: $defaultPath. Do you want to proceed? (Y/N)"
  if ($confirmation -ne 'Y') {
    Log-Message "Script aborted."
    exit
  }
}

# Loop through all Baseline files
function invoke-list-WindowsBaseline24H2-files {
  param (
    [string]$path
  )

  Get-ChildItem -Path $path -Recurse -Filter *.json | ForEach-Object {
    [PSCustomObject]@{
      Name = $_.Name
    }
  }
}

$alljsonfiles = invoke-list-WindowsBaseline24H2-files -path $defaultPath

foreach ($jsonfile in $alljsonfiles) {
  $item = $($jsonfile.Name)
  $policyname = $item -replace '.json$', ''  # This removes the ".json" extension

  Log-Message "Working on baseline: $policyname"

  # Check if a policy with the same name already exists
  $existingPolicy = Get-MgBetaDeviceManagementConfigurationPolicy | Where-Object { $_.Name -eq $policyname } #updated 20225-02-19

  if (!$existingPolicy) {
    Log-Message "No existing policy with the name '$policyname'. Proceeding with creation."

    # Read the content of the JSON template file
    $jsonContent = Get-Content -Path "$defaultPath\$item" -Raw
    $params = $jsonContent

    Log-Message "Creating baseline Policy: $policyname"
    New-MgBetaDeviceManagementConfigurationPolicy -BodyParameter $params
    
  }
  else {
    Log-Message "A policy with the name '$policyname' already exists. Skipping creation."
  }
}

Log-Message "Script execution completed."
