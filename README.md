# Intune Security Baselines

Intune Security Baseline JSON configuration files and automated deployment scripts for Microsoft Intune.

## Available Baselines

| Baseline            | Policies | Directory                |
| ------------------- | -------- | ------------------------ |
| Windows 11 v25H2    | 28       | `Windows Baseline 25H2/` |
| Microsoft Edge v128 | 7        | `Edge Baseline/`         |
| Microsoft 365 Apps  | 12       | `M365 Baseline/`         |

> **Note:** The Windows Security Baseline does not include the LAPS category setting for Backup Directory. This setting does not appear in the Settings Catalog.

## Settings Added in 25H2

| Setting                                                                | Location                                           | 25H2 Default                                                               | Notes                                                                                                                                                                             |
| ---------------------------------------------------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Include command line in process creation events                        | Admin Templates > System > Audit Process Creation  | Enabled                                                                    | Captures full command-line args in Event ID 4688. Be aware that passwords passed via CLI will also be logged.                                                                     |
| Block process creations originating from PSExec and WMI commands       | Defender > ASR Rules (under Allow Script Scanning) | Audit                                                                      | GUID: `d1e49aac-8f56-4280-b9ba-993a6d77406c`. Audit-only to avoid breaking legitimate admin tooling.                                                                              |
| Impersonate Client - Windows restricted services (PrintSpoolerService) | User Rights > Impersonate Client                   | Added SID `S-1-5-99-216390572-1995538116-3857911515-2404958512-2623887229` | Supports Windows Protected Print (WPP). Removing this entry will break printing in WPP environments. SID may appear as raw value in Group Policy tools until service initializes. |

## Settings Removed in 25H2

| Setting                                                  | Location                                              | 24H2 Default                      | Reason for Removal                                                                                                                                                                 |
| -------------------------------------------------------- | ----------------------------------------------------- | --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| WDigest Authentication (disabling may require KB2871997) | Admin Templates > MS Security Guide                   | Disabled                          | Deprecated in 24H2. WDigest credential caching disabled by default since Windows 8.1. Existing registry values at `UseLogonCredential` will not auto-clean from prior deployments. |
| Scan packed executables                                  | Admin Templates > Microsoft Defender Antivirus > Scan | Enabled                           | No longer functional. Defender always scans packed executables by default now.                                                                                                     |
| Hide Exclusions From Local Users                         | Defender CSP                                          | Enabled (hidden from local users) | Redundant. Parent setting "Hide Exclusions From Local Admins" (still present and enabled) takes precedence.                                                                        |

## Quick Start

Download and run the deployment script directly in PowerShell:

```powershell
irm "https://raw.githubusercontent.com/dgulle/Security-Baselines/master/Deploy-SecurityBaselines.ps1" -OutFile "$env:TEMP\Deploy-SecurityBaselines.ps1"; & "$env:TEMP\Deploy-SecurityBaselines.ps1" -InstallAll
```

