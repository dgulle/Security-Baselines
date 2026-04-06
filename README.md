# Intune Security Baselines

Intune Security Baseline JSON configuration files and automated deployment scripts for Microsoft Intune.

## Available Baselines

| Baseline | Policies | Directory |
|---|---|---|
| Windows 11 v25H2 | 28 | `Windows Baseline 25H2/` |
| Microsoft Edge v128 | 7 | `Edge Baseline/` |
| Microsoft 365 Apps | 12 | `M365 Baseline/` |

> **Note:** The Windows Security Baseline does not include the LAPS category setting for Backup Directory. This setting does not appear in the Settings Catalog.

## Settings Added in 25H2

| Setting | Location | 25H2 Default | Notes |
|---------|----------|-------------|-------|
| Include command line in process creation events | Admin Templates > System > Audit Process Creation | Enabled | Captures full command-line args in Event ID 4688. Be aware that passwords passed via CLI will also be logged. |
| Block process creations originating from PSExec and WMI commands | Defender > ASR Rules (under Allow Script Scanning) | Audit | GUID: `d1e49aac-8f56-4280-b9ba-993a6d77406c`. Audit-only to avoid breaking legitimate admin tooling. |
| Impersonate Client - Windows restricted services (PrintSpoolerService) | User Rights > Impersonate Client | Added SID `S-1-5-99-216390572-1995538116-3857911515-2404958512-2623887229` | Supports Windows Protected Print (WPP). Removing this entry will break printing in WPP environments. SID may appear as raw value in Group Policy tools until service initializes. |

## Settings Removed in 25H2

| Setting | Location | 24H2 Default | Reason for Removal |
|---------|----------|-------------|-------------------|
| WDigest Authentication (disabling may require KB2871997) | Admin Templates > MS Security Guide | Disabled | Deprecated in 24H2. WDigest credential caching disabled by default since Windows 8.1. Existing registry values at `UseLogonCredential` will not auto-clean from prior deployments. |
| Scan packed executables | Admin Templates > Microsoft Defender Antivirus > Scan | Enabled | No longer functional. Defender always scans packed executables by default now. |
| Hide Exclusions From Local Users | Defender CSP | Enabled (hidden from local users) | Redundant. Parent setting "Hide Exclusions From Local Admins" (still present and enabled) takes precedence. |

## Quick Start

Download and run the deployment script directly in PowerShell:

```powershell
irm "https://raw.githubusercontent.com/dgulle/Security-Baselines/master/Deploy-SecurityBaselines.ps1" -OutFile "$env:TEMP\Deploy-SecurityBaselines.ps1"; & "$env:TEMP\Deploy-SecurityBaselines.ps1" -InstallAll
```

## Deploy-SecurityBaselines.ps1

Unified deployment script that downloads the baseline JSON files from this repository, creates the corresponding Intune device management configuration policies via Microsoft Graph, and cleans up temporary files automatically.

### Prerequisites

- PowerShell 5.1 or later
- Internet access to download from GitHub and connect to Microsoft Graph
- An Entra ID account with **Intune Administrator** or equivalent permissions
- The `Microsoft.Graph.Beta` module (the script will install it automatically if missing)

### Parameters

| Parameter | Type | Description |
|---|---|---|
| `-InstallWindows` | Switch | Deploy Windows 11 v25H2 Security Baseline policies |
| `-InstallEdge` | Switch | Deploy Microsoft Edge v128 Security Baseline policies |
| `-InstallM365` | Switch | Deploy Microsoft 365 Apps Security Baseline policies |
| `-InstallAll` | Switch | Deploy all available baselines (Windows, Edge, and M365) |
| `-GroupAssignmentId` | String | Entra ID security group Object ID to assign all created policies to |

### Usage Examples

**Deploy all baselines:**

```powershell
.\Deploy-SecurityBaselines.ps1 -InstallAll
```

**Deploy only Windows and Edge baselines:**

```powershell
.\Deploy-SecurityBaselines.ps1 -InstallWindows -InstallEdge
```

**Deploy all baselines and assign to a security group:**

```powershell
.\Deploy-SecurityBaselines.ps1 -InstallAll -GroupAssignmentId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**Deploy only M365 baselines with group assignment:**

```powershell
.\Deploy-SecurityBaselines.ps1 -InstallM365 -GroupAssignmentId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### What the Script Does

1. Displays selected baselines and prompts for confirmation
2. Downloads and extracts the repository archive to a temporary folder
3. Installs/imports the `Microsoft.Graph.Beta` module and authenticates to Microsoft Graph
4. Creates Intune configuration policies from the JSON files (skips any that already exist by name)
5. Optionally assigns each created policy to the specified Entra ID security group
6. Cleans up all temporary files
7. Displays a summary of created, skipped, and failed policies

### Logs

A log file is written to `%TEMP%\Deploy-SecurityBaselines.log` with timestamps for each operation.

## Repository Structure

```
Security-Baselines/
├── Deploy-SecurityBaselines.ps1                          # Unified deployment script
├── Create-Windows-11-v25H2-Security-Baseline.ps1         # Windows-only deployment script
├── GPO_Export_Template.xlsx
├── README.md
├── Windows Baseline 25H2/
│   ├── Security Baseline 25H2 - Administrative Templates.json
│   ├── Security Baseline 25H2 - Auditing.json
│   ├── Security Baseline 25H2 - Browser.json
│   ├── ...                                               # 28 policy JSON files
│   └── UAT Form.xlsx
├── Edge Baseline/
│   ├── Edge Baseline - v128_Extensions.json
│   ├── Edge Baseline - v128_Microsoft Edge.json
│   ├── ...                                               # 7 policy JSON files
│   └── Baseline Template and Script/                     # Export script (not for deployment)
│       ├── MS_Edge_Baseline_Export.ps1
│       └── Edge Baseline - v128.json
└── M365 Baseline/
    ├── Access.json
    ├── Excel.json
    ├── Outlook.json
    ├── ...                                               # 12 policy JSON files
    └── Baseline Template and Script/                     # Export script (not for deployment)
        ├── M365 Baselines Export.ps1
        └── M365 Baseline Template.json
```

## Export Scripts

The `Baseline Template and Script/` subdirectories contain utility scripts for exporting new baselines from Intune. These are used to maintain and update the JSON files in this repository and are **not** part of the deployment process.

- **MS_Edge_Baseline_Export.ps1** - Exports and splits Edge baseline policies by category
- **M365 Baselines Export.ps1** - Exports and splits M365 baseline policies by application

## Credits

- [Dustin Gullett](https://www.linkedin.com/in/dustin-gullett-83607b1ba/) - Repository maintainer
- [Thiago Beier](https://www.youracclaim.com/) - Deployment script author
- Blog post: [Rolling Out Intune Security Baselines Without Causing a Workplace Uprising](https://zerototrust.tech/rolling-out-intune-security-baselines-without-causing-a-workplace-uprising/)
