# Flags and their fixed values. Counterpart of test-global-flags.sh,
# test-hidden-flags.sh, test-agents-subcommand.sh, test-effort-values.sh,
# test-model-aliases.sh and test-setting-sources.sh.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    $env:CLAUDE_CONFIG_DIR = New-Directory (Join-Path $TestDrive 'config')
    Push-Location (New-Directory (Join-Path $TestDrive 'work'))
}

AfterAll {
    Pop-Location
    $env:CLAUDE_CONFIG_DIR = $null
}

Describe 'global flags' {
    It 'lists the long flags for --' {
        $texts = Get-CompletionText 'claude --'
        $texts.Count | Should -BeGreaterThan 80
        foreach ($flag in '--add-dir', '--model', '--resume', '--print', '--permission-mode', '--output-format', '--worktree') {
            $texts | Should -Contain $flag
        }
        $texts | Should -Not -Contain '-p'
    }

    It 'lists short and long flags for -' {
        $texts = Get-CompletionText 'claude -'
        foreach ($flag in '-c', '-d', '-h', '-n', '-p', '-r', '-v', '-w', '--continue') { $texts | Should -Contain $flag }
    }

    It 'shows the description as the tooltip' {
        $tips = Get-CompletionTip 'claude --'
        $tips['--continue'] | Should -Be 'Continue the most recent conversation in the current directory'
        $tips['--json-schema'] | Should -BeLike 'JSON Schema for structured output validation. Example: {"type":"object"*"required":`["name"`]}'
    }

    # The CLI accepts these although `claude --help` has no row for them; an
    # update made from the help text alone would drop them.
    It 'keeps the hidden flag <_>' -ForEach @(
        '--system-prompt-file', '--append-system-prompt-file', '--append-subagent-system-prompt',
        '--append-subagent-system-prompt-file', '--exec', '--maintenance', '--ref'
    ) {
        Get-CompletionText 'claude --' | Should -Contain $_
    }

    It 'matches flags by case' {
        $texts = Get-CompletionText 'claude mcp add -'
        $texts | Should -Contain '-h'
        $texts | Should -Contain '-H'
        Get-CompletionText 'claude mcp add -H' | Should -Be '-H'
        Get-CompletionText 'claude mcp add --H' | Should -BeNullOrEmpty
    }

    It 'stops offering a flag that is already there, under either name' {
        $texts = Get-CompletionText 'claude -p -'
        $texts | Should -Not -Contain '-p'
        $texts | Should -Not -Contain '--print'
        $texts | Should -Contain '--model'
    }

    It 'keeps offering a repeatable flag' {
        Get-CompletionText 'claude --add-dir a --add' | Should -Be '--add-dir'
        Get-CompletionText 'claude mcp add -e A=1 -' | Should -Contain '--env'
    }

    It 'leaves out flags that cannot be combined' {
        Get-CompletionText 'claude ultrareview --post --' | Should -Not -Contain '--no-post'
        Get-CompletionText 'claude ultrareview --no-post --' | Should -Not -Contain '--post'
        Get-CompletionText 'claude remote-control --session-id x -' | Should -Not -Contain '--continue'
        Get-CompletionText 'claude remote-control -c --' | Should -Not -Contain '--session-id'
    }

    It 'does not offer the global flags under a command' {
        Get-CompletionText 'claude mcp list -' | Should -Be '-h', '--help'
    }

    It 'offers the flags for an empty word when a command takes nothing else' {
        Get-CompletionText 'claude doctor ' | Should -Be '-h', '--help'
    }
}

Describe 'claude agents' {
    It 'offers its flags for <line>' -ForEach @(
        @{ line = 'claude agents ' }
        @{ line = 'claude agents --' }
    ) {
        $texts = Get-CompletionText $line
        foreach ($flag in '--add-dir', '--cwd', '--effort', '--json', '--model', '--permission-mode', '--setting-sources', '--strict-mcp-config') {
            $texts | Should -Contain $flag
        }
    }
}