> Note: To run a script from the current directory, PowerShell requires the `.` + `\` prefix, e.g. `.\\Deploy-SecurityBaselines.ps1`.
> If you accidentally run `.Deploy-SecurityBaselines.ps1` (missing the `\`), you’ll get “The term '.Deploy-SecurityBaselines.ps1' is not recognized...”.
> Dot-sourcing (not required here) would be: `. .\\Deploy-SecurityBaselines.ps1`.

## Deploy-SecurityBaselines.ps1

Unified deployment script that downloads the baseline JSON files from this repository, creates the corresponding Intune device management configuration policies via Microsoft Graph, and cleans up temporary files automatically.

### Prerequisites

- PowerShell 5.1 or later
- Internet access to download from GitHub and connect to Microsoft Graph
- An Entra ID account with **Intune Administrator** or equivalent permissions
- The `Microsoft.Graph.Beta` module (the script will install it automatically if missing)

### Parameters

| Parameter                | Type   | Description                                                                                    |
| ------------------------ | ------ | ---------------------------------------------------------------------------------------------- |
| `-InstallWindows`        | Switch | Deploy Windows 11 v25H2 Security Baseline policies                                             |
| `-WindowsVersion`        | String | Which Windows baseline to deploy with `-InstallWindows` (`24H2` or `25H2`). Default: `25H2`    |
| `-InstallEdge`           | Switch | Deploy Microsoft Edge v128 Security Baseline policies                                          |
| `-InstallM365`           | Switch | Deploy Microsoft 365 Apps Security Baseline policies                                           |
| `-InstallAll`            | Switch | Deploy all available baselines (Windows, Edge, and M365)                                       |
| `-SourcePath`            | String | Use a local repository path instead of downloading from GitHub                                 |
| `-Force`                 | Switch | Skip the interactive confirmation prompt                                                       |
| `-DryRun`                | Switch | Connect to Graph and report what would be created/updated/assigned, but do not change anything |
| `-UpdateExisting`        | Switch | If a policy already exists, update it instead of skipping                                      |
| `-KeepTemplateReference` | Switch | Keep `templateReference` from JSON (do not force Settings Catalog)                             |
| `-GroupAssignmentId`     | String | Entra ID security group Object ID to assign all created policies to                            |

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

**Check what’s already in the tenant (no changes):**

```powershell
.\Deploy-SecurityBaselines.ps1 -InstallAll -Force -DryRun
```

**Deploy Windows 24H2 instead of 25H2:**

```powershell
.\Deploy-SecurityBaselines.ps1 -InstallWindows -WindowsVersion 24H2
```

**Use local files (no download):**

```powershell
.\Deploy-SecurityBaselines.ps1 -InstallAll -SourcePath "C:\Path\To\Security-Baselines"
```

### What the Script Does

1. Displays selected baselines and prompts for confirmation
2. Downloads and extracts the repository archive to a temporary folder
3. Installs/imports the `Microsoft.Graph.Beta` module and authenticates to Microsoft Graph
4. Creates Intune configuration policies from the JSON files (skips any that already exist by name)
5. Optionally assigns each created policy to the specified Entra ID security group
6. Cleans up all temporary files
7. Displays a summary of created, skipped, and failed policies

## How to Tell If Baselines Already Exist in the Tenant

There are two common “baseline” implementations you might already have:

1. **Intune Security Baselines profiles** (shown in the Intune admin center under _Endpoint security → Security baselines_).
2. **Settings Catalog configuration policies** (shown under _Devices → Configuration → Profiles_). This repo’s deployment script can intentionally deploy JSON as Settings Catalog by clearing `templateReference`.

### Quick checks (portal)

- Intune admin center:
  - _Endpoint security → Security baselines_ (baseline profiles)
  - _Devices → Configuration → Profiles_ (Settings Catalog policies)
- Search for policy names like:
  - `Security Baseline 25H2 - ...`
  - `Edge Baseline - v128_...`
  - `M365 Security Baseline - ...`

### Script-based check (recommended)

Run a dry-run. It connects to Graph read-only, checks which policies already exist by name, and prints whether each policy would be created or updated:

```powershell
.\Deploy-SecurityBaselines.ps1 -InstallAll -Force -DryRun
```

### Logs

A log file is written to `%TEMP%\Deploy-SecurityBaselines.log` with timestamps for each operation.

## Export Scripts

The `Baseline Template and Script/` subdirectories contain utility scripts for exporting new baselines from Intune. These are used to maintain and update the JSON files in this repository and are **not** part of the deployment process.

- **MS_Edge_Baseline_Export.ps1** - Exports and splits Edge baseline policies by category
- **M365 Baselines Export.ps1** - Exports and splits M365 baseline policies by application

## Credits

- [Dustin Gullett](https://www.linkedin.com/in/dustin-gullett-83607b1ba/) - Repository maintainer
- [Thiago Beier](https://github.com/thiagogbeier) - Deployment script author
- Blog post: [Rolling Out Intune Security Baselines Without Causing a Workplace Uprising](https://zerototrust.tech/rolling-out-intune-security-baselines-without-causing-a-workplace-uprising/)
