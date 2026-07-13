Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$manager = Join-Path $root "plugins/codex-bilingual-hover/skills/manage-bilingual-hover/scripts/manage-helper.ps1"
$helper = Join-Path $root "plugins/codex-bilingual-hover/skills/manage-bilingual-hover/scripts/windows-hover-translator.ps1"

foreach ($path in @($manager, $helper)) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $messages = $errors | ForEach-Object { $_.ToString() }
        throw "PowerShell parse errors in $path`n$($messages -join "`n")"
    }
}

$content = Get-Content -LiteralPath $helper -Raw
foreach ($required in @("Task actions", "Try now", "Install plugin", "UIAutomationClient", "PresentationFramework", "MenuItem", '"codex", "chatgpt", "openai"')) {
    if (-not $content.Contains($required)) {
        throw "Missing required Windows surface or framework marker: $required"
    }
}

foreach ($forbidden in @("knownPluginTitles", "knownTitles", "Invoke-WebRequest", "System.Net.Http.HttpClient")) {
    if ($content.Contains($forbidden)) {
        throw "Unexpected hard-coded catalog or remote-network marker: $forbidden"
    }
}

Write-Output "Windows PowerShell parse and policy checks passed."
