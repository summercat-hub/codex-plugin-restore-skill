[CmdletBinding(DefaultParameterSetName = 'Inspect')]
param(
    [Parameter(ParameterSetName = 'Inspect')]
    [switch]$InspectOnly,

    [Parameter(Mandatory, ParameterSetName = 'Repair')]
    [switch]$Repair,

    [Parameter(ParameterSetName = 'Repair')]
    [switch]$RestoreMissingPluginStates,

    [string]$CodexHome,
    [string[]]$VisiblePluginId = @()
)

$ErrorActionPreference = 'Stop'

if (-not $CodexHome) {
    $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
}
$CodexHome = [System.IO.Path]::GetFullPath($CodexHome)
$configPath = Join-Path $CodexHome 'config.toml'
$inspectScript = Join-Path $PSScriptRoot 'Inspect-CodexPluginInventory.ps1'
$codex = Get-Command codex -ErrorAction Stop

function Invoke-Codex {
    param([string[]]$Arguments)
    $output = & $codex.Source @Arguments 2>&1 | Out-String
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output.Trim() }
}

function Normalize-PathValue {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    $value = $PathValue.Trim()
    if ($value.StartsWith('\\?\')) { $value = $value.Substring(4) }
    try { return [System.IO.Path]::GetFullPath($value) } catch { return $value }
}

function Get-Inventory {
    $parameters = @{ Json = $true; CodexHome = $CodexHome }
    if ($VisiblePluginId.Count -gt 0) { $parameters.VisiblePluginId = $VisiblePluginId }
    $text = & $inspectScript @parameters | Out-String
    try { return $text | ConvertFrom-Json -ErrorAction Stop } catch {
        throw "Inspection did not return valid JSON: $($_.Exception.Message)"
    }
}

function Find-KnownCandidate {
    param($Inventory, [string]$Name)
    @($Inventory.KnownOfficialCandidates | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
}

function Find-MarketplaceHealth {
    param($Inventory, [string]$Name)
    @($Inventory.MarketplaceHealth | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
}

function Find-CliMarketplace {
    param($Inventory, [string]$Name)
    @($Inventory.CliMarketplaces | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
}

$inventory = Get-Inventory
$missing = @($inventory.ExpectedPlugins | Where-Object { -not $_.CliInstalled -or -not $_.CliEnabled })

Write-Host "Evidence-derived installed total: $($inventory.Counts.ExpectedPreviouslyInstalled)"
Write-Host "Currently installed and enabled: $($inventory.Counts.CliInstalledAndEnabled)"
Write-Host "Missing or disabled: $($missing.Count)"
if ($missing.Count -gt 0) { Write-Host "Targets: $($missing.PluginId -join ', ')" }

$marketplacePlans = [System.Collections.Generic.List[object]]::new()
foreach ($name in @('openai-primary-runtime', 'openai-bundled')) {
    $candidate = Find-KnownCandidate $inventory $name
    if (-not $candidate -or -not $candidate.Health.ManifestValid) { continue }
    $health = Find-MarketplaceHealth $inventory $name
    $cliMarketplace = Find-CliMarketplace $inventory $name
    $officialRoot = Normalize-PathValue $candidate.Health.Root
    $currentRoot = if ($cliMarketplace) { Normalize-PathValue $cliMarketplace.Root } elseif ($health) { Normalize-PathValue $health.ConfiguredSource } else { $null }
    $sameRoot = [bool]($currentRoot -and $officialRoot -and $currentRoot.Equals($officialRoot, [System.StringComparison]::OrdinalIgnoreCase))

    if (-not $cliMarketplace) {
        $marketplacePlans.Add([pscustomobject]@{ Name = $name; Action = 'AddOfficialSource'; CurrentRoot = $currentRoot; OfficialRoot = $officialRoot; Safe = $true; Reason = 'Marketplace is not registered with the CLI.' })
    } elseif (-not $sameRoot) {
        $currentBroken = [bool](-not $health -or -not $health.SourceExists -or -not $health.ManifestValid)
        if ($currentBroken) {
            $marketplacePlans.Add([pscustomobject]@{ Name = $name; Action = 'ReplaceBrokenOfficialSource'; CurrentRoot = $currentRoot; OfficialRoot = $officialRoot; Safe = $true; Reason = 'Configured source is missing or lacks a valid manifest.' })
        } else {
            $marketplacePlans.Add([pscustomobject]@{ Name = $name; Action = 'RefuseHealthySourceReplacement'; CurrentRoot = $currentRoot; OfficialRoot = $officialRoot; Safe = $false; Reason = 'A different healthy source is already registered.' })
        }
    }
}

if ($marketplacePlans.Count -eq 0) {
    Write-Host 'Known official marketplace registrations require no repair.'
} else {
    Write-Host 'Marketplace repair plan:'
    $marketplacePlans | Format-Table Name, Action, Safe, CurrentRoot, OfficialRoot -AutoSize
}

if (-not $Repair) {
    if ($missing.Count -gt 0) { Write-Host 'To restore strong-evidence plugin states, rerun with -Repair -RestoreMissingPluginStates.' }
    if (@($marketplacePlans | Where-Object { $_.Safe }).Count -gt 0) { Write-Host 'To apply safe known-official marketplace repairs, rerun with -Repair.' }
    exit 0
}

if (-not (Test-Path -LiteralPath $configPath)) { throw "Codex config was not found: $configPath" }

$safePlans = @($marketplacePlans | Where-Object { $_.Safe })
$willMutate = $safePlans.Count -gt 0 -or ($RestoreMissingPluginStates -and $missing.Count -gt 0)
$backupPath = $null
if ($willMutate) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$configPath.before-plugin-restore-$timestamp.bak"
    Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
    Write-Host "Config backup: $backupPath"
}

foreach ($plan in $safePlans) {
    if ($plan.Action -eq 'ReplaceBrokenOfficialSource') {
        Write-Host "Removing broken marketplace registration: $($plan.Name)"
        $remove = Invoke-Codex @('plugin', 'marketplace', 'remove', $plan.Name)
        if ($remove.ExitCode -ne 0) { throw "Failed to remove $($plan.Name): $($remove.Output)" }
    }
    Write-Host "Registering $($plan.Name) from $($plan.OfficialRoot)"
    $add = Invoke-Codex @('plugin', 'marketplace', 'add', $plan.OfficialRoot, '--json')
    if ($add.ExitCode -ne 0) { throw "Failed to register $($plan.Name): $($add.Output)" }
}

$inventoryAfterMarketplaceRepair = Get-Inventory
$restoreFailures = [System.Collections.Generic.List[object]]::new()
if ($RestoreMissingPluginStates) {
    $registered = @($inventoryAfterMarketplaceRepair.CliMarketplaces | ForEach-Object { $_.Name })
    $targets = @($inventoryAfterMarketplaceRepair.ExpectedPlugins | Where-Object { -not $_.CliInstalled -or -not $_.CliEnabled })
    foreach ($plugin in $targets) {
        $separator = $plugin.PluginId.LastIndexOf('@')
        $marketplaceName = if ($separator -ge 0) { $plugin.PluginId.Substring($separator + 1) } else { $null }
        if (-not $marketplaceName -or $registered -notcontains $marketplaceName) {
            $restoreFailures.Add([pscustomobject]@{ PluginId = $plugin.PluginId; Reason = 'Marketplace is not registered.' })
            continue
        }
        Write-Host "Restoring $($plugin.PluginId)"
        $addPlugin = Invoke-Codex @('plugin', 'add', $plugin.PluginId, '--json')
        if ($addPlugin.ExitCode -ne 0) {
            $restoreFailures.Add([pscustomobject]@{ PluginId = $plugin.PluginId; Reason = $addPlugin.Output })
        }
    }
}

$finalInventory = Get-Inventory
$unresolved = @($finalInventory.ExpectedPlugins | Where-Object { -not $_.CliInstalled -or -not $_.CliEnabled })
$brokenMarketplaces = @($finalInventory.MarketplaceHealth | Where-Object { -not $_.SourceExists -or -not $_.ManifestValid -or -not $_.CliRegistered })

Write-Host ''
Write-Host 'Verification summary:'
Write-Host "Expected previously installed: $($finalInventory.Counts.ExpectedPreviouslyInstalled)"
Write-Host "Installed and enabled: $($finalInventory.Counts.CliInstalledAndEnabled)"
Write-Host "Unresolved plugin states: $($unresolved.Count)"
Write-Host "Broken registered marketplaces: $($brokenMarketplaces.Count)"
if ($restoreFailures.Count -gt 0) {
    Write-Warning "Some plugin states could not be restored automatically: $($restoreFailures.PluginId -join ', ')"
}
if ($unresolved.Count -gt 0) {
    Write-Warning 'Remaining entries may require account/App authorization, desktop UI refresh, or server-side entitlement. Review each classification; do not delete caches.'
}
if ($brokenMarketplaces.Count -gt 0) {
    Write-Warning "Marketplace verification remains incomplete: $($brokenMarketplaces.Name -join ', ')"
}
if ($unresolved.Count -eq 0 -and $brokenMarketplaces.Count -eq 0) {
    Write-Host 'Local plugin inventory restoration succeeded.'
}
Write-Host 'Restart Codex Desktop once, then verify the store, installed page, plus menu, and @ picker separately.'
