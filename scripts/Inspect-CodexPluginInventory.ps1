[CmdletBinding()]
param(
    [switch]$Json,
    [string]$CodexHome,
    [string[]]$VisiblePluginId = @()
)

$ErrorActionPreference = 'Stop'

if (-not $CodexHome) {
    $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' }
}
$CodexHome = [System.IO.Path]::GetFullPath($CodexHome)

function Invoke-ExternalCommand {
    param([string]$FilePath, [string[]]$Arguments)

    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FilePath
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { [void]$info.ArgumentList.Add($argument) }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $info
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        StdOut = $stdout.Trim()
        StdErr = $stderr.Trim()
        Combined = (@($stdout.Trim(), $stderr.Trim()) | Where-Object { $_ }) -join [Environment]::NewLine
    }
}

function ConvertFrom-JsonSafe {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { return $Text | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

function Normalize-PathValue {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    $value = $PathValue.Trim()
    if ($value.StartsWith('\\?\')) { $value = $value.Substring(4) }
    try { return [System.IO.Path]::GetFullPath($value) } catch { return $value }
}

function Get-ConfigSnapshot {
    param([string]$Path, [bool]$Current)

    $text = Get-Content -LiteralPath $Path -Raw
    $pluginIds = @(
        [regex]::Matches($text, '(?m)^\s*\[plugins\."([^"\r\n]+)"\]\s*$') |
            ForEach-Object { $_.Groups[1].Value }
    )
    $marketplaces = @()
    foreach ($match in [regex]::Matches($text, '(?ms)^\s*\[marketplaces\.([^\]\r\n]+)\]\s*(.*?)(?=^\s*\[|\z)')) {
        $body = $match.Groups[2].Value
        $sourceMatch = [regex]::Match($body, '(?m)^\s*source\s*=\s*(["''])(.*?)\1\s*$')
        $typeMatch = [regex]::Match($body, '(?m)^\s*source_type\s*=\s*(["''])(.*?)\1\s*$')
        $marketplaces += [pscustomobject]@{
            Name = $match.Groups[1].Value.Trim()
            Source = if ($sourceMatch.Success) { $sourceMatch.Groups[2].Value } else { $null }
            SourceType = if ($typeMatch.Success) { $typeMatch.Groups[2].Value } else { $null }
        }
    }
    [pscustomobject]@{
        Path = $Path
        Current = $Current
        Modified = (Get-Item -LiteralPath $Path).LastWriteTime.ToString('o')
        PluginIds = $pluginIds
        Marketplaces = $marketplaces
    }
}

function Get-ManifestSummary {
    param([string]$Root)
    $normalized = Normalize-PathValue $Root
    $manifestPath = if ($normalized) { Join-Path $normalized '.agents\plugins\marketplace.json' } else { $null }
    $plugins = @()
    $name = $null
    $errorMessage = $null
    $manifestExists = [bool]($manifestPath -and (Test-Path -LiteralPath $manifestPath))
    if ($manifestExists) {
        try {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            $name = $manifest.name
            $plugins = @($manifest.plugins | ForEach-Object { $_.name })
        } catch {
            $errorMessage = $_.Exception.Message
        }
    }
    [pscustomobject]@{
        Root = $normalized
        RootExists = [bool]($normalized -and (Test-Path -LiteralPath $normalized))
        ManifestPath = $manifestPath
        ManifestExists = $manifestExists
        ManifestValid = [bool]($manifestExists -and -not $errorMessage)
        MarketplaceName = $name
        Plugins = $plugins
        Error = $errorMessage
    }
}

$codexCommand = Get-Command codex -ErrorAction SilentlyContinue
if (-not $codexCommand) { throw 'codex command not found' }
$codexPath = $codexCommand.Source

$versionCommand = Invoke-ExternalCommand $codexPath @('--version')
$loginCommand = Invoke-ExternalCommand $codexPath @('login', 'status')
$marketplaceCommand = Invoke-ExternalCommand $codexPath @('plugin', 'marketplace', 'list')
$pluginCommand = Invoke-ExternalCommand $codexPath @('plugin', 'list', '--available', '--json')
$pluginJson = ConvertFrom-JsonSafe $pluginCommand.StdOut

$cliMarketplaces = @()
foreach ($line in ($marketplaceCommand.StdOut -split "`r?`n" | Select-Object -Skip 1)) {
    if ($line -match '^([^\s]+)\s{2,}(.+)$') {
        $cliMarketplaces += [pscustomobject]@{ Name = $matches[1].Trim(); Root = Normalize-PathValue $matches[2] }
    }
}
$registeredNames = @($cliMarketplaces | ForEach-Object { $_.Name })

$configPath = Join-Path $CodexHome 'config.toml'
$configFiles = @()
if (Test-Path -LiteralPath $configPath) { $configFiles += Get-Item -LiteralPath $configPath }
$configFiles += @(
    Get-ChildItem -LiteralPath $CodexHome -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $configPath -and $_.Name -match '^config\.toml.*\.bak$' }
)
$configSnapshots = @(
    $configFiles | Sort-Object FullName -Unique | ForEach-Object {
        try { Get-ConfigSnapshot $_.FullName ($_.FullName -eq $configPath) } catch {
            [pscustomobject]@{ Path = $_.FullName; Current = ($_.FullName -eq $configPath); Error = $_.Exception.Message; PluginIds = @(); Marketplaces = @() }
        }
    }
)
$currentSnapshot = @($configSnapshots | Where-Object { $_.Current }) | Select-Object -First 1

$marketplaceHealth = @()
if ($currentSnapshot) {
    foreach ($marketplace in $currentSnapshot.Marketplaces) {
        $manifest = Get-ManifestSummary $marketplace.Source
        $cliRow = @($cliMarketplaces | Where-Object { $_.Name -eq $marketplace.Name }) | Select-Object -First 1
        $marketplaceHealth += [pscustomobject]@{
            Name = $marketplace.Name
            ConfiguredSource = $manifest.Root
            SourceType = $marketplace.SourceType
            SourceExists = $manifest.RootExists
            ManifestExists = $manifest.ManifestExists
            ManifestValid = $manifest.ManifestValid
            ManifestMarketplaceName = $manifest.MarketplaceName
            ManifestPlugins = $manifest.Plugins
            CliRegistered = [bool]$cliRow
            CliRoot = if ($cliRow) { $cliRow.Root } else { $null }
            Error = $manifest.Error
        }
    }
}

$cacheRoot = Join-Path $CodexHome 'plugins\cache'
$cacheEntries = @()
if (Test-Path -LiteralPath $cacheRoot) {
    foreach ($marketplaceDirectory in Get-ChildItem -LiteralPath $cacheRoot -Directory -ErrorAction SilentlyContinue) {
        foreach ($pluginDirectory in Get-ChildItem -LiteralPath $marketplaceDirectory.FullName -Directory -ErrorAction SilentlyContinue) {
            if ($pluginDirectory.Name -like 'plugin-install-*') { continue }
            foreach ($versionDirectory in Get-ChildItem -LiteralPath $pluginDirectory.FullName -Directory -ErrorAction SilentlyContinue) {
                if ($versionDirectory.Name -eq 'latest') { continue }
                $pluginManifestPath = Join-Path $versionDirectory.FullName '.codex-plugin\plugin.json'
                if (-not (Test-Path -LiteralPath $pluginManifestPath)) { continue }
                $manifestName = $pluginDirectory.Name
                $manifestVersion = $versionDirectory.Name
                try {
                    $pluginManifest = Get-Content -LiteralPath $pluginManifestPath -Raw | ConvertFrom-Json
                    if ($pluginManifest.name) { $manifestName = $pluginManifest.name }
                    if ($pluginManifest.version) { $manifestVersion = $pluginManifest.version }
                } catch { }
                $rawMarketplace = $marketplaceDirectory.Name
                $canonicalMarketplace = $rawMarketplace
                if ($rawMarketplace.EndsWith('-remote')) {
                    $baseMarketplace = $rawMarketplace.Substring(0, $rawMarketplace.Length - 7)
                    if ($registeredNames -contains $baseMarketplace) { $canonicalMarketplace = $baseMarketplace }
                }
                $cacheEntries += [pscustomobject]@{
                    PluginId = "$manifestName@$canonicalMarketplace"
                    Name = $manifestName
                    Marketplace = $canonicalMarketplace
                    RawMarketplace = $rawMarketplace
                    Version = $manifestVersion
                    Path = $versionDirectory.FullName
                    ManifestPath = $pluginManifestPath
                }
            }
        }
    }
}

$cliInstalled = if ($pluginJson) { @($pluginJson.installed) } else { @() }
$cliAvailable = if ($pluginJson) { @($pluginJson.available) } else { @() }
$currentPluginIds = if ($currentSnapshot) { @($currentSnapshot.PluginIds) } else { @() }
$backupPluginIds = @($configSnapshots | Where-Object { -not $_.Current } | ForEach-Object { $_.PluginIds })

$evidence = @{}
function Add-Evidence {
    param([string]$PluginId, [string]$Source)
    if ([string]::IsNullOrWhiteSpace($PluginId)) { return }
    if (-not $evidence.ContainsKey($PluginId)) {
        $evidence[$PluginId] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }
    [void]$evidence[$PluginId].Add($Source)
}
foreach ($id in $currentPluginIds) { Add-Evidence $id 'current-config' }
foreach ($id in $backupPluginIds) { Add-Evidence $id 'backup-config' }
foreach ($entry in $cacheEntries) { Add-Evidence $entry.PluginId "cache:$($entry.RawMarketplace)" }
foreach ($plugin in $cliInstalled) { Add-Evidence $plugin.pluginId 'cli-installed' }

$installedById = @{}
foreach ($plugin in $cliInstalled) { $installedById[$plugin.pluginId] = $plugin }
$availableById = @{}
foreach ($plugin in $cliAvailable) { $availableById[$plugin.pluginId] = $plugin }
$visibleSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($id in $VisiblePluginId) { [void]$visibleSet.Add($id) }

$actionableIds = [System.Collections.Generic.List[string]]::new()
$historicalOnlyPlugins = [System.Collections.Generic.List[object]]::new()
foreach ($id in ($evidence.Keys | Sort-Object)) {
    $sources = @($evidence[$id])
    $separator = $id.LastIndexOf('@')
    $pluginName = if ($separator -ge 0) { $id.Substring(0, $separator) } else { $id }
    $marketplaceName = if ($separator -ge 0) { $id.Substring($separator + 1) } else { $null }
    $hasCurrentEvidence = @($sources | Where-Object { $_ -ne 'backup-config' }).Count -gt 0
    $marketplaceStillRegistered = [bool]($marketplaceName -and $registeredNames -contains $marketplaceName)
    if ($hasCurrentEvidence -or $marketplaceStillRegistered) {
        $actionableIds.Add($id)
    } else {
        $historicalOnlyPlugins.Add([pscustomobject]@{
            PluginId = $id
            Name = $pluginName
            Marketplace = $marketplaceName
            Evidence = @($sources | Sort-Object)
            Reason = 'Backup-only evidence from an unregistered marketplace.'
        })
    }
}

$expectedPlugins = @()
foreach ($id in ($actionableIds | Sort-Object)) {
    $installed = if ($installedById.ContainsKey($id)) { $installedById[$id] } else { $null }
    $available = if ($availableById.ContainsKey($id)) { $availableById[$id] } else { $null }
    $expectedPlugins += [pscustomobject]@{
        PluginId = $id
        Evidence = @($evidence[$id] | Sort-Object)
        CliInstalled = [bool]$installed
        CliEnabled = [bool]($installed -and $installed.enabled)
        CliAvailable = [bool]($installed -or $available)
        Version = if ($installed) { $installed.version } elseif ($available) { $available.version } else { $null }
        UserReportedVisible = if ($VisiblePluginId.Count -gt 0) { $visibleSet.Contains($id) } else { $null }
    }
}

foreach ($historical in $historicalOnlyPlugins) {
    $sameName = @($expectedPlugins | Where-Object { ($_.PluginId -split '@', 2)[0] -eq $historical.Name })
    if ($sameName.Count -gt 0) {
        $historical.Reason = "Superseded by active evidence: $($sameName.PluginId -join ', ')"
    }
}

$knownOfficialCandidates = @()
$primaryRoot = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\plugins\openai-primary-runtime'
$primaryManifest = Get-ManifestSummary $primaryRoot
$knownOfficialCandidates += [pscustomobject]@{ Name = 'openai-primary-runtime'; SourceKind = 'workspace-runtime'; Health = $primaryManifest }
try {
    $appPackage = Get-AppxPackage OpenAI.Codex -ErrorAction Stop | Select-Object -First 1
    $bundledRoot = Join-Path $appPackage.InstallLocation 'app\resources\plugins\openai-bundled'
    $bundledManifest = Get-ManifestSummary $bundledRoot
    $desktopApp = [pscustomobject]@{ Name = $appPackage.Name; Version = $appPackage.Version.ToString(); Status = $appPackage.Status.ToString() }
    $knownOfficialCandidates += [pscustomobject]@{ Name = 'openai-bundled'; SourceKind = 'desktop-package'; Health = $bundledManifest }
} catch {
    $desktopApp = [pscustomobject]@{ Name = 'OpenAI.Codex'; Version = $null; Status = 'Not detected through AppX' }
}

$diagnoses = [System.Collections.Generic.List[string]]::new()
foreach ($marketplace in $marketplaceHealth) {
    if (-not $marketplace.SourceExists) { $diagnoses.Add("MARKETPLACE_SOURCE_MISSING:$($marketplace.Name)") }
    elseif (-not $marketplace.ManifestValid) { $diagnoses.Add("MARKETPLACE_MANIFEST_INVALID:$($marketplace.Name)") }
    if (-not $marketplace.CliRegistered) { $diagnoses.Add("MARKETPLACE_NOT_CLI_REGISTERED:$($marketplace.Name)") }
}
foreach ($plugin in $expectedPlugins) {
    if (-not $plugin.CliInstalled) { $diagnoses.Add("PRIOR_INSTALLED_PLUGIN_MISSING_FROM_CLI:$($plugin.PluginId)") }
    elseif (-not $plugin.CliEnabled) { $diagnoses.Add("PRIOR_INSTALLED_PLUGIN_DISABLED:$($plugin.PluginId)") }
    if ($VisiblePluginId.Count -gt 0 -and -not $plugin.UserReportedVisible) { $diagnoses.Add("PRIOR_INSTALLED_PLUGIN_NOT_USER_VISIBLE:$($plugin.PluginId)") }
}
if ($diagnoses.Count -eq 0) { $diagnoses.Add('NO_LOCAL_FAILURE_DETECTED') }

$result = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    CodexHome = $CodexHome
    CodexCliVersion = $versionCommand.Combined
    DesktopApp = $desktopApp
    LoginStatus = [ordered]@{ ExitCode = $loginCommand.ExitCode; Summary = $loginCommand.Combined }
    Counts = [ordered]@{
        ExpectedPreviouslyInstalled = $expectedPlugins.Count
        CliInstalled = @($expectedPlugins | Where-Object { $_.CliInstalled }).Count
        CliInstalledAndEnabled = @($expectedPlugins | Where-Object { $_.CliInstalled -and $_.CliEnabled }).Count
        MissingFromCli = @($expectedPlugins | Where-Object { -not $_.CliInstalled }).Count
        AvailableOnly = @($cliAvailable | Where-Object { -not $evidence.ContainsKey($_.pluginId) }).Count
        HistoricalOnly = $historicalOnlyPlugins.Count
        UserReportedVisible = if ($VisiblePluginId.Count -gt 0) { @($expectedPlugins | Where-Object { $_.UserReportedVisible }).Count } else { $null }
    }
    ExpectedPlugins = $expectedPlugins
    HistoricalOnlyPlugins = @($historicalOnlyPlugins)
    CacheEntries = $cacheEntries
    ConfigSnapshots = $configSnapshots
    CliMarketplaces = $cliMarketplaces
    MarketplaceHealth = $marketplaceHealth
    KnownOfficialCandidates = $knownOfficialCandidates
    CommandStatus = [ordered]@{
        MarketplaceListExitCode = $marketplaceCommand.ExitCode
        PluginListExitCode = $pluginCommand.ExitCode
        PluginListParseSucceeded = [bool]$pluginJson
    }
    Diagnoses = @($diagnoses)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
    exit 0
}

Write-Host "Codex home: $CodexHome"
Write-Host "Desktop / CLI: $($desktopApp.Version) / $($versionCommand.Combined)"
Write-Host "Expected previously installed: $($result.Counts.ExpectedPreviouslyInstalled)"
Write-Host "CLI installed and enabled: $($result.Counts.CliInstalledAndEnabled)"
Write-Host "Missing from CLI: $($result.Counts.MissingFromCli)"
Write-Host "Available only (not prior-install evidence): $($result.Counts.AvailableOnly)"
Write-Host "Historical only / superseded: $($result.Counts.HistoricalOnly)"
Write-Host ''
Write-Host 'Expected plugin inventory:'
$expectedPlugins | Format-Table PluginId, CliInstalled, CliEnabled, UserReportedVisible -AutoSize
Write-Host 'Marketplace health:'
$marketplaceHealth | Format-Table Name, SourceExists, ManifestValid, CliRegistered, ConfiguredSource -AutoSize
Write-Host "Diagnoses: $($diagnoses -join ', ')"
