# Plugin and marketplace values. Counterpart of test-plugin-values.sh.
# Everything is read from a fake <home>/.claude/plugins. The fixtures mix in
# the older installed_plugins.json format and several malformed entries,
# which must not hide the valid ones.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:fakeHome = New-Directory (Join-Path $TestDrive 'home')
    $script:work = New-Directory (Join-Path $fakeHome 'work')
    [void](New-Directory (Join-Path $work 'some-dir'))
    $script:proj = New-Directory (Join-Path $fakeHome 'proj')
    [void](New-Directory (Join-Path $proj '.git'))
    $script:projSub = New-Directory (Join-Path $proj 'sub')

    # -Tag is appended to every plugin and marketplace name, to tell a second
    # config directory apart.
    function Set-PluginFixture {
        param([string]$PluginsDir, [string]$Tag = '')
        $here = (Resolve-RealPath $proj) | ConvertTo-Json
        $another = (Join-Path (Resolve-RealPath $fakeHome) 'another-project') | ConvertTo-Json
        Set-TextFile (Join-Path $PluginsDir 'installed_plugins.json') @"
{
  "version": 2,
  "plugins": {
    "alpha$Tag@one-market": [{ "scope": "user", "version": "1.2.3" }],
    "oops$Tag@one-market": ["not an install"],
    "beta$Tag@two-market": [{ "scope": "project", "version": "0.9.0" }],
    "worse$Tag@one-market": "just a string",
    "legacy$Tag@one-market": { "version": "0.1.0" },
    "here$Tag@two-market": [{ "scope": "project", "projectPath": $here, "version": "2.0.0" }],
    "elsewhere$Tag@two-market": [{ "scope": "local", "projectPath": $another, "version": "3.0.0" }]
  }
}
"@
        Set-TextFile (Join-Path $PluginsDir 'known_marketplaces.json') @"
{
  "one-market$Tag": { "source": { "source": "github", "repo": "org/one" } },
  "bad-market$Tag": "just a string",
  "two-market$Tag": { "source": { "source": "git", "url": "https://example.com/two.git?token=SECRETVALUE" } },
  "odd-market$Tag": { "source": "not an object" }
}
"@
        Set-TextFile (Join-Path $PluginsDir 'marketplaces' 'one-market' '.claude-plugin' 'marketplace.json') @"
{
  "name": "one-market",
  "plugins": [
    { "name": "alpha$Tag", "description": "Alpha plugin text" },
    "junk entry",
    { "description": "entry without a name" },
    { "name": "gamma$Tag", "description": ["not", "a", "string"] }
  ]
}
"@
        Set-TextFile (Join-Path $PluginsDir 'marketplaces' 'two-market' '.claude-plugin' 'marketplace.json') @"
{ "plugins": [{ "name": "beta$Tag", "description": "Beta plugin text" }] }
"@
    }

    $script:plugins = Join-Path $fakeHome '.claude' 'plugins'
    Set-PluginFixture $plugins
}

Describe 'installed plugins' {
    It 'lists them, including the older single-object format' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
            Get-CompletionText 'claude plugin enable ' | Should -Be 'alpha@one-market', 'beta@two-market', 'legacy@one-market'
        }
    }

    It 'describes each with its version and scope' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
            $tips = Get-CompletionTip 'claude plugin enable '
            $tips['alpha@one-market'] | Should -Be '1.2.3 (user scope)'
            $tips['beta@two-market'] | Should -Be '0.9.0 (project scope)'
            $tips['legacy@one-market'] | Should -Be '0.1.0 (user scope)'
        }
    }

    It 'offers a project-scope install only inside its project' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $projSub {
            $texts = Get-CompletionText 'claude plugin enable '
            $texts | Should -Contain 'here@two-market'
            $texts | Should -Contain 'alpha@one-market'
            $texts | Should -Not -Contain 'elsewhere@two-market'
        }
    }

    It 'is offered by claude <_>' -ForEach @(
        'plugin configure', 'plugin details', 'plugin enable', 'plugin disable', 'plugin uninstall', 'plugin remove',
        'plugin update', 'plugins enable', 'plugin list --data-size'
    ) {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
            $texts = Get-CompletionText "claude $_ "
            $texts | Should -Contain 'alpha@one-market'
            $texts | Should -Contain 'beta@two-market'
        }
    }

    It 'filters by what is typed' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
            Get-CompletionText 'claude plugin enable --scope user be' | Should -Be 'beta@two-market'
        }
    }

    It 'is offered next to init and paths as a plugin eval target' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
            $texts = Get-CompletionText 'claude plugin eval '
            $texts | Should -Contain 'init'
            $texts | Should -Contain 'alpha@one-market'
            $texts | Should -Contain (Join-Path '.' 'some-dir')
        }
    }
}