Describe 'other commands' {
    It 'offers <flags> for <line>' -ForEach @(
        @{ line = 'claude purge --'; flags = '--all', '--dry-run', '--interactive', '--yes' }
        @{ line = 'claude project purge --'; flags = '--all', '--dry-run', '--interactive', '--yes' }
        @{ line = 'claude daemon run --'; flags = '--json-path', '--log-file' }
        @{ line = 'claude daemon status --'; flags = '--json-path', '--log-file' }
        @{ line = 'claude daemon stop --'; flags = '--any', '--keep-workers', '--json-path', '--log-file' }
        @{ line = 'claude plugin validate --'; flags = '--strict', '--json' }
        @{ line = 'claude respawn --'; flags = '--all', '--help' }
        @{ line = 'claude rm --'; flags = '--discard-unpushed', '--force-remove-worktree' }
        @{ line = 'claude auth login --'; flags = '--claudeai', '--console', '--email', '--sso' }
        @{ line = 'claude plugin install --'; flags = '--marketplace', '--scope', '--yes' }
        @{ line = 'claude self-hosted-runner --s'; flags = '--server-auto-mode-lists', '--session-stop-grace-sec', '--startup-timeout-min' }
        # In `claude --help`, not in the zsh plugin's `_claude`.
        @{ line = 'claude plugin marketplace add --'; flags = '--json', '--scope', '--sparse' }
        @{ line = 'claude plugin marketplace remove --'; flags = '--json', '--scope' }
        @{ line = 'claude plugin marketplace update --'; flags = '--json', '--help' }
        @{ line = 'claude mcp -'; flags = '-h', '--help' }
        @{ line = 'claude plugin marketplace -'; flags = '-h', '--help' }
    ) {
        $texts = Get-CompletionText $line
        foreach ($flag in $flags) { $texts | Should -Contain $flag }
    }
}

Describe 'fixed flag values' {
    It 'completes <line>' -ForEach @(
        @{ line = 'claude --effort '; expected = 'low', 'medium', 'high', 'xhigh', 'max', 'ultracode' }
        @{ line = 'claude agents --effort '; expected = 'low', 'medium', 'high', 'xhigh', 'max', 'ultracode' }
        @{ line = 'claude --permission-mode '; expected = 'acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan' }
        @{ line = 'claude agents --permission-mode '; expected = 'acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan' }
        @{ line = 'claude remote-control --permission-mode '; expected = 'acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan' }
        @{ line = 'claude --output-format '; expected = 'text', 'json', 'stream-json' }
        @{ line = 'claude --input-format '; expected = 'text', 'stream-json' }
        @{ line = 'claude --advisor '; expected = 'fable', 'opus', 'sonnet' }
        @{ line = 'claude --teammate-mode '; expected = 'auto', 'tmux', 'iterm2', 'in-process' }
        @{ line = 'claude --permission-prompts '; expected = 'host', 'none' }
        @{ line = 'claude --system-prompt-snapshot '; expected = 'on', 'off' }
        @{ line = 'claude mcp add --scope '; expected = 'local', 'user', 'project' }
        @{ line = 'claude mcp add -s '; expected = 'local', 'user', 'project' }
        @{ line = 'claude mcp add --transport '; expected = 'stdio', 'sse', 'http' }
        @{ line = 'claude plugin install --scope '; expected = 'user', 'project', 'local' }
        @{ line = 'claude plugin update --scope '; expected = 'user', 'project', 'local', 'managed' }
        @{ line = 'claude plugin marketplace add --scope '; expected = 'user', 'project', 'local' }
        @{ line = 'claude plugin init --with '; expected = 'skills', 'agents', 'hooks', 'mcp', 'lsp', 'output-style', 'channel' }
        @{ line = 'claude plugin eval --ablation '; expected = 'none', 'with-without' }
        @{ line = 'claude plugin eval --mocks '; expected = 'record', 'off' }
        @{ line = 'claude remote-control --spawn '; expected = 'same-dir', 'worktree', 'session' }
        @{ line = 'claude self-hosted-runner --host-config-snapshot '; expected = 'disk', 'memory' }
        @{ line = 'claude self-hosted-runner --confine-repo-settings '; expected = 'warn', 'enforce', 'off' }
        @{ line = 'claude self-hosted-runner --trust-workspace '; expected = 'true', 'false' }
        @{ line = 'claude self-hosted-runner orchestrator --log-level '; expected = 'info', 'debug' }
        @{ line = 'claude self-hosted-runner --server-auto-mode-lists '; expected = 'all', 'no-allow', 'none' }
        @{ line = 'claude --tmux '; expected = 'classic' }
    ) {
        Get-CompletionText $line | Should -Be $expected
    }

    It 'filters values by what is typed, ignoring case' {
        Get-CompletionText 'claude --effort x' | Should -Be 'xhigh'
        Get-CompletionText 'claude --permission-mode ACC' | Should -Be 'acceptEdits'
        Get-CompletionText 'claude --effort nope' | Should -BeNullOrEmpty
    }

    It 'completes a value written as --flag=value' {
        Get-CompletionText 'claude --effort=' | Should -Be '--effort=low', '--effort=medium', '--effort=high', '--effort=xhigh', '--effort=max', '--effort=ultracode'
        Get-CompletionText 'claude --output-format=s' | Should -Be '--output-format=stream-json'
        (Get-Completion 'claude --output-format=s')[0].ListItemText | Should -Be 'stream-json'
    }

    It 'completes a value inside quotes' {
        Get-CompletionText "claude --effort 'hi" | Should -Be 'high'
        Get-CompletionText 'claude --effort "hi' | Should -Be 'high'
    }

    It 'offers a value, not flags, right after a flag that needs one' {
        Get-CompletionText 'claude --output-format -' | Should -BeNullOrEmpty
    }

    It 'still offers flags after a flag whose value is optional' {
        Get-CompletionText 'claude --worktree --mod' | Should -Be '--model'
        Get-CompletionText 'claude self-hosted-runner --trust-workspace --cap' | Should -Be '--capacity'
    }
}

