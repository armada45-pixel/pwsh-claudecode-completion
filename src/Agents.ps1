# Agent names for `--agent`, the way Claude finds them
# (https://code.claude.com/docs/en/sub-agents):
#   - project: every `.claude/agents/` from the working directory up to the
#     repository root, closest first, so `claude --agent` works from a
#     subdirectory. Outside a repository only the working directory counts.
#   - user: `<config>/agents`, `~/.claude/agents` by default.
#   - both are searched recursively, and the agent is identified by the
#     `name` in its frontmatter, never by its path or file name. A file
#     without usable frontmatter is skipped.

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
}

$script:ClaudeValueCompleters['Agents'] = 'Get-ClaudeAgentItem'
