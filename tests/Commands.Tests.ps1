# Commands and subcommands. Counterpart of test-commands-shadow.sh,
# test-mcp-subcommand.sh, test-daemon-subcommand.sh, test-purge-subcommand.sh,
# test-self-hosted-runner.sh and test-nested-positionals.sh.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    $script:work = New-Directory (Join-Path $TestDrive 'work')
    [void](New-Directory (Join-Path $work 'alpha-dir'))
    [void](New-Directory (Join-Path $work 'some-project'))
    Set-TextFile (Join-Path $work 'server.sh')
    $script:config = New-Directory (Join-Path $TestDrive 'config')
    $env:CLAUDE_CONFIG_DIR = $config
    Push-Location $work
}

AfterAll {
    Pop-Location
    $env:CLAUDE_CONFIG_DIR = $null
}

Describe 'top-level commands' {
    BeforeAll {
        $script:expected = @(
            'agents', 'attach', 'auth', 'auto-mode', 'daemon', 'doctor', 'gateway', 'import', 'install', 'kill',
            'logs', 'mcp', 'plugin', 'plugins', 'project', 'purge', 'remote-control', 'respawn', 'rm',
            'self-hosted-runner', 'setup-token', 'stop', 'ultrareview', 'update', 'upgrade'
        )
    }

    It 'lists every command exactly once, in alphabetical order' {
        Get-CompletionText 'claude ' | Should -Be $expected
    }

    It 'describes each command' {
        $tips = Get-CompletionTip 'claude '
        $tips['mcp'] | Should -Be 'Configure and manage MCP servers'
        $tips['purge'] | Should -BeLike 'Delete all Claude Code state for a project*'
        $tips['kill'] | Should -Be 'Stop a background session (alias for stop)'
        foreach ($name in $expected) { $tips[$name] | Should -Not -BeNullOrEmpty }
    }

    It 'filters by what is typed' {
        Get-CompletionText 'claude se' | Should -Be 'self-hosted-runner', 'setup-token'
        Get-CompletionText 'claude plugin' | Should -Be 'plugin', 'plugins'
    }

    It 'offers commands after flags an alias put in front' {
        Get-CompletionText 'claude --verbose m' | Should -Be 'mcp'
        Get-CompletionText 'claude --model opus m' | Should -Be 'mcp'
    }

    It 'does not offer commands once a prompt has been typed' {
        Get-CompletionText 'claude "fix the bug" ' | Should -Not -Contain 'mcp'
    }

    It 'has something to offer under every command' {
        foreach ($name in $expected) {
            # A subcommand list, or at least --help.
            (Get-Completion "claude $name ").Count | Should -BeGreaterThan 0 -Because "claude $name takes something"
        }
    }
}

Describe 'nested subcommands' {
    It 'completes <line>' -ForEach @(
        @{ line = 'claude mcp '; expected = 'add', 'add-from-claude-desktop', 'add-json', 'get', 'help', 'list', 'login', 'logout', 'remove', 'reset-project-choices', 'serve' }
        @{ line = 'claude auth '; expected = 'help', 'login', 'logout', 'status' }
        @{ line = 'claude daemon '; expected = 'logs', 'run', 'status', 'stop', 'uninstall' }
        @{ line = 'claude auto-mode '; expected = 'config', 'critique', 'defaults', 'help', 'reset' }
        @{ line = 'claude project '; expected = 'help', 'purge' }
        @{ line = 'claude plugin marketplace '; expected = 'add', 'help', 'list', 'remove', 'rm', 'update' }
        @{ line = 'claude plugins marketplace '; expected = 'add', 'help', 'list', 'remove', 'rm', 'update' }
        @{ line = 'claude self-hosted-runner '; expected = 'doctor', 'orchestrator', 'setup' }
    ) {
        Get-CompletionText $line | Should -Be $expected
    }

    It 'lists the plugin commands with their descriptions' {
        $tips = Get-CompletionTip 'claude plugin '
        $tips.Keys | Sort-Object | Should -Be (@(
                'autoremove', 'configure', 'details', 'disable', 'enable', 'eval', 'help', 'i', 'init', 'install', 'list',
                'marketplace', 'new', 'prune', 'remove', 'tag', 'test', 'uninstall', 'update', 'validate'
            ) | Sort-Object)
        $tips['test'] | Should -Be "Run a mod's tests"
        $tips['marketplace'] | Should -Be 'Manage Claude Code marketplaces'
    }

    It 'describes the marketplace commands' {
        (Get-CompletionTip 'claude plugin marketplace ')['add'] | Should -Be 'Add a marketplace from a URL, path, or GitHub repo'
    }

    It 'finds the subcommand after flags, with or without a value' {
        Get-CompletionText 'claude --verbose mcp g' | Should -Be 'get'
        Get-CompletionText 'claude --model opus plugin marketplace a' | Should -Be 'add'
        Get-CompletionText 'claude --model=opus plugin marketplace a' | Should -Be 'add'
    }

    It 'takes a flag value that looks like a command as the value' {
        # `--model mcp`: mcp is the model here, so the command list is still due.
        Get-CompletionText 'claude --model mcp a' | Should -Be 'agents', 'attach', 'auth', 'auto-mode'
    }

    It 'takes an optional flag value that names a command as the command' {
        Get-CompletionText 'claude --debug mcp g' | Should -Be 'get'
        Get-CompletionText 'claude --worktree mcp g' | Should -Be 'get'
    }

    It 'only looks at the words before the cursor' {
        # Cursor right after `--m`: the later `mcp get foo` must not switch to the mcp flags.
        $line = 'claude --m mcp get foo'
        Get-CompletionText $line -Cursor 10 | Should -Contain '--model'
        Get-CompletionText $line -Cursor 10 | Should -Contain '--mcp-config'
    }

    It 'does not treat the word under the cursor as a command yet' {
        Get-CompletionText 'claude plugin' | Should -Not -Contain 'marketplace'
    }
}

