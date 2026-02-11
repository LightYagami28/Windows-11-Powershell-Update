# This is provided 'as is', should you chose to run the script you automatically acknowledge I am exempt from any & all possible outcomes.
# v1 26-Feb-2025 - https://bsky.app/profile/marcyjcook.bsky.social
# GNU GENERAL PUBLIC LICENSE v3

# Function to handle errors
function Handle-Error {
    param (
        [string]$Message
    )
    Write-Host $Message -ForegroundColor Red
}

# Function to check and elevate script privileges
function Ensure-ElevatedPrivileges {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "Elevating privileges..." -ForegroundColor Yellow
        Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(${MyInvocation.MyCommand.Path})`"" -Verb RunAs
        exit
    }
}

# Function to manage services
function Manage-Services {
    param (
        [string[]]$Services,
        [ValidateSet("Stop", "Start")] [string]$Action
    )
    Write-Host "${Action}ing services..." -ForegroundColor Yellow
    $jobs = @()
    foreach ($service in $Services) {
        $jobs += Start-Job -ScriptBlock {
            param($service, $Action)
            try {
                switch ($Action) {
                    "Stop" { Stop-Service -Name $service -Force -Confirm:$false -ErrorAction Stop }
                    "Start" { Start-Service -Name $service -Confirm:$false -ErrorAction Stop }
                }
                Write-Host "${Action}ed $service." -ForegroundColor Green
            } catch {
                Handle-Error ("Failed to ${Action} service ${service}: $($_.Exception.Message)")
            }
        } -ArgumentList $service, $Action
    }
    $jobs | Wait-Job | Receive-Job
    $jobs | ForEach-Object { Remove-Job -Job $_ }
}

# Function to clean up incomplete updates
function Clean-Up-IncompleteUpdates {
    try {
        Write-Host "Cleaning up incomplete Windows updates..." -ForegroundColor Yellow
        Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -Confirm:$false -ErrorAction Stop
        Write-Host "Cleanup complete." -ForegroundColor Green
    } catch {
        Handle-Error ("Failed to clean up incomplete updates: $($_.Exception.Message)")
    }
}

# Function to update progress
function Update-Progress {
    param (
        [string]$Activity,
        [int]$PercentComplete
    )
    Write-Progress -Activity $Activity -PercentComplete $PercentComplete
}

# Function to check and install PSWindowsUpdate module
function Ensure-PSWindowsUpdate {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Write-Host "PSWindowsUpdate module is not installed. Installing now..." -ForegroundColor Yellow
        Install-Module PSWindowsUpdate -Force -Scope CurrentUser -Confirm:$false
        Import-Module PSWindowsUpdate
        Write-Host "PSWindowsUpdate module installed successfully." -ForegroundColor Green
    } else {
        Import-Module PSWindowsUpdate
    }
}

# Function to check if winget is installed and install if not
function Ensure-Winget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "winget is not installed. Installing now..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "https://aka.ms/getwinget" -OutFile "$(${env:TEMP})\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle"
        Add-AppxPackage -Path "$(${env:TEMP})\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.appxbundle"
        Write-Host "winget installation complete." -ForegroundColor Green
    }
}

# Main Script Execution
Write-Host "Starting Script..." -ForegroundColor Yellow

# Ensure elevated privileges
Ensure-ElevatedPrivileges

# Stop services and clean up incomplete updates
Manage-Services -Services 'bits', 'wuauserv', 'appidsvc', 'cryptsvc' -Action "Stop"
Clean-Up-IncompleteUpdates

# Restart the Windows Update service
Write-Host "Restarting the Windows Update service..." -ForegroundColor Yellow
Restart-Service -Name wuauserv -Force

# Update Windows 11
Write-Host "Updating Windows 11..." -ForegroundColor Yellow
try {
    Ensure-PSWindowsUpdate
    Update-Progress -Activity "Initializing Update Process" -PercentComplete 0
    $updates = Get-WindowsUpdate -AcceptAll
    $totalUpdates = $updates.Count
    $currentUpdate = 0

    foreach ($update in $updates) {
        $currentUpdate++
        $percentComplete = [math]::Round(($currentUpdate / $totalUpdates) * 100)
        
        # Update the progress bar for each update
        Update-Progress -Activity "Updating Windows 11: $($update.Title)" -PercentComplete $percentComplete
        
        # Display the update name in console
        Write-Host "Installing update: $($update.Title)" -ForegroundColor Cyan
        
        # Install the update
        try {
            Install-WindowsUpdate -Title $update.Title -AcceptAll -AutoReboot -ErrorAction Stop
        } catch {
            Handle-Error ("Failed to install update: $($update.Title) - $($_.Exception.Message)")
        }
    }
    
    Update-Progress -Activity "Updating Windows 11" -PercentComplete 100
    Write-Host "Windows 11 update complete." -ForegroundColor Green
} catch {
    Handle-Error ("Failed to update Windows 11: $($_.Exception.Message)")
}

# Update installed applications using Winget
Write-Host "Updating installed applications using Winget..." -ForegroundColor Yellow
Ensure-Winget
try {
    Update-Progress -Activity "Updating installed applications" -PercentComplete 0
    $installedApps = winget upgrade --all --include-unknown --verbose --accept-source-agreements --accept-package-agreements 
    $totalApps = $installedApps.Count
    $currentApp = 0
    foreach ($app in $installedApps) {
        $currentApp++
        $percentComplete = [math]::Round(($currentApp / $totalApps) * 100)
        Update-Progress -Activity "Updating application: $($app)" -PercentComplete $percentComplete
        Write-Host "Updating application: $($app)" -ForegroundColor Cyan
    }
    Update-Progress -Activity "Updating installed applications" -PercentComplete 100
    Write-Host "Installed applications update complete." -ForegroundColor Green
} catch {
    Handle-Error ("Failed to update installed applications: $($_.Exception.Message)")
}

# Updating Microsoft Store apps
Write-Host "Updating Microsoft Store apps..." -ForegroundColor Yellow

Start-Job -ScriptBlock {
    function Update-Progress {
        param (
            [string]$Activity,
            [int]$PercentComplete
        )
        Write-Progress -Activity $Activity -PercentComplete $PercentComplete
    }
    try {
        # Get a list of all installed apps
        $apps = Get-AppxPackage
        $totalApps = $apps.Count

        # Check if there are apps to update
        if ($totalApps -eq 0) {
            Write-Host "No Microsoft Store apps found to update." -ForegroundColor Red
            return
        }
        $currentApp = 0
        # Iterate through the apps and update each one
        $apps | ForEach-Object {
            $currentApp++
            $percentComplete = [math]::Round(($currentApp / $totalApps) * 100)
            # Show progress
            Update-Progress -Activity "Updating Microsoft Store apps" -PercentComplete $percentComplete
            Write-Host "Updating $($_.Name)..." -ForegroundColor Cyan
            try {
                # Register or update the app
                Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml"
            } catch {
                Write-Host "Failed to update $($_.Name): $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        # Final progress update
        Update-Progress -Activity "Updating Microsoft Store apps" -PercentComplete 100
        Write-Host "Microsoft Store apps update complete." -ForegroundColor Green
    } catch {
        Handle-Error ("Failed to update Microsoft Store apps: $($_.Exception.Message)")
    }
} | Wait-Job


# Display job results
Get-Job | ForEach-Object {
    $job = $_
    if ($job.State -eq 'Failed') {
        Handle-Error ("Job $($job.Id) failed: $($job.Error) ")
    } else {
        Write-Host "Job $($job.Id) completed successfully." -ForegroundColor Green
    }
    Remove-Job -Job $job
}

Write-Host "All updates complete!" -ForegroundColor Green

# Start services after updates
Manage-Services -Services 'bits', 'wuauserv', 'appidsvc', 'cryptsvc' -Action "Start"