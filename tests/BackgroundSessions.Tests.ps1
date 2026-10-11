# Background session ids for `claude attach|logs|stop|kill|respawn|rm`.
# Counterpart of test-background-session-ids.sh.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    function New-Job {
        param([string]$ConfigDir, [string]$Id, [string]$State, [datetime]$Modified)
        $path = Join-Path $ConfigDir 'jobs' $Id 'state.json'
        Set-TextFile $path $State
        if ($Modified) { [IO.File]::SetLastWriteTimeUtc($path, $Modified) }
    }

    $script:config = New-Directory (Join-Path $TestDrive 'config')
    $day = [datetime]::new(2026, 5, 9, 12, 0, 0, [DateTimeKind]::Utc)
    # Oldest: name and state.
    New-Job $config '7c5dcf5d' '{"name":"investigate flaky test","state":"done","intent":"not shown"}' $day.AddHours(-2)
    # `intent` but no `name`.
    New-Job $config '9a1b2c3d' '{"intent":"address PR review comments","state":"idle"}' $day.AddHours(-1)
    # Newest: moved to the background with /bg, so it is not in roster.json.
    New-Job $config '55eab974' '{"name":"imported via /bg"}' $day
    # In roster.json only: a placeholder that never became a session.
    [void](New-Directory (Join-Path $config 'jobs' '6d75c459'))
    Set-TextFile (Join-Path $config 'daemon' 'roster.json') '{"workers":[{"id":"6d75c459","name":"placeholder"}]}'
    # Broken or empty state files still mark a session; they have no label.
    New-Job $config 'broken01' '{ not json' $day.AddHours(-3)
    New-Job $config 'empty001' '' $day.AddHours(-4)
    New-Job $config 'odd00001' '{"name":42,"state":["x"]}' $day.AddHours(-5)

    $env:CLAUDE_CONFIG_DIR = $config
    Push-Location (New-Directory (Join-Path $TestDrive 'work'))
}

AfterAll {
    Pop-Location
    $env:CLAUDE_CONFIG_DIR = $null
}

Describe 'background session ids' {
    It 'lists every session with a state.json, most recently active first' {
        Get-CompletionText 'claude attach ' | Should -Be '55eab974', '9a1b2c3d', '7c5dcf5d', 'broken01', 'empty001', 'odd00001'
    }

    It 'leaves out a session that is only in roster.json' {
        Get-CompletionText 'claude attach ' | Should -Not -Contain '6d75c459'
    }

    It 'labels each session from its state.json' {
        $byId = @{}
        foreach ($match in (Get-Completion 'claude attach ')) { $byId[$match.CompletionText] = $match }
        $byId['7c5dcf5d'].ToolTip | Should -Be '[done] investigate flaky test'
        $byId['7c5dcf5d'].ListItemText | Should -Be '7c5dcf5d [done] investigate flaky test'
        $byId['9a1b2c3d'].ToolTip | Should -Be '[idle] address PR review comments'
        $byId['55eab974'].ToolTip | Should -Be 'imported via /bg'
        $byId['broken01'].ToolTip | Should -Be 'broken01'
        $byId['odd00001'].ListItemText | Should -Be 'odd00001'
    }

    It 'is offered by claude <_>' -ForEach 'attach', 'logs', 'stop', 'kill', 'respawn', 'rm' {
        Get-CompletionText "claude $_ 7c" | Should -Be '7c5dcf5d'
    }

    It 'is not offered for respawn --all' {
        Get-CompletionText 'claude respawn --all ' | Should -Not -Contain '7c5dcf5d'
        Get-CompletionText 'claude respawn --' | Should -Contain '--all'
    }

    It 'offers one session per command' {
        Get-CompletionText 'claude attach 7c5dcf5d ' | Should -Not -Contain '9a1b2c3d'
    }

    It 'follows CLAUDE_CONFIG_DIR, and ~/.claude without it' {
        $fakeHome = New-Directory (Join-Path $TestDrive 'home')
        New-Job (Join-Path $fakeHome '.claude') 'home0001' '{"name":"from home"}'
        Use-ClaudeEnvironment -HomeDir $fakeHome {
            Get-CompletionText 'claude logs ' | Should -Be 'home0001'
        }
        Use-ClaudeEnvironment -HomeDir $fakeHome -ConfigDir $config {
            Get-CompletionText 'claude logs ' | Should -Not -Contain 'home0001'
        }
    }

    It 'offers the flags, and no error, without a jobs directory' {
        Use-ClaudeEnvironment -ConfigDir (New-Directory (Join-Path $TestDrive 'empty-config')) {
            $Error.Clear()
            Get-CompletionText 'claude attach ' | Should -Be '-h', '--help'
            Get-CompletionText 'claude attach 7c' | Should -BeNullOrEmpty
            $Error.Count | Should -Be 0
        }
    }
}