Describe 'model aliases' {
    It 'offers the aliases for <_>' -ForEach @(
        'claude --model ', 'claude agents --model ', 'claude auto-mode critique --model ',
        'claude plugin eval --model ', 'claude plugin eval --judge-model ', 'claude --fallback-model '
    ) {
        $tips = Get-CompletionTip $_
        $tips['opus'] | Should -Be 'Latest Opus, for complex reasoning tasks'
        $tips['haiku'] | Should -Be 'Fast and efficient Haiku, for simple tasks'
        $tips.Keys | Should -Contain 'opusplan'
        $tips.Keys | Should -Contain 'default'
    }

    It 'quotes an alias PowerShell would not pass on literally' {
        $match = Get-Completion 'claude --model sonnet['
        $match.CompletionText | Should -Be "'sonnet[1m]'"
        $match.ListItemText | Should -Be 'sonnet[1m]'
        $match.ToolTip | Should -Be 'Sonnet with a 1 million token context window'
    }

    It 'offers the remaining models in a comma-separated --fallback-model list' {
        $tips = Get-CompletionTip 'claude --fallback-model opus,'
        $tips.Keys | Should -Contain 'sonnet'
        $tips.Keys | Should -Not -Contain 'opus'
        $tips['sonnet'] | Should -Be 'Latest Sonnet, for daily coding tasks'
        Get-CompletionText 'claude --fallback-model opus,ha' | Should -Be 'haiku'
        Get-CompletionText 'claude --fallback-model opus,haiku,' | Should -Not -Contain 'haiku'
    }

    It 'offers only the advisor models for --advisor' {
        Get-CompletionText 'claude --advisor ' | Should -Not -Contain 'haiku'
    }
}

Describe '--setting-sources' {
    It 'offers every source first' {
        Get-CompletionText 'claude --setting-sources ' | Should -Be 'user', 'project', 'local'
    }

    It 'leaves out the sources already in the list' {
        Get-CompletionText 'claude --setting-sources user,' | Should -Be 'project', 'local'
        Get-CompletionText 'claude --setting-sources user,pro' | Should -Be 'project'
        Get-CompletionText 'claude --setting-sources user,project,' | Should -Be 'local'
        Get-CompletionText 'claude agents --setting-sources local,' | Should -Be 'user', 'project'
    }

    It 'replaces only the last item, so the list stays one word' {
        $line = 'claude --setting-sources user,pro'
        $result = [System.Management.Automation.CommandCompletion]::CompleteInput($line, $line.Length, $null)
        $done = $line.Remove($result.ReplacementIndex, $result.ReplacementLength).Insert($result.ReplacementIndex, $result.CompletionMatches[0].CompletionText)
        $done | Should -Be 'claude --setting-sources user,project'
    }

    It 'keeps the earlier items of a quoted list' {
        Get-CompletionText "claude --setting-sources 'user,pro" | Should -Be 'user,project'
    }

    # Culture-aware string searches skip punctuation under some cultures
    # (th-TH), and tr-TR has its own upper and lower case for `i`.
    It 'does not depend on the culture: <_>' -ForEach 'th-TH', 'tr-TR', 'en-US' {
        $saved = [cultureinfo]::CurrentCulture
        try {
            [cultureinfo]::CurrentCulture = [cultureinfo]::new($_)
            Get-CompletionText "claude --setting-sources 'user,pro" | Should -Be 'user,project'
            Get-CompletionText 'claude --setting-sources user,' | Should -Be 'project', 'local'
            Get-CompletionText 'claude --output-format=s' | Should -Be '--output-format=stream-json'
            Get-CompletionText 'claude --permission-mode ' | Should -Contain 'bypassPermissions'
            Get-CompletionText 'claude --i' | Should -Contain '--input-format'
            Get-CompletionText 'claude I' | Should -Be 'import', 'install'
        }
        finally { [cultureinfo]::CurrentCulture = $saved }
    }

    It 'works in the --flag=value form' {
        Get-CompletionText 'claude --setting-sources=u' | Should -Be '--setting-sources=user'
    }
}
