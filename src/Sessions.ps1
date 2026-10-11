# Session ids for `claude --resume` / `-r`: the sessions of the current
# project, newest first, each with the title `/resume` shows for it.

using namespace System.Text.Json

# Claude stores each project under <config>/projects/ in a folder named after
# the project path with every character other than a-z, A-Z and 0-9 replaced
# by `-` (`path.replace(/[^a-zA-Z0-9]/g, "-")`). That regex works on UTF-16
# code units, and so does .NET, so a character beyond U+FFFF becomes `--`
# here as it does there. `C:\Users\me\repo` becomes `C--Users-me-repo`.
function ConvertTo-ClaudeProjectFolder {
    param([string]$Path)
    [regex]::Replace($Path, '[^a-zA-Z0-9]', '-')
}

function Get-ClaudeSessionProjectDir {
    param([string]$Cwd)
    $projects = Join-Path (Get-ClaudeConfigDir) 'projects'
    if (-not [IO.Directory]::Exists($projects)) { return $null }

    $paths = @(Resolve-ClaudeRealPath $Cwd; $Cwd) | Select-Object -Unique
    foreach ($path in $paths) {
        $folder = ConvertTo-ClaudeProjectFolder $path
        $dir = Join-Path $projects $folder
        if ([IO.Directory]::Exists($dir)) { return $dir }
        # Claude cuts a long folder name at 200 characters and appends a hash.
        if ($folder.Length -gt 200) {
            foreach ($match in [IO.Directory]::EnumerateDirectories($projects, $folder.Substring(0, 200) + '-*')) { return $match }
        }
    }

    # No folder of that name (another naming scheme, or a session started
    # from another spelling of the path): find the project by the
    # `originalPath` recorded in its sessions-index.json.
    foreach ($dir in [IO.Directory]::EnumerateDirectories($projects)) {
        $index = Join-Path $dir 'sessions-index.json'
        if (-not [IO.File]::Exists($index)) { continue }
        $original = Get-ClaudeJsonString (Read-ClaudeJson $index) 'originalPath'
        foreach ($path in $paths) { if (Test-ClaudeSamePath $original $path) { return $dir } }
    }
    $null
}

# The first lines and the last lines of a session file. Titles are written
# at the start and appended throughout the session, so this finds them
# without reading a file of many megabytes; byte limits keep a session with
# very long lines cheap too.
function Read-ClaudeSessionLines {
    param([string]$Path)
    $headBytes = 262144
    $tailBytes = 65536
    $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
    try {
        $length = $stream.Length
        $size = [int][Math]::Min($length, $headBytes)
        $buffer = [byte[]]::new($size)
        $read = $stream.Read($buffer, 0, $size)
        $lines = [Text.Encoding]::UTF8.GetString($buffer, 0, $read).Split([char]10)
        $complete = $lines.Length
        # The last line of a partial read is cut off.
        if ($length -gt $size) { $complete-- }
        $count = [Math]::Min($complete, 100)
        for ($i = 0; $i -lt $count; $i++) { $lines[$i] }

        if ($length -le $size) {
            for ($i = [Math]::Max($count, $complete - 50); $i -lt $complete; $i++) { $lines[$i] }
            return
        }
        $start = [Math]::Max([long]$size, $length - $tailBytes)
        [void]$stream.Seek($start, [IO.SeekOrigin]::Begin)
        $buffer = [byte[]]::new([int]($length - $start))
        $read = $stream.Read($buffer, 0, $buffer.Length)
        $lines = [Text.Encoding]::UTF8.GetString($buffer, 0, $read).Split([char]10)
        # The first line starts somewhere in the middle.
        for ($i = [Math]::Max(1, $lines.Length - 50); $i -lt $lines.Length; $i++) { $lines[$i] }
    }
    finally { $stream.Dispose() }
}

$script:ClaudeSessionCache = @{}

