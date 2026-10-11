# Plugin and marketplace values, from the files Claude keeps under
# <config>/plugins (or CLAUDE_CODE_PLUGIN_CACHE_DIR when that is set).
# A missing or malformed file, or a malformed entry in one, leaves the
# remaining values in place.

using namespace System.Text.Json

# A JSON value as text: a string as it is, anything else as written, null as $null.
function Get-ClaudeJsonText {
    param($Element, [string]$Name)
    $value = Get-ClaudeJsonProperty $Element $Name
    if ($null -eq $value -or $value.ValueKind -eq [JsonValueKind]::Null) { return $null }
    if ($value.ValueKind -eq [JsonValueKind]::String) { return $value.GetString() }
    $value.GetRawText()
}

# The installs recorded for one plugin in installed_plugins.json: a list of
# installs, or a single install in the older format.
function Get-ClaudePluginInstalls {
    param($Value)
    if ($Value.ValueKind -eq [JsonValueKind]::Object) { return , $Value }
    if ($Value.ValueKind -eq [JsonValueKind]::Array) {
        foreach ($install in $Value.EnumerateArray()) {
            if ($install.ValueKind -eq [JsonValueKind]::Object) { $install }
        }
    }
}

# Installed plugins, as `name@marketplace`. An install made for one project
# (project or local scope, with a `projectPath`) only counts inside that
# project; the first install that counts supplies the description.
function Get-ClaudeInstalledPluginItem {
    param($Context)
    $root = Read-ClaudeJson (Join-Path (Get-ClaudePluginsDir) 'installed_plugins.json')
    $plugins = Get-ClaudeJsonProperty $root 'plugins'
    if ($null -eq $plugins -or $plugins.ValueKind -ne [JsonValueKind]::Object) { return }
    $dirs = @(Get-ClaudeProjectDirs $Context.Cwd)

    foreach ($plugin in $plugins.EnumerateObject()) {
        foreach ($install in (Get-ClaudePluginInstalls $plugin.Value)) {
            $projectPath = Get-ClaudeJsonString $install 'projectPath'
            if ($null -ne $projectPath -and -not ($dirs | Where-Object { Test-ClaudeSamePath $projectPath $_ })) { continue }
            $version = Get-ClaudeJsonText $install 'version'
            if (-not $version) { $version = 'unknown' }
            $scope = Get-ClaudeJsonText $install 'scope'
            if (-not $scope) { $scope = 'user' }
            [pscustomobject]@{ Name = $plugin.Name; Description = Limit-ClaudeText "$version ($scope scope)" }
            break
        }
    }
}

# Marketplace names, from known_marketplaces.json.
function Get-ClaudeMarketplaceItem {
    param($Context)
    $root = Read-ClaudeJson (Join-Path (Get-ClaudePluginsDir) 'known_marketplaces.json')
    if ($null -eq $root -or $root.ValueKind -ne [JsonValueKind]::Object) { return }
    foreach ($marketplace in $root.EnumerateObject()) {
        if ($marketplace.Value.ValueKind -ne [JsonValueKind]::Object) { continue }
        $source = Get-ClaudeJsonProperty $marketplace.Value 'source'
        $from = ''
        foreach ($key in 'repo', 'url', 'path', 'source') {
            $from = Get-ClaudeJsonString $source $key
            if ($from) { break }
        }
        # The query string of a URL can hold a token: do not show it.
        [pscustomobject]@{ Name = $marketplace.Name; Description = ([string]$from).Split([char]'?')[0] }
    }
}

# Plugins that can be installed, as `name@marketplace`, from the manifest each
# known marketplace caches under marketplaces/<name>/.
function Get-ClaudeMarketplacePluginItem {
    param($Context)
    $marketplaces = Join-Path (Get-ClaudePluginsDir) 'marketplaces'
    if (-not [IO.Directory]::Exists($marketplaces)) { return }
    foreach ($dir in ([IO.Directory]::GetDirectories($marketplaces) | Sort-Object)) {
        $manifest = Read-ClaudeJson ([IO.Path]::Combine($dir, '.claude-plugin', 'marketplace.json'))
        $plugins = Get-ClaudeJsonProperty $manifest 'plugins'
        if ($null -eq $plugins -or $plugins.ValueKind -ne [JsonValueKind]::Array) { continue }
        $marketplace = [IO.Path]::GetFileName($dir)
        foreach ($plugin in $plugins.EnumerateArray()) {
            $name = Get-ClaudeJsonString $plugin 'name'
            if (-not $name) { continue }
            [pscustomobject]@{
                Name        = "$name@$marketplace"
                Description = Limit-ClaudeText (Get-ClaudeJsonString $plugin 'description')
            }
        }
    }
}

$script:ClaudeValueCompleters['InstalledPlugins'] = 'Get-ClaudeInstalledPluginItem'
$script:ClaudeValueCompleters['Marketplaces'] = 'Get-ClaudeMarketplaceItem'
$script:ClaudeValueCompleters['MarketplacePlugins'] = 'Get-ClaudeMarketplacePluginItem'
