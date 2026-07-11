param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("install", "start", "stop", "restart", "status", "enable-autostart", "disable-autostart", "uninstall")]
    [string]$Action
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$appName = "Codex Hover Translator"
$sourceScript = Join-Path $PSScriptRoot "windows-hover-translator.ps1"
$installDir = Join-Path $env:LOCALAPPDATA "CodexHoverTranslator"
$installedScript = Join-Path $installDir "windows-hover-translator.ps1"
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "Codex Hover Translator.lnk"

function Get-HelperProcesses {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($installedScript) }
}

function Install-Helper {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Copy-Item -LiteralPath $sourceScript -Destination $installedScript -Force
    Write-Output "Installed: $installedScript"
}

function Start-Helper {
    if (-not (Test-Path -LiteralPath $installedScript)) { Install-Helper }
    if (Get-HelperProcesses) {
        Write-Output "Already running: $appName"
        return
    }
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-WindowStyle", "Hidden",
        "-File", ('"{0}"' -f $installedScript)
    ) -join " "
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden
    Start-Sleep -Milliseconds 700
    if (Get-HelperProcesses) { Write-Output "Running: $appName" } else { throw "Failed to start: $appName" }
}

function Stop-Helper {
    $processes = @(Get-HelperProcesses)
    if ($processes.Count -eq 0) {
        Write-Output "Already stopped: $appName"
        return
    }
    $processes | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Write-Output "Stopped: $appName"
}

function Enable-Autostart {
    if (-not (Test-Path -LiteralPath $installedScript)) { Install-Helper }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installedScript`""
    $shortcut.WorkingDirectory = $installDir
    $shortcut.Description = $appName
    $shortcut.Save()
    Write-Output "Launch at login enabled."
}

switch ($Action) {
    "install" { Install-Helper }
    "start" { Start-Helper }
    "stop" { Stop-Helper }
    "restart" { Stop-Helper; Start-Helper }
    "status" {
        if (Get-HelperProcesses) { Write-Output "running" } else { Write-Output "stopped" }
        if (Test-Path -LiteralPath $installedScript) { Write-Output "installed: $installedScript" } else { Write-Output "not installed" }
        if (Test-Path -LiteralPath $shortcutPath) { Write-Output "autostart: enabled" } else { Write-Output "autostart: disabled" }
    }
    "enable-autostart" { Enable-Autostart }
    "disable-autostart" {
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
        Write-Output "Launch at login disabled."
    }
    "uninstall" {
        Stop-Helper
        Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Output "Uninstalled: $installDir"
    }
}
