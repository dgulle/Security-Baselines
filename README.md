# Intune Security Baselines

Intune Security Baseline JSON configuration files and automated deployment scripts for Microsoft Intune.

## Available Baselines

| Baseline | Policies | Directory |
|---|---|---|
| Windows 11 v26H2 | 28 | `Windows Baseline 26H2/` |
| Microsoft Edge v128 | 7 | `Edge Baseline/` |
| Microsoft 365 Apps | 12 | `M365 Baseline/` |

> **Note:** The Windows Security Baseline does not include the LAPS category setting for Backup Directory. This setting does not appear in the Settings Catalog.

## Settings Added in 26H2

| Setting | Location | 26H2 Default | Notes |
|---------|----------|-------------|-------|
| Configure Windows Ready Print driver ranking | Admin Templates > Printers | Enabled | Windows prefers the inbox IPP class driver over third-party V3/V4 OEM drivers when a new printer is installed over an IPP-capable connection (USB, network multicast discovery). Printers that don't support IPP, or that are added directly as TCP/IP printers, are unaffected. Test any printer models that rely on vendor driver features. Registry: `HKLM\Software\Policies\Microsoft\Windows NT\Printers\DriverRanking!UseWindowsReadyPrintDriverRankingGroupPolicy = 1`. |

## Settings Changed in 26H2

| Setting | Location | 25H2 Value | 26H2 Value | Notes |
|---------|----------|-----------|-----------|-------|
| Turn off encryption support (Secure Protocol combinations) | Admin Templates > Windows Components > Internet Explorer > Internet Control Panel > Advanced Page | Use TLS 1.1 and TLS 1.2 (`2560`) | Use TLS 1.2 and TLS 1.3 (`10240`) | TLS 1.1 is obsolete. This sets the WinINet `SecureProtocols` value, so anything that still requires TLS 1.1 through WinINet will stop connecting. |

No settings were removed in 26H2.

### Repository Fix in 26H2

| Setting | Location | Previous Value | Fixed Value | Notes |
|---------|----------|---------------|-------------|-------|
| Prevent installation of devices using drivers that match these device setup classes (Prevented Classes) | Admin Templates > System > Device Installation > Device Installation Restrictions | `" {d48179be-ec20-11d1-b6b8-00c04fa372a7}"` | `"{d48179be-ec20-11d1-b6b8-00c04fa372a7}"` | Not a Microsoft baseline change. The 24H2 and 25H2 files had a leading space in the class GUID, so the IEEE 1394 (SBP-2) device class block likely didn't match on devices. The value now matches Microsoft's baseline. |

> **Note:** Microsoft's Intune 26H2 baseline announcement also lists **Configure NetBIOS settings** as pending. It isn't in the Settings Catalog yet, so it isn't included here.

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
| `-InstallWindows` | Switch | Deploy Windows 11 v26H2 Security Baseline policies |
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


## Export Scripts

The `Baseline Template and Script/` subdirectories contain utility scripts for exporting new baselines from Intune. These are used to maintain and update the JSON files in this repository and are **not** part of the deployment process.

- **MS_Edge_Baseline_Export.ps1** - Exports and splits Edge baseline policies by category
- **M365 Baselines Export.ps1** - Exports and splits M365 baseline policies by application

## Credits

- [Dustin Gullett](https://www.linkedin.com/in/dustin-gullett-83607b1ba/) - Repository maintainer
- [Thiago Beier](https://github.com/thiagogbeier) - Deployment script author
- Blog post: [Rolling Out Intune Security Baselines Without Causing a Workplace Uprising](https://zerototrust.tech/rolling-out-intune-security-baselines-without-causing-a-workplace-uprising/)