Describe 'installable plugins' {
    It 'lists the plugins of every cached marketplace manifest' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
            # A description that is not a string must not drop the plugin.
            Get-CompletionText 'claude plugin install ' | Should -Be 'alpha@one-market', 'gamma@one-market', 'beta@two-market'
            $tips = Get-CompletionTip 'claude plugin install '
            $tips['alpha@one-market'] | Should -Be 'Alpha plugin text'
            $tips['gamma@one-market'] | Should -Be 'gamma@one-market'
            Get-CompletionText 'claude plugin i b' | Should -Be 'beta@two-market'
        }
    }

    It 'skips a manifest that is not valid JSON' {
        $broken = Join-Path $plugins 'marketplaces' 'broken-market' '.claude-plugin' 'marketplace.json'
        Set-TextFile $broken '{ "plugins": [ { "name": "lost"'
        try {
            Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
                $Error.Clear()
                Get-CompletionText 'claude plugin install ' | Should -Be 'alpha@one-market', 'gamma@one-market', 'beta@two-market'
                $Error.Count | Should -Be 0
            }
        }
        finally { Remove-Item -Recurse -Force (Join-Path $plugins 'marketplaces' 'broken-market') }
    }

    It 'cuts a long description' {
        $long = Join-Path $plugins 'marketplaces' 'long-market' '.claude-plugin' 'marketplace.json'
        Set-TextFile $long (@{ plugins = @(@{ name = 'wordy'; description = "first line`nsecond " + ('z' * 200) }) } | ConvertTo-Json -Depth 4)
        try {
            Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
                $tip = (Get-Completion 'claude plugin install wordy').ToolTip
                $tip.Length | Should -Be 80
                $tip | Should -BeLike 'first line second zzz*...'
            }
        }
        finally { Remove-Item -Recurse -Force (Join-Path $plugins 'marketplaces' 'long-market') }
    }
}

Describe 'marketplaces' {
    It 'lists them for marketplace <_>' -ForEach 'remove', 'rm', 'update' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
            # odd-market has a malformed source, but the marketplace itself is known.
            Get-CompletionText "claude plugin marketplace $_ " | Should -Be 'one-market', 'two-market', 'odd-market'
        }
    }

    It 'describes each with its source, without the query string of a URL' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
            $tips = Get-CompletionTip 'claude plugin marketplace remove '
            $tips['one-market'] | Should -Be 'org/one'
            $tips['two-market'] | Should -Be 'https://example.com/two.git'
            $tips['odd-market'] | Should -Be 'odd-market'
        }
    }
}

Describe 'where the plugin files are read from' {
    BeforeAll {
        $script:alt = New-Directory (Join-Path $TestDrive 'altconfig')
        Set-PluginFixture (Join-Path $alt 'plugins') -Tag '-alt'
        $script:cache = New-Directory (Join-Path $TestDrive 'plugin-cache')
        Set-PluginFixture $cache -Tag '-cache'
    }

    It 'follows CLAUDE_CONFIG_DIR' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -ConfigDir $alt -Cwd $work {
            $installed = Get-CompletionText 'claude plugin enable '
            $installed | Should -Contain 'alpha-alt@one-market'
            $installed | Should -Not -Contain 'alpha@one-market'
            Get-CompletionText 'claude plugin install ' | Should -Contain 'beta-alt@two-market'
            Get-CompletionText 'claude plugin marketplace update ' | Should -Contain 'one-market-alt'
        }
    }

    It 'follows CLAUDE_CODE_PLUGIN_CACHE_DIR, which wins over CLAUDE_CONFIG_DIR' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -ConfigDir $alt -Cwd $work -Environment @{ CLAUDE_CODE_PLUGIN_CACHE_DIR = $cache } {
            Get-CompletionText 'claude plugin enable ' | Should -Contain 'alpha-cache@one-market'
            Get-CompletionText 'claude plugin enable ' | Should -Not -Contain 'alpha-alt@one-market'
            Get-CompletionText 'claude plugin install ' | Should -Contain 'beta-cache@two-market'
            Get-CompletionText 'claude plugin marketplace update ' | Should -Contain 'one-market-cache'
        }
    }

    It 'offers nothing, and no error, when <case>' -ForEach @(
        @{ case = 'the plugins directory is missing'; text = $null }
        @{ case = 'the files are empty'; text = '' }
        @{ case = 'the files are not JSON'; text = '{ "plugins": ' }
        @{ case = 'the files hold other JSON'; text = '[1, "two", null]' }
        @{ case = 'plugins is not an object'; text = '{ "plugins": "none" }' }
    ) {
        $empty = Join-Path $TestDrive 'empty-config'
        if (Test-Path $empty) { Remove-Item -Recurse -Force $empty }
        [void](New-Directory $empty)
        if ($null -ne $text) {
            Set-TextFile (Join-Path $empty 'plugins' 'installed_plugins.json') $text
            Set-TextFile (Join-Path $empty 'plugins' 'known_marketplaces.json') $text
            Set-TextFile (Join-Path $empty 'plugins' 'marketplaces' 'm' '.claude-plugin' 'marketplace.json') $text
        }
        Use-ClaudeEnvironment -HomeDir $fakeHome -ConfigDir $empty -Cwd $work {
            $Error.Clear()
            foreach ($line in 'claude plugin enable x', 'claude plugin install x', 'claude plugin marketplace remove x', 'claude plugin list --data-size x') {
                Get-CompletionText $line | Should -BeNullOrEmpty
            }
            $Error.Count | Should -Be 0
        }
    }
}