# What a session file says about itself: branch and the candidates for a title.
function Get-ClaudeSessionInfo {
    param([IO.FileInfo]$File)
    $stamp = "$($File.LastWriteTimeUtc.Ticks):$($File.Length)"
    $hit = $script:ClaudeSessionCache[$File.FullName]
    if ($hit -and $hit.Stamp -eq $stamp) { return $hit.Info }

    $info = @{ Branch = ''; Custom = ''; Ai = ''; Summary = ''; Prompt = ''; Command = '' }
    $sawUser = $false
    try {
        foreach ($line in (Read-ClaudeSessionLines $File.FullName)) {
            # Most lines are assistant turns and tool output; parse only the candidates.
            if (-not ($line.Contains('"user"') -or $line.Contains('-title"') -or $line.Contains('"summary"'))) { continue }
            try { $document = [JsonDocument]::Parse($line) } catch { continue }
            try {
                $record = $document.RootElement
                switch -CaseSensitive (Get-ClaudeJsonString $record 'type') {
                    'custom-title' { $title = Get-ClaudeJsonString $record 'customTitle'; if ($title) { $info.Custom = $title } }
                    'ai-title' { $title = Get-ClaudeJsonString $record 'aiTitle'; if ($title) { $info.Ai = $title } }
                    'summary' { if (-not $info.Summary) { $info.Summary = [string](Get-ClaudeJsonString $record 'summary') } }
                    'user' {
                        if (-not $sawUser) {
                            $sawUser = $true
                            $info.Branch = [string](Get-ClaudeJsonString $record 'gitBranch')
                        }
                        $content = Get-ClaudeJsonProperty (Get-ClaudeJsonProperty $record 'message') 'content'
                        $text = $null
                        if ($null -ne $content) {
                            if ($content.ValueKind -eq [JsonValueKind]::String) { $text = $content.GetString() }
                            elseif ($content.ValueKind -eq [JsonValueKind]::Array) {
                                foreach ($block in $content.EnumerateArray()) {
                                    $text = Get-ClaudeJsonString $block 'text'
                                    if ($null -ne $text) { break }
                                }
                            }
                        }
                        if ($null -eq $text) { continue }
                        $meta = Get-ClaudeJsonProperty $record 'isMeta'
                        $isMeta = $null -ne $meta -and $meta.ValueKind -eq [JsonValueKind]::True
                        if (-not $info.Prompt -and -not $isMeta -and $text -notmatch '^\s*<(command|local-command)') {
                            $info.Prompt = $text
                        }
                        # A session of slash commands only (a quick `/exit`) is
                        # still listed by `/resume`, under the command's name.
                        if (-not $info.Command -and $text -match '<command-name>([^<]+)</command-name>') {
                            $info.Command = $Matches[1]
                        }
                    }
                }
            }
            finally { $document.Dispose() }
        }
    }
    catch { }

    if ($script:ClaudeSessionCache.Count -gt 2048) { $script:ClaudeSessionCache.Clear() }
    $script:ClaudeSessionCache[$File.FullName] = @{ Stamp = $stamp; Info = $info }
    $info
}

