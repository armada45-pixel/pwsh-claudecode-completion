# Where Claude keeps its files, and safe ways to read them. The value
# completers only ever read files: they never run `claude` and never use the
# network. A missing, empty or malformed file reads as "nothing there".

using namespace System.Text.Json

# The home directory as Claude (Node's os.homedir()) sees it.
function Get-ClaudeHome {
    $userHome = if ($IsWindows) { $env:USERPROFILE } else { $env:HOME }
    if (-not $userHome) { $userHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile) }
    $userHome
}

# ~/.claude, or CLAUDE_CONFIG_DIR.
function Get-ClaudeConfigDir {
    if ($env:CLAUDE_CONFIG_DIR) { return $env:CLAUDE_CONFIG_DIR }
    Join-Path (Get-ClaudeHome) '.claude'
}

# ~/.claude.json. With CLAUDE_CONFIG_DIR set, the file is inside that directory.
function Get-ClaudeJsonPath {
    if ($env:CLAUDE_CONFIG_DIR) { return Join-Path $env:CLAUDE_CONFIG_DIR '.claude.json' }
    Join-Path (Get-ClaudeHome) '.claude.json'
}

# ~/.claude/plugins, or CLAUDE_CODE_PLUGIN_CACHE_DIR, as Claude does.
function Get-ClaudePluginsDir {
    if ($env:CLAUDE_CODE_PLUGIN_CACHE_DIR) { return $env:CLAUDE_CODE_PLUGIN_CACHE_DIR }
    Join-Path (Get-ClaudeConfigDir) 'plugins'
}

# A path with its symbolic links (and, on Windows, junctions) resolved:
# Claude keys project state by the resolved path.
function Resolve-ClaudeRealPath {
    param([string]$Path)
    try {
        $full = [IO.Path]::GetFullPath($Path)
        $root = [IO.Path]::GetPathRoot($full)
        $current = $root
        $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        foreach ($part in $full.Substring($root.Length).Split($separators, [StringSplitOptions]::RemoveEmptyEntries)) {
            $current = [IO.Path]::Combine($current, $part)
            $info = [IO.DirectoryInfo]::new($current)
            if ($info.LinkTarget) {
                $target = $info.ResolveLinkTarget($true)
                if ($target) { $current = $target.FullName }
            }
        }
        $current
    }
    catch { $Path }
}

# The directories Claude treats as the current project: the working directory
# and each parent up to the repository root, closest first. Outside a
# repository that is the working directory alone.
function Get-ClaudeProjectDirs {
    param([string]$Cwd)
    $start = Resolve-ClaudeRealPath $Cwd
    $dirs = [Collections.Generic.List[string]]::new()
    $dir = $start
    while ($dir) {
        $dirs.Add($dir)
        # `.git` is a directory in a repository and a file in a worktree.
        $git = [IO.Path]::Combine($dir, '.git')
        if ([IO.Directory]::Exists($git) -or [IO.File]::Exists($git)) { return $dirs }
        $dir = [IO.Path]::GetDirectoryName($dir)
    }
    , $start
}

# Whether two paths written by Claude name the same directory. Windows paths
# compare without case, and Claude has written them with `\` and with `/`.
function Test-ClaudeSamePath {
    param([string]$Left, [string]$Right)
    if (-not $Left -or -not $Right) { return $false }
    if ($IsWindows) {
        $Left = $Left.Replace('/', '\').TrimEnd('\')
        $Right = $Right.Replace('/', '\').TrimEnd('\')
        return [string]::Equals($Left, $Right, [StringComparison]::OrdinalIgnoreCase)
    }
    [string]::Equals($Left, $Right, [StringComparison]::Ordinal)
}

# Read a file Claude may be writing to at this moment. $null when it cannot be read.
function Read-ClaudeText {
    param([string]$Path)
    try {
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        try {
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
            $reader.ReadToEnd()
        }
        finally { $stream.Dispose() }
    }
    catch { $null }
}

# Parsed JSON files, by path. A file is parsed again only when its time stamp
# or size changes, so a large ~/.claude.json costs one parse, not one per Tab.
$script:ClaudeJsonCache = @{}

# The root element of a JSON file, or $null when the file is missing, empty
# or not JSON.
function Read-ClaudeJson {
    param([string]$Path)
    try {
        $info = [IO.FileInfo]::new($Path)
        if (-not $info.Exists -or $info.Length -eq 0) { return $null }
        $stamp = "$($info.LastWriteTimeUtc.Ticks):$($info.Length)"
        $hit = $script:ClaudeJsonCache[$info.FullName]
        if ($hit -and $hit.Stamp -eq $stamp) { return $hit.Root }

        $root = $null
        $text = Read-ClaudeText $info.FullName
        if ($text) {
            try { $root = [JsonDocument]::Parse($text).RootElement } catch { $root = $null }
        }
        if ($script:ClaudeJsonCache.Count -gt 256) { $script:ClaudeJsonCache.Clear() }
        $script:ClaudeJsonCache[$info.FullName] = @{ Stamp = $stamp; Root = $root }
        $root
    }
    catch { $null }
}

# The property of a JSON object, or $null when the element is not an object
# or has no such property.
function Get-ClaudeJsonProperty {
    param($Element, [string]$Name)
    if ($null -eq $Element -or $Element.ValueKind -ne [JsonValueKind]::Object) { return $null }
    # The out parameter has to be typed, or PowerShell finds no overload.
    [JsonElement]$value = [JsonElement]::new()
    if ($Element.TryGetProperty($Name, [ref]$value)) { return $value }
    $null
}

# The same, but only when the property is a string.
function Get-ClaudeJsonString {
    param($Element, [string]$Name)
    $value = Get-ClaudeJsonProperty $Element $Name
    if ($null -ne $value -and $value.ValueKind -eq [JsonValueKind]::String) { return $value.GetString() }
    $null
}

# Cut a description to one short line.
function Limit-ClaudeText {
    param([string]$Text, [int]$Length = 80)
    $Text = ConvertTo-ClaudeDisplayText $Text
    if ($Text.Length -gt $Length) { return $Text.Substring(0, $Length - 3) + '...' }
    $Text
}
