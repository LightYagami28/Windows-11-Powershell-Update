<#
.SYNOPSIS
    Comprehensive Windows 11 update script with enhanced security and error handling.

.DESCRIPTION
    This script updates Windows 11 OS, Microsoft Store apps, and winget-registered applications.
    It includes robust error handling, logging, and security features.

.PARAMETER WhatIf
    Shows what would happen if the script runs. No changes are made.

.PARAMETER CreateRestorePoint
    Creates a system restore point before making changes.

.PARAMETER LogPath
    Path to save the log file. Default: $env:TEMP\Windows11Update_[timestamp].log

.PARAMETER SkipWindowsUpdate
    Skip Windows Update installation.

.PARAMETER SkipWingetUpdate
    Skip winget application updates.

.PARAMETER SkipStoreUpdate
    Skip Microsoft Store application updates.

.EXAMPLE
    .\Update-Windows11.ps1 -WhatIf
    Shows what would be updated without making changes.

.EXAMPLE
    .\Update-Windows11.ps1 -CreateRestorePoint
    Creates a restore point and runs all updates.

.NOTES
    Author: Based on script by marcyjcook.bsky.social
    Version: 2.0 Enhanced - February 2026
    License: GNU GENERAL PUBLIC LICENSE v3
    
    DISCLAIMER: This script is provided 'as is'. Use at your own risk.
    The author is exempt from any and all possible outcomes.

.LINK
    https://github.com/ravens-wing/Windows-11-Powershell-Update
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [switch]$CreateRestorePoint,
    
    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\Windows11Update_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipWindowsUpdate,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipWingetUpdate,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipStoreUpdate
)

#Requires -Version 5.1
#Requires -RunAsAdministrator

# Script configuration
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'
$VerbosePreference = if ($PSBoundParameters['Verbose']) { 'Continue' } else { 'SilentlyContinue' }

# Initialize transcript
$TranscriptPath = "$env:TEMP\Windows11Update_Transcript_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $TranscriptPath -Append

#region Helper Functions

function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to the log file and console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
    
    # Write to console with color
    switch ($Level) {
        'Info'    { Write-Host $Message -ForegroundColor Cyan }
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error $Message }
        'Success' { Write-Host $Message -ForegroundColor Green }
    }
}

function Invoke-SafeCommand {
    <#
    .SYNOPSIS
        Executes a command with proper error handling and logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        
        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage,
        
        [Parameter(Mandatory = $false)]
        [switch]$ContinueOnError
    )
    
    try {
        & $ScriptBlock
        return $true
    }
    catch {
        Write-Log -Message "$ErrorMessage : $($_.Exception.Message)" -Level Error
        if (-not $ContinueOnError) {
            throw
        }
        return $false
    }
}

function Test-Administrator {
    <#
    .SYNOPSIS
        Checks if the current user has administrator privileges.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-SystemRestorePoint {
    <#
    .SYNOPSIS
        Creates a system restore point.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    if ($PSCmdlet.ShouldProcess("System", "Create restore point")) {
        try {
            Write-Log -Message "Creating system restore point..." -Level Info
            
            # Enable System Restore if not enabled
            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
            
            # Create restore point
            Checkpoint-Computer -Description "Before Windows 11 Update - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS
            
            Write-Log -Message "System restore point created successfully." -Level Success
            return $true
        }
        catch {
            Write-Log -Message "Failed to create system restore point: $($_.Exception.Message)" -Level Warning
            return $false
        }
    }
}

function Set-ServiceState {
    <#
    .SYNOPSIS
        Manages Windows services with validation.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ServiceNames,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('Stop', 'Start', 'Restart')]
        [string]$Action
    )
    
    foreach ($serviceName in $ServiceNames) {
        try {
            # Check if service exists
            $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            
            if (-not $service) {
                Write-Log -Message "Service '$serviceName' not found. Skipping." -Level Warning
                continue
            }
            
            if ($PSCmdlet.ShouldProcess($serviceName, $Action)) {
                Write-Log -Message "${Action}ping service: $serviceName" -Level Info
                
                switch ($Action) {
                    'Stop' {
                        if ($service.Status -ne 'Stopped') {
                            Stop-Service -Name $serviceName -Force -ErrorAction Stop
                            Write-Log -Message "Service '$serviceName' stopped successfully." -Level Success
                        }
                    }
                    'Start' {
                        if ($service.Status -ne 'Running') {
                            Start-Service -Name $serviceName -ErrorAction Stop
                            Write-Log -Message "Service '$serviceName' started successfully." -Level Success
                        }
                    }
                    'Restart' {
                        Restart-Service -Name $serviceName -Force -ErrorAction Stop
                        Write-Log -Message "Service '$serviceName' restarted successfully." -Level Success
                    }
                }
            }
        }
        catch {
            Write-Log -Message "Failed to $Action service '$serviceName': $($_.Exception.Message)" -Level Error
        }
    }
}

