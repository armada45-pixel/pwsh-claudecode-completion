# Background session ids for `claude attach|logs|stop|kill|respawn|rm`.
#
# This lists what `claude agents` lists: every <config>/jobs/<id>/ that has a
# state.json. daemon/roster.json is not used. It can hold placeholders for
# sessions that never started, and it misses sessions moved to the background
# with /bg from an interactive terminal.

function Get-ClaudeBackgroundSessionItem {
    param($Context)
    $jobs = Join-Path (Get-ClaudeConfigDir) 'jobs'
    if (-not [IO.Directory]::Exists($jobs)) { return }

    $rows = foreach ($dir in [IO.Directory]::EnumerateDirectories($jobs)) {
        $file = [IO.FileInfo]::new((Join-Path $dir 'state.json'))
        if (-not $file.Exists) { continue }
        $state = Read-ClaudeJson $file.FullName
        # `name` is generated or set by the user, `intent` is the prompt the
        # session started from. The other names are a guard against a rename.
        $name = ''
        foreach ($key in 'name', 'displayName', 'title', 'sessionName', 'intent', 'summary', 'prompt') {
            $name = Get-ClaudeJsonString $state $key
            if ($name) { break }
        }
        $status = ''
        foreach ($key in 'state', 'status', 'lifecycle') {
            $status = Get-ClaudeJsonString $state $key
            if ($status) { break }
        }
        $label = if ($name -and $status) { "[$status] $name" } elseif ($name) { $name } elseif ($status) { "[$status]" } else { '' }
        $id = [IO.Path]::GetFileName($dir)
        [pscustomobject]@{
            Name        = $id
            ListText    = "$id $label".TrimEnd()
            Description = $label
            # The supervisor rewrites state.json on every turn, so its time
            # stamp is the session's last activity.
            Modified    = $file.LastWriteTimeUtc
        }
    }
    $rows | Sort-Object -Property @{ Expression = 'Modified'; Descending = $true }, @{ Expression = 'Name' }
}

$script:ClaudeValueCompleters['BackgroundSessions'] = 'Get-ClaudeBackgroundSessionItem'
