# Agent names for `--agent`, the way Claude finds them
# (https://code.claude.com/docs/en/sub-agents):
#   - project: every `.claude/agents/` from the working directory up to the
#     repository root, closest first, so `claude --agent` works from a
#     subdirectory. Outside a repository only the working directory counts.
#   - user: `<config>/agents`, `~/.claude/agents` by default.
#   - both are searched recursively, and the agent is identified by the
#     `name` in its frontmatter, never by its path or file name. A file
#     without usable frontmatter is skipped.
#   - plugin: see Get-ClaudePluginAgentItem. Only the scoped name is offered.
#     Claude also takes the last part alone, but then a user or project
#     agent of that name wins, and so does the first of two plugins.
#   - built-in: the agents Claude registers itself. A user or project agent
#     of the same name replaces one, so it is listed once.

using namespace System.Text.Json

$script:ClaudeAgentCache = @{}

# The `name` and the `description` in the frontmatter of an agent file, each
# empty when it is missing. Only the start of the file is read.
function Read-ClaudeAgentFrontmatter {
    param([IO.FileInfo]$File)
    $stamp = "$($File.LastWriteTimeUtc.Ticks):$($File.Length)"
    $hit = $script:ClaudeAgentCache[$File.FullName]
    if ($hit -and $hit.Stamp -eq $stamp) { return $hit.Value }

    $name = ''
    $description = ''
    try {
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.FileStream]::new($File.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        try {
            $buffer = [byte[]]::new([int][Math]::Min($stream.Length, 65536))
            $read = $stream.Read($buffer, 0, $buffer.Length)
        }
        finally { $stream.Dispose() }
        # A byte-order mark may precede the opening `---`.
        $lines = [Text.Encoding]::UTF8.GetString($buffer, 0, $read).TrimStart([char]0xFEFF).Split([char]10)

        $block = $false
        if ($lines.Length -and $lines[0].TrimEnd() -ceq '---') {
            for ($i = 1; $i -lt $lines.Length -and $i -lt 200; $i++) {
                $line = $lines[$i].TrimEnd([char]13)
                if ($line.TrimEnd() -ceq '---') { break }
                if ($block) {
                    # First line of a `description: |` or `>` block.
                    $block = $false
                    if ($line -match '^\s+\S') { $description = $line.Trim(); continue }
                }
                if ($line -cnotmatch '^(name|description):(.*)$') { continue }
                $key = $Matches[1]
                $value = $Matches[2].TrimStart()
                if ($value.Length -and $value[0] -in [char]34, [char]39) {
                    $close = $value.IndexOf($value[0], 1)
                    $value = if ($close -lt 0) { $value.Substring(1) } else { $value.Substring(1, $close - 1) }
                }
                else {
                    # Unquoted: drop a trailing ` # comment`, then trailing blanks.
                    $value = ($value -replace '^#.*$', '' -replace '\s+#.*$', '').TrimEnd()
                }
                if ($key -ceq 'name') { $name = $value }
                elseif ($value -match '^[|>][+-]?[0-9]?$') { $block = $true }
                else { $description = $value }
            }
        }
    }
    catch { $name = ''; $description = '' }

    # Descriptions often carry escaped examples; keep the first line short.
    $cut = $description.IndexOf('\n', [StringComparison]::Ordinal)
    if ($cut -ge 0) { $description = $description.Substring(0, $cut) }
    $value = [pscustomobject]@{ Name = $name; Description = Limit-ClaudeText $description }

    if ($script:ClaudeAgentCache.Count -gt 2048) { $script:ClaudeAgentCache.Clear() }
    $script:ClaudeAgentCache[$File.FullName] = @{ Stamp = $stamp; Value = $value }
    $value
}