function Clear-WindowsUpdateCache {
    <#
    .SYNOPSIS
        Clears Windows Update cache and temporary files.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    if ($PSCmdlet.ShouldProcess("Windows Update Cache", "Clear")) {
        try {
            Write-Log -Message "Cleaning Windows Update cache..." -Level Info
            
            $cachePaths = @(
                "$env:SystemRoot\SoftwareDistribution\Download"
                "$env:SystemRoot\SoftwareDistribution\DataStore"
            )
            
            foreach ($path in $cachePaths) {
                if (Test-Path $path) {
                    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
                }
            }
            
            Write-Log -Message "Windows Update cache cleaned successfully." -Level Success
            return $true
        }
        catch {
            Write-Log -Message "Failed to clean Windows Update cache: $($_.Exception.Message)" -Level Warning
            return $false
        }
    }
}

function Install-RequiredModule {
    <#
    .SYNOPSIS
        Installs and imports required PowerShell modules.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )
    
    try {
        if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
            Write-Log -Message "Installing module: $ModuleName" -Level Info
            
            # Set TLS 1.2 for secure communication
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            Install-Module -Name $ModuleName -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
            Write-Log -Message "Module '$ModuleName' installed successfully." -Level Success
        }
        
        Import-Module -Name $ModuleName -ErrorAction Stop
        Write-Log -Message "Module '$ModuleName' imported successfully." -Level Success
        return $true
    }
    catch {
        Write-Log -Message "Failed to install/import module '$ModuleName': $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Test-WingetInstallation {
    <#
    .SYNOPSIS
        Checks if winget is installed and installs if necessary.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log -Message "Winget is already installed." -Level Info
        return $true
    }
    
    Write-Log -Message "Winget not found. Attempting installation..." -Level Warning
    
    try {
        # Set TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        $tempPath = Join-Path $env:TEMP "AppInstaller.msixbundle"
        $uri = "https://aka.ms/getwinget"
        
        Write-Log -Message "Downloading winget installer from: $uri" -Level Info
        Invoke-WebRequest -Uri $uri -OutFile $tempPath -UseBasicParsing -ErrorAction Stop
        
        Write-Log -Message "Installing winget..." -Level Info
        Add-AppxPackage -Path $tempPath -ErrorAction Stop
        
        Remove-Item -Path $tempPath -Force -ErrorAction SilentlyContinue
        
        Write-Log -Message "Winget installed successfully." -Level Success
        return $true
    }
    catch {
        Write-Log -Message "Failed to install winget: $($_.Exception.Message)" -Level Error
        return $false
    }
}

#endregion

#region Main Update Functions

function Update-WindowsOS {
    <#
    .SYNOPSIS
        Updates Windows 11 operating system.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    if ($SkipWindowsUpdate) {
        Write-Log -Message "Skipping Windows Update (parameter specified)." -Level Info
        return
    }
    
    Write-Log -Message "Starting Windows Update process..." -Level Info
    
    # Install PSWindowsUpdate module
    if (-not (Install-RequiredModule -ModuleName 'PSWindowsUpdate')) {
        Write-Log -Message "Cannot proceed with Windows Update without PSWindowsUpdate module." -Level Error
        return
    }
    
    if ($PSCmdlet.ShouldProcess("Windows 11", "Install Updates")) {
        try {
            # Get available updates
            Write-Log -Message "Checking for available Windows updates..." -Level Info
            $updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -ErrorAction Stop
            
            if ($updates.Count -eq 0) {
                Write-Log -Message "No Windows updates available." -Level Success
                return
            }
            
            Write-Log -Message "Found $($updates.Count) update(s) to install." -Level Info
            
            # Install updates
            $currentUpdate = 0
            foreach ($update in $updates) {
                $currentUpdate++
                $percentComplete = [math]::Round(($currentUpdate / $updates.Count) * 100)
                
                Write-Progress -Activity "Installing Windows Updates" -Status "$currentUpdate of $($updates.Count): $($update.Title)" -PercentComplete $percentComplete
                Write-Log -Message "Installing update ($currentUpdate/$($updates.Count)): $($update.Title)" -Level Info
                
                try {
                    Install-WindowsUpdate -KBArticleID $update.KBArticleID -AcceptAll -IgnoreReboot -ErrorAction Stop
                    Write-Log -Message "Successfully installed: $($update.Title)" -Level Success
                }
                catch {
                    Write-Log -Message "Failed to install update '$($update.Title)': $($_.Exception.Message)" -Level Error
                }
            }
            
            Write-Progress -Activity "Installing Windows Updates" -Completed
            Write-Log -Message "Windows Update process completed." -Level Success
            
            # Check if reboot is required
            if (Get-WURebootStatus -Silent) {
                Write-Log -Message "System reboot is required to complete Windows updates." -Level Warning
            }
        }
        catch {
            Write-Log -Message "Windows Update process failed: $($_.Exception.Message)" -Level Error
        }
    }
}