Describe 'positional arguments of nested subcommands' {
    It 'completes a path for plugin validate' {
        Get-CompletionText 'claude plugin validate ' | Should -Contain (Join-Path '.' 'alpha-dir')
        Get-CompletionText 'claude --verbose plugin validate ' | Should -Contain (Join-Path '.' 'alpha-dir')
    }

    It 'completes the command of mcp add, after the name' {
        Get-CompletionText 'claude mcp add myserver ' | Should -Contain (Join-Path '.' 'server.sh')
        Get-CompletionText 'claude mcp add --scope user myserver ' | Should -Contain (Join-Path '.' 'server.sh')
    }

    It 'completes the source of marketplace add after a flag with a value' {
        Get-CompletionText 'claude --model opus plugin marketplace add ' | Should -Contain (Join-Path '.' 'alpha-dir')
    }

    It 'completes only directories for <line>' -ForEach @(
        @{ line = 'claude purge ' }
        @{ line = 'claude project purge ' }
        @{ line = 'claude plugin test ' }
        @{ line = 'claude --add-dir ' }
        @{ line = 'claude agents --cwd ' }
    ) {
        $texts = Get-CompletionText $line
        $texts | Should -Contain (Join-Path '.' 'some-project')
        $texts | Should -Not -Contain (Join-Path '.' 'server.sh')
    }

    It 'offers the fixed targets of <line>' -ForEach @(
        @{ line = 'claude install '; expected = 'stable', 'latest' }
        @{ line = 'claude import '; expected = 'codex', 'gemini', 'cursor' }
    ) {
        Get-CompletionText $line | Should -Be $expected
    }

    It 'offers the flags where a positional takes free text' {
        Get-CompletionText 'claude mcp add ' | Should -Contain '--transport'
    }
}

Describe 'plugin eval' {
    It 'offers init and paths as the first word' {
        $texts = Get-CompletionText 'claude plugin eval '
        $texts | Should -Contain 'init'
        $texts | Should -Contain (Join-Path '.' 'alpha-dir')
    }

    It 'offers the eval flags for <line>' -ForEach @(
        @{ line = 'claude plugin eval --' }
        @{ line = 'claude plugin eval alpha-dir --' }
        # `init` is the value of --case here, not the command.
        @{ line = 'claude plugin eval --case init --' }
        # A target came first, so `init` is not the command either.
        @{ line = 'claude plugin eval alpha-dir init --' }
        # --tag and --allow-tools take every word up to the next option.
        @{ line = 'claude plugin eval --tag init --' }
        @{ line = 'claude plugin eval --allow-tools Bash init --' }
        @{ line = 'claude plugin eval --model init --' }
    ) {
        $texts = Get-CompletionText $line
        $texts | Should -Contain '--ablation'
        $texts | Should -Not -Contain '--bare'
    }

    It 'offers the init flags for <line>' -ForEach @(
        @{ line = 'claude plugin eval init --' }
        @{ line = 'claude plugin eval --verbose init --' }
        # --json takes a value only when one follows.
        @{ line = 'claude plugin eval --json result.json init --' }
        @{ line = 'claude plugin eval --tag smoke --verbose init --' }
    ) {
        $texts = Get-CompletionText $line
        $texts | Should -Contain '--bare'
        $texts | Should -Not -Contain '--ablation'
    }
}

Describe 'self-hosted-runner' {
    It 'offers only its subcommands as the first word' {
        $texts = Get-CompletionText 'claude self-hosted-runner '
        $texts | Should -Not -Contain '--capacity'
        $texts | Should -Not -Contain 'setup-token'
    }

    It 'offers the runner flags, not the orchestrator ones' {
        $texts = Get-CompletionText 'claude self-hosted-runner --'
        foreach ($flag in '--api-url', '--capacity', '--base-dir', '--git-ssh-rewrite', '--trust-workspace', '--retire-at') {
            $texts | Should -Contain $flag
        }
        foreach ($flag in '--hook-concurrency', '--min-idle', '--scm-connector-host') { $texts | Should -Not -Contain $flag }
    }

    It 'offers the orchestrator flags, not the runner ones' {
        $texts = Get-CompletionText 'claude self-hosted-runner orchestrator --'
        foreach ($flag in '--api-url', '--hooks-dir', '--hook-concurrency', '--hook-timeout', '--min-idle') {
            $texts | Should -Contain $flag
        }
        foreach ($flag in '--capacity', '--base-dir', '--trust-workspace', '--retire-at') { $texts | Should -Not -Contain $flag }
    }

    It 'keeps offering runner flags after another flag, and no subcommands' {
        $texts = Get-CompletionText 'claude self-hosted-runner --capacity 2 --'
        $texts | Should -Contain '--base-dir'
        $texts | Should -Not -Contain '--hook-concurrency'
        Get-CompletionText 'claude self-hosted-runner --capacity 2 ' | Should -Not -Contain 'setup'
        # `setup` is not the first word, so the runner flags still apply.
        Get-CompletionText 'claude self-hosted-runner --capacity 2 setup --' | Should -Contain '--base-dir'
    }

    It 'offers only help for setup' {
        Get-CompletionText 'claude self-hosted-runner setup -' | Should -Be '-h', '--help'
    }
}