# The `.md` files under a directory, at any depth, in a stable order.
function Get-ClaudeAgentFiles {
    param([string]$Directory)
    if (-not [IO.Directory]::Exists($Directory)) { return }
    try {
        $options = [IO.EnumerationOptions]::new()
        $options.RecurseSubdirectories = $true
        $options.IgnoreInaccessible = $true
        $files = [IO.DirectoryInfo]::new($Directory).GetFiles('*.md', $options)
        [Array]::Sort($files, [Comparison[IO.FileInfo]] { param($a, $b) [string]::CompareOrdinal($a.FullName, $b.FullName) })
        foreach ($file in $files) { if ($file.Extension -ceq '.md') { $file } }
    }
    catch { }
}

function Get-ClaudeAgentItem {
    param($Context)
    $dirs = @(Get-ClaudeProjectDirs $Context.Cwd)
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

    $agentDirs = @(foreach ($dir in $dirs) { [IO.Path]::Combine($dir, '.claude', 'agents') }) + @(Join-Path (Get-ClaudeConfigDir) 'agents')
    foreach ($agentDir in $agentDirs) {
        foreach ($file in (Get-ClaudeAgentFiles $agentDir)) {
            $agent = Read-ClaudeAgentFrontmatter $file
            # `:` is reserved for plugin-scoped agents; Claude skips such a file.
            if (-not $agent.Name -or $agent.Name.Contains([char]':')) { continue }
            if (-not $seen.Add($agent.Name)) { continue }
            $agent
        }
    }

    Get-ClaudePluginAgentItem $dirs

    foreach ($agent in $script:ClaudeBuiltInAgents) {
        if (-not $seen.Contains($agent.Name)) { $agent }
    }
}

# The descriptions are from the sub-agents page.
$script:ClaudeBuiltInAgents = @(
    [pscustomobject]@{ Name = 'general-purpose'; Description = 'Complex, multi-step tasks that need both exploration and action' }
    [pscustomobject]@{ Name = 'statusline-setup'; Description = 'Configures your status line' }
    [pscustomobject]@{ Name = 'claude'; Description = 'Catch-all with every tool available to subagents' }
    [pscustomobject]@{ Name = 'Explore'; Description = 'Fast, read-only agent for searching and analyzing codebases' }
    [pscustomobject]@{ Name = 'Plan'; Description = 'Research agent that gathers context before presenting a plan' }
    [pscustomobject]@{ Name = 'claude-code-guide'; Description = 'Answers questions about Claude Code features' }
)