function Update-WingetApplications {
    <#
    .SYNOPSIS
        Updates applications managed by winget.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    if ($SkipWingetUpdate) {
        Write-Log -Message "Skipping winget updates (parameter specified)." -Level Info
        return
    }
    
    Write-Log -Message "Starting winget application updates..." -Level Info
    
    if (-not (Test-WingetInstallation)) {
        Write-Log -Message "Cannot proceed with winget updates." -Level Error
        return
    }
    
    if ($PSCmdlet.ShouldProcess("Winget Applications", "Update All")) {
        try {
            Write-Log -Message "Updating all winget applications..." -Level Info
            
            # Execute winget upgrade
            $upgradeOutput = winget upgrade --all --accept-source-agreements --accept-package-agreements --silent 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log -Message "Winget applications updated successfully." -Level Success
            }
            else {
                Write-Log -Message "Winget upgrade completed with warnings. Output: $($upgradeOutput -join "`n")" -Level Warning
            }
        }
        catch {
            Write-Log -Message "Failed to update winget applications: $($_.Exception.Message)" -Level Error
        }
    }
}

function Update-StoreApplications {
    <#
    .SYNOPSIS
        Updates Microsoft Store applications.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    if ($SkipStoreUpdate) {
        Write-Log -Message "Skipping Microsoft Store updates (parameter specified)." -Level Info
        return
    }
    
    Write-Log -Message "Starting Microsoft Store application updates..." -Level Info
    
    if ($PSCmdlet.ShouldProcess("Microsoft Store Applications", "Update All")) {
        try {
            # Get all installed AppX packages
            $apps = Get-AppxPackage -AllUsers | Where-Object { $_.InstallLocation -and (Test-Path "$($_.InstallLocation)\AppxManifest.xml") }
            
            if ($apps.Count -eq 0) {
                Write-Log -Message "No Microsoft Store apps found to update." -Level Info
                return
            }
            
            Write-Log -Message "Found $($apps.Count) Microsoft Store app(s) to process." -Level Info
            
            $currentApp = 0
            $successCount = 0
            $failCount = 0
            
            foreach ($app in $apps) {
                $currentApp++
                $percentComplete = [math]::Round(($currentApp / $apps.Count) * 100)
                
                Write-Progress -Activity "Updating Microsoft Store Applications" -Status "$currentApp of $($apps.Count): $($app.Name)" -PercentComplete $percentComplete
                
                try {
                    $manifestPath = Join-Path $app.InstallLocation "AppxManifest.xml"
                    
                    if (Test-Path $manifestPath) {
                        Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop
                        $successCount++
                        Write-Verbose "Updated: $($app.Name)"
                    }
                }
                catch {
                    $failCount++
                    Write-Log -Message "Failed to update '$($app.Name)': $($_.Exception.Message)" -Level Warning
                }
            }
            
            Write-Progress -Activity "Updating Microsoft Store Applications" -Completed
            Write-Log -Message "Microsoft Store app updates completed. Success: $successCount, Failed: $failCount" -Level Success
        }
        catch {
            Write-Log -Message "Failed to update Microsoft Store applications: $($_.Exception.Message)" -Level Error
        }
    }
}

#endregion

#region Main Script Execution

try {
    Write-Log -Message "========================================" -Level Info
    Write-Log -Message "Windows 11 Update Script Started" -Level Info
    Write-Log -Message "========================================" -Level Info
    Write-Log -Message "Log file: $LogPath" -Level Info
    Write-Log -Message "Transcript: $TranscriptPath" -Level Info
    
    # Verify administrator privileges
    if (-not (Test-Administrator)) {
        Write-Log -Message "This script requires administrator privileges. Please run as Administrator." -Level Error
        exit 1
    }
    
    # Create system restore point if requested
    if ($CreateRestorePoint) {
        New-SystemRestorePoint
    }
    
    # Define Windows Update services
    $updateServices = @('wuauserv', 'bits', 'cryptsvc', 'appidsvc')
    
    # Stop services
    Write-Log -Message "Stopping Windows Update services..." -Level Info
    Set-ServiceState -ServiceNames $updateServices -Action Stop
    
    # Clear Windows Update cache
    Clear-WindowsUpdateCache
    
    # Restart Windows Update service
    Write-Log -Message "Restarting Windows Update service..." -Level Info
    Set-ServiceState -ServiceNames @('wuauserv') -Action Start
    
    # Execute updates
    Update-WindowsOS
    Update-WingetApplications
    Update-StoreApplications
    
    # Restart all services
    Write-Log -Message "Starting Windows Update services..." -Level Info
    Set-ServiceState -ServiceNames $updateServices -Action Start
    
    Write-Log -Message "========================================" -Level Info
    Write-Log -Message "All update processes completed!" -Level Success
    Write-Log -Message "========================================" -Level Info
    
    # Check for required reboot
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") {
        Write-Log -Message "IMPORTANT: A system reboot is required to complete the updates." -Level Warning
        
        $response = Read-Host "Would you like to reboot now? (Y/N)"
        if ($response -eq 'Y' -or $response -eq 'y') {
            Write-Log -Message "Initiating system reboot..." -Level Info
            Stop-Transcript
            Restart-Computer -Force
        }
    }
}
catch {
    Write-Log -Message "Critical error occurred: $($_.Exception.Message)" -Level Error
    Write-Log -Message "Stack trace: $($_.ScriptStackTrace)" -Level Error
    exit 1
}
finally {
    Write-Log -Message "Script execution ended at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info
    Stop-Transcript
}

#endregion
