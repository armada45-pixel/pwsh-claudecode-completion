# Shared by every *.Tests.ps1: dot-source it from BeforeAll.
#
# Completion is driven the way PSReadLine drives it, through
# CommandCompletion.CompleteInput, so the tests cover the registration and
# the engine together. Nothing here reads the real ~/.claude: every test file
# points CLAUDE_CONFIG_DIR and HOME at a directory under TestDrive.

Import-Module (Join-Path $PSScriptRoot '..' 'pwsh-claudecode-completion.psd1') -Force

# The matches for a command line. The cursor is at the end unless -Cursor is given.
function Get-Completion {
    param([Parameter(Mandatory)][string]$Line, [int]$Cursor = -1)
    if ($Cursor -lt 0) { $Cursor = $Line.Length }
    @([System.Management.Automation.CommandCompletion]::CompleteInput($Line, $Cursor, $null).CompletionMatches)
}

function Get-CompletionText {
    param([Parameter(Mandatory)][string]$Line, [int]$Cursor = -1)
    @((Get-Completion $Line $Cursor).CompletionText)
}

# Tooltip by completion text, for checking descriptions.
function Get-CompletionTip {
    param([Parameter(Mandatory)][string]$Line)
    $tips = @{}
    foreach ($match in (Get-Completion $Line)) { $tips[$match.CompletionText] = $match.ToolTip }
    $tips
}

# The path Claude records for a directory: symbolic links resolved (on macOS
# the temp directory is one).
function Resolve-RealPath {
    param([Parameter(Mandatory)][string]$Path)
    & (Get-Module pwsh-claudecode-completion) { param($p) Resolve-ClaudeRealPath $p } $Path
}

# The folder name Claude gives a project under projects/.
function ConvertTo-ProjectFolder {
    param([Parameter(Mandatory)][string]$Path)
    [regex]::Replace($Path, '[^a-zA-Z0-9]', '-')
}

function New-Directory {
    param([Parameter(Mandatory)][string]$Path)
    (New-Item -ItemType Directory -Force -Path $Path).FullName
}

# Write a file as UTF-8 without a byte-order mark, creating its directory.
function Set-TextFile {
    param([Parameter(Mandatory)][string]$Path, [string]$Text = '')
    [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

# Run a script block with the environment a fixture needs, then restore it.
#   -ConfigDir sets CLAUDE_CONFIG_DIR; -HomeDir sets HOME and USERPROFILE and
#   clears CLAUDE_CONFIG_DIR unless -ConfigDir is given too.
function Use-ClaudeEnvironment {
    param([string]$ConfigDir, [string]$HomeDir, [string]$Cwd, [hashtable]$Environment = @{}, [Parameter(Mandatory)][scriptblock]$Body)
    $names = @('CLAUDE_CONFIG_DIR', 'CLAUDE_CODE_PLUGIN_CACHE_DIR', 'CLAUDE_COMPLETION_SESSION_LIMIT', 'HOME', 'USERPROFILE') + @($Environment.Keys)
    $saved = @{}
    foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
    try {
        foreach ($name in 'CLAUDE_CONFIG_DIR', 'CLAUDE_CODE_PLUGIN_CACHE_DIR', 'CLAUDE_COMPLETION_SESSION_LIMIT') {
            [Environment]::SetEnvironmentVariable($name, $null)
        }
        if ($HomeDir) { $env:HOME = $HomeDir; $env:USERPROFILE = $HomeDir }
        if ($ConfigDir) { $env:CLAUDE_CONFIG_DIR = $ConfigDir }
        foreach ($name in $Environment.Keys) { [Environment]::SetEnvironmentVariable($name, $Environment[$name]) }
        if ($Cwd) { Push-Location -LiteralPath $Cwd }
        try { & $Body } finally { if ($Cwd) { Pop-Location } }
    }
    finally {
        foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}
