# MCP server names for `claude mcp get|remove|login|logout`: the servers
# configured for the current directory (https://code.claude.com/docs/en/mcp):
#   - user scope:    `mcpServers` in ~/.claude.json
#   - local scope:   `projects.<project path>.mcpServers` in ~/.claude.json
#   - project scope: `mcpServers` in the project's `.mcp.json`
# With CLAUDE_CONFIG_DIR set, .claude.json is read from that directory. The
# project is every directory from the working directory up to the repository
# root, so servers are also found from a subdirectory or through a link.

using namespace System.Text.Json

# One item per server in a `mcpServers` object. An entry that is not an
# object is skipped; the others stay.
function Get-ClaudeMcpServerRow {
    param($Servers, [string]$Scope)
    if ($null -eq $Servers -or $Servers.ValueKind -ne [JsonValueKind]::Object) { return }
    foreach ($server in $Servers.EnumerateObject()) {
        if ($server.Value.ValueKind -ne [JsonValueKind]::Object) { continue }
        $url = Get-ClaudeJsonString $server.Value 'url'
        $target = if ($url) { $url } else { [string](Get-ClaudeJsonString $server.Value 'command') }
        # The query string of a URL can hold a token: do not show it.
        $target = $target.Split([char]'?')[0]
        $type = Get-ClaudeJsonString $server.Value 'type'
        if (-not $type) { $type = if ($url) { 'http' } else { 'stdio' } }
        $description = ConvertTo-ClaudeDisplayText "$Scope - $type $target"
        if ($description.Length -gt 100) { $description = $description.Substring(0, 100) }
        [pscustomobject]@{ Name = $server.Name; Description = $description }
    }
}

function Get-ClaudeMcpServerItem {
    param($Context)
    $dirs = @(Get-ClaudeProjectDirs $Context.Cwd)
    $rows = [Collections.Generic.List[object]]::new()

    $config = Read-ClaudeJson (Get-ClaudeJsonPath)
    foreach ($row in (Get-ClaudeMcpServerRow (Get-ClaudeJsonProperty $config 'mcpServers') 'user')) { $rows.Add($row) }

    $projects = Get-ClaudeJsonProperty $config 'projects'
    if ($null -ne $projects -and $projects.ValueKind -eq [JsonValueKind]::Object) {
        # On Windows the same project can be recorded as `C:\repo` and as
        # `C:/repo`, so the keys are compared as paths, not looked up.
        $local = @{}
        foreach ($project in $projects.EnumerateObject()) {
            for ($i = 0; $i -lt $dirs.Count; $i++) {
                if (-not (Test-ClaudeSamePath $project.Name $dirs[$i])) { continue }
                $local[$i] = @($local[$i]) + @(Get-ClaudeMcpServerRow (Get-ClaudeJsonProperty $project.Value 'mcpServers') 'local')
            }
        }
        for ($i = 0; $i -lt $dirs.Count; $i++) { foreach ($row in $local[$i]) { if ($row) { $rows.Add($row) } } }
    }

    foreach ($dir in $dirs) {
        $servers = Get-ClaudeJsonProperty (Read-ClaudeJson (Join-Path $dir '.mcp.json')) 'mcpServers'
        foreach ($row in (Get-ClaudeMcpServerRow $servers 'project')) { $rows.Add($row) }
    }

    # A name configured in two scopes is one server to complete.
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in $rows) { if ($seen.Add($row.Name)) { $row } }
}

$script:ClaudeValueCompleters['McpServers'] = 'Get-ClaudeMcpServerItem'