# "3 hours ago", in the buckets `/resume` uses.
function Format-ClaudeAge {
    param([long]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    $count, $unit = if ($Seconds -lt 60) { $Seconds, 'second' }
    elseif ($Seconds -lt 3600) { [Math]::Floor($Seconds / 60), 'minute' }
    elseif ($Seconds -lt 86400) { [Math]::Floor($Seconds / 3600), 'hour' }
    elseif ($Seconds -lt 604800) { [Math]::Floor($Seconds / 86400), 'day' }
    elseif ($Seconds -lt 2592000) { [Math]::Floor($Seconds / 604800), 'week' }
    elseif ($Seconds -lt 31536000) { [Math]::Floor($Seconds / 2592000), 'month' }
    else { [Math]::Floor($Seconds / 31536000), 'year' }
    if ($count -eq 1) { "1 $unit ago" } else { "$count ${unit}s ago" }
}

# "2.5MB": one decimal place, dropped when it is zero.
function Format-ClaudeSize {
    param([long]$Bytes)
    if ($Bytes -lt 1024) { return "${Bytes}B" }
    $divisor, $unit = if ($Bytes -lt 1048576) { 1024, 'KB' } elseif ($Bytes -lt 1073741824) { 1048576, 'MB' } else { 1073741824, 'GB' }
    $tenths = [long][Math]::Floor($Bytes * 10 / $divisor)
    $whole = [long][Math]::Floor($tenths / 10)
    if ($tenths % 10) { "$whole.$($tenths % 10)$unit" } else { "$whole$unit" }
}

function Get-ClaudeSessionItem {
    param($Context)
    $dir = Get-ClaudeSessionProjectDir $Context.Cwd
    if (-not $dir) { return }

    # A project with a long history has hundreds of session files. Offer the
    # 20 most recent unless CLAUDE_COMPLETION_SESSION_LIMIT says otherwise;
    # 0 or less lifts the cap.
    $limit = 20
    if ($env:CLAUDE_COMPLETION_SESSION_LIMIT) {
        $parsed = 0
        if ([int]::TryParse($env:CLAUDE_COMPLETION_SESSION_LIMIT, [ref]$parsed)) { $limit = $parsed }
    }

    $files = @([IO.DirectoryInfo]::new($dir).GetFiles('*.jsonl') | Where-Object Extension -CEQ '.jsonl')
    if (-not $files.Count) { return }
    # Newest first; the name settles a tie so the order is stable.
    $files = @($files | Sort-Object -Property @{ Expression = 'LastWriteTimeUtc'; Descending = $true }, @{ Expression = 'Name' })
    # Read a few more than the cap: a file with nothing to show is skipped.
    if ($limit -gt 0 -and $files.Count -gt $limit * 2 + 5) { $files = $files[0..($limit * 2 + 4)] }

    # sessions-index.json has the title `/resume` shows for older sessions.
    $indexed = @{}
    $entries = Get-ClaudeJsonProperty (Read-ClaudeJson (Join-Path $dir 'sessions-index.json')) 'entries'
    if ($null -ne $entries -and $entries.ValueKind -eq [JsonValueKind]::Array) {
        foreach ($entry in $entries.EnumerateArray()) {
            $id = Get-ClaudeJsonString $entry 'sessionId'
            if ($id) {
                $indexed[$id] = @{ Summary = Get-ClaudeJsonString $entry 'summary'; Branch = Get-ClaudeJsonString $entry 'gitBranch' }
            }
        }
    }

    $now = [DateTime]::UtcNow
    $count = 0
    foreach ($file in $files) {
        if ($limit -gt 0 -and $count -ge $limit) { break }
        $id = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $info = Get-ClaudeSessionInfo $file
        $entry = $indexed[$id]

        # A title set with /rename, then the generated one, then the index
        # summary, a summary record, the first prompt, the first slash command.
        $title = if ($info.Custom) { $info.Custom }
        elseif ($info.Ai) { $info.Ai }
        elseif ($entry -and $entry.Summary) { $entry.Summary }
        elseif ($info.Summary) { $info.Summary }
        elseif ($info.Prompt) { $info.Prompt }
        else { $info.Command }
        $title = ConvertTo-ClaudeDisplayText $title
        if (-not $title) { continue }
        if ($title.Length -gt 80) { $title = $title.Substring(0, 80) }

        $branch = if ($info.Branch) { $info.Branch } elseif ($entry -and $entry.Branch) { $entry.Branch } else { '?' }
        $age = Format-ClaudeAge ([long]($now - $file.LastWriteTimeUtc).TotalSeconds)
        $short = if ($id.Length -gt 8) { $id.Substring(0, 8) } else { $id }
        [pscustomobject]@{
            Name        = $id
            ListText    = "$short  $title"
            Description = "$age · $branch · $(Format-ClaudeSize $file.Length) - $title"
        }
        $count++
    }
}

$script:ClaudeValueCompleters['Sessions'] = 'Get-ClaudeSessionItem'