# The agents of the installed plugins
# (https://code.claude.com/docs/en/plugins/components#agents):
#   - installed_plugins.json names each plugin's `installPath`. The cache
#     directory also keeps older versions, so it is not searched. An
#     install with project or local scope counts only inside its project.
#   - a plugin is skipped when `enabledPlugins` turns it off in the user's
#     settings.json or the working directory's .claude/settings.json or
#     settings.local.json (the later file wins), or when nothing sets it
#     and its manifest says `defaultEnabled: false`.
#   - the agent is `<plugin>:<subfolders of agents/>:<name>`, the name
#     being the frontmatter `name`, or the file name without it. `<plugin>`
#     is the manifest's `name`, the part before `@` without a manifest.
#   - `agents` in the manifest replaces the `agents/` scan with the listed
#     `.md` files, which get no subfolder in their name.
# A broken settings file or manifest is skipped, not the plugin.
function Get-ClaudePluginAgentItem {
    param([string[]]$ProjectDirs)
    $installed = Get-ClaudeJsonProperty (Read-ClaudeJson (Join-Path (Get-ClaudePluginsDir) 'installed_plugins.json')) 'plugins'
    if ($null -eq $installed -or $installed.ValueKind -ne [JsonValueKind]::Object) { return }

    # enabledPlugins, merged in the order the files apply.
    $enabled = @{}
    $settingsFiles = @(
        Join-Path (Get-ClaudeConfigDir) 'settings.json'
        [IO.Path]::Combine($ProjectDirs[0], '.claude', 'settings.json')
        [IO.Path]::Combine($ProjectDirs[0], '.claude', 'settings.local.json')
    )
    foreach ($file in $settingsFiles) {
        $entries = Get-ClaudeJsonProperty (Read-ClaudeJson $file) 'enabledPlugins'
        if ($null -eq $entries -or $entries.ValueKind -ne [JsonValueKind]::Object) { continue }
        foreach ($entry in $entries.EnumerateObject()) { $enabled[$entry.Name] = $entry.Value.ValueKind -ne [JsonValueKind]::False }
    }

    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $installed.EnumerateObject()) {
        $id = $entry.Name
        if ($enabled.ContainsKey($id) -and -not $enabled[$id]) { continue }

        # The install for this project if there is one, else the first that is not tied to a project.
        $root = $null
        $fallback = $null
        foreach ($install in (Get-ClaudePluginInstalls $entry.Value)) {
            $path = Get-ClaudeJsonString $install 'installPath'
            if (-not $path) { continue }
            $projectPath = Get-ClaudeJsonString $install 'projectPath'
            if ($null -ne $projectPath -and ($ProjectDirs | Where-Object { Test-ClaudeSamePath $projectPath $_ })) { $root = $path; break }
            $scope = Get-ClaudeJsonString $install 'scope'
            if (-not $fallback -and $scope -cne 'project' -and $scope -cne 'local') { $fallback = $path }
        }
        if (-not $root) { $root = $fallback }
        if (-not $root -or -not [IO.Directory]::Exists($root)) { continue }
        $root = [IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)

        $plugin = $id.Split([char]'@')[0]
        $manifest = Read-ClaudeJson ([IO.Path]::Combine($root, '.claude-plugin', 'plugin.json'))
        $listed = $null
        if ($null -ne $manifest -and $manifest.ValueKind -eq [JsonValueKind]::Object) {
            $name = Get-ClaudeJsonString $manifest 'name'
            if ($name) { $plugin = $name }
            $default = Get-ClaudeJsonProperty $manifest 'defaultEnabled'
            if (-not $enabled.ContainsKey($id) -and $null -ne $default -and $default.ValueKind -eq [JsonValueKind]::False) { continue }
            $agents = Get-ClaudeJsonProperty $manifest 'agents'
            if ($null -ne $agents) {
                $listed = @(
                    if ($agents.ValueKind -eq [JsonValueKind]::String) { $agents.GetString() }
                    elseif ($agents.ValueKind -eq [JsonValueKind]::Array) {
                        foreach ($item in $agents.EnumerateArray()) { if ($item.ValueKind -eq [JsonValueKind]::String) { $item.GetString() } }
                    }
                )
            }
        }

        $agentsDir = [IO.Path]::Combine($root, 'agents')
        $files = if ($null -ne $listed) {
            foreach ($path in $listed) {
                # Paths start with `./` and stay inside the plugin.
                if ($path -cnotlike './*.md' -or $path.Contains('..')) { continue }
                $file = [IO.FileInfo]::new([IO.Path]::Combine($root, $path.Substring(2)))
                if ($file.Exists) { $file }
            }
        }
        else { Get-ClaudeAgentFiles $agentsDir }

        foreach ($file in $files) {
            $agent = Read-ClaudeAgentFrontmatter $file
            # Claude's own fallbacks for a file without usable frontmatter.
            $name = if ($agent.Name) { $agent.Name } else { [IO.Path]::GetFileNameWithoutExtension($file.Name) }
            $description = if ($agent.Description) { $agent.Description } else { "Agent from $plugin plugin" }
            $scope = ''
            if ($null -eq $listed) {
                $folder = $file.DirectoryName.Substring($agentsDir.Length)
                $scope = $folder.Replace([IO.Path]::DirectorySeparatorChar, [char]':').Replace([IO.Path]::AltDirectorySeparatorChar, [char]':')
            }
            $name = "$plugin${scope}:$name"
            if ($seen.Add($name)) { [pscustomobject]@{ Name = $name; Description = $description } }
        }
    }
}

$script:ClaudeValueCompleters['Agents'] = 'Get-ClaudeAgentItem'
