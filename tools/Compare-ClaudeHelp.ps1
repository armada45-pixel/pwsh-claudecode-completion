<#
.SYNOPSIS
    Compares the completion tree in src/Spec.ps1 with `claude --help`.

.DESCRIPTION
    A maintenance tool for updating the module to a new Claude Code version.
    It runs `claude <command> --help` for every command in the tree and
    reports:
      - flags and subcommands the help lists that the tree does not have
      - flags and subcommands in the tree that the help does not list
        (often on purpose: the CLI accepts flags it does not document)
      - flags whose value is required in one and optional or absent in the other

    This is the only place in the repository that runs the `claude` binary.
    Completion itself never does.

.EXAMPLE
    ./tools/Compare-ClaudeHelp.ps1
#>
[CmdletBinding()]
param(
    # The claude executable to ask.
    [string]$Claude = 'claude'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'pwsh-claudecode-completion.psd1') -Force
$spec = & (Get-Module pwsh-claudecode-completion) { Get-ClaudeSpec }

# Flags and subcommands as one help page lists them.
function Read-Help {
    param([string[]]$Path)
    $text = & $Claude @Path --help 2>&1 | ForEach-Object { "$_" }
    # `-h` and `-H` are different flags.
    $flags = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::Ordinal)
    $commands = [Collections.Generic.List[string]]::new()
    $inCommands = $false
    foreach ($line in $text) {
        if ($line -match '^\S.*:$') { $inCommands = $line -ceq 'Commands:'; continue }
        if ($inCommands) {
            if ($line -cmatch '^  ([a-z][\w|-]*)') { foreach ($name in $Matches[1].Split('|')) { $commands.Add($name) } }
            continue
        }
        # `  -x, --long, --alias <value>  description`; continuation lines are indented further.
        if ($line -cnotmatch '^  (-[^\s].*?)(?:\s{2,}|$)') { continue }
        $head = $Matches[1]
        $value = if ($head -match '\s<[^>]+>') { 'required' } elseif ($head -match '\s\[[^\]]+\]') { 'optional' } else { 'none' }
        foreach ($name in [regex]::Matches($head, '(?<![\w-])--?[A-Za-z][\w-]*')) { $flags[$name.Value] = $value }
    }
    [pscustomobject]@{ Found = [bool]($text -match '^Usage:'); Flags = $flags; Commands = $commands }
}

$report = [Collections.Generic.List[object]]::new()
function Add-Finding {
    param([string]$Command, [string]$Kind, [string]$Name, [string]$Detail = '')
    $report.Add([pscustomobject]@{ Command = $Command; Kind = $Kind; Name = $Name; Detail = $Detail })
}

$visited = [Collections.Generic.HashSet[object]]::new()
function Compare-Node {
    param($Node, [string[]]$Path)
    $label = (@('claude') + $Path) -join ' '
    $help = Read-Help $Path
    if (-not $help.Found) { Add-Finding $label 'no help page' ''; return }

    foreach ($name in $help.Flags.Keys) {
        if (-not $Node.FlagMap.ContainsKey($name)) { Add-Finding $label 'flag only in help' $name $help.Flags[$name]; continue }
        $flag = $Node.FlagMap[$name]
        $have = if (-not $flag.TakesValue) { 'none' } elseif ($flag.Optional) { 'optional' } else { 'required' }
        if ($have -ne $help.Flags[$name]) { Add-Finding $label 'flag value differs' $name "help: $($help.Flags[$name]), tree: $have" }
    }
    foreach ($flag in $Node.Flags) {
        foreach ($name in $flag.Names) {
            if (-not $help.Flags.ContainsKey($name)) { Add-Finding $label 'flag only in tree' $name }
        }
    }
    foreach ($name in $help.Commands) {
        if (-not $Node.Subs.ContainsKey($name)) { Add-Finding $label 'command only in help' $name }
    }
    foreach ($name in $Node.Subs.Keys) {
        if ($name -cnotin $help.Commands) { Add-Finding $label 'command only in tree' $name }
        $child = $Node.Subs[$name]
        # Aliases share a definition: ask about it once.
        if ($name -cne 'help' -and $visited.Add($child)) { Compare-Node $child ($Path + $name) }
    }
}

$version = (& $Claude --version 2>&1 | Select-Object -First 1) -replace '\s.*$'
$tracked = (Get-Content (Join-Path $PSScriptRoot '..' 'claude-version') -Raw).Trim()
Write-Host "claude $version installed, the tree tracks $tracked"
Compare-Node $spec @()
$report | Sort-Object Kind, Command, Name
