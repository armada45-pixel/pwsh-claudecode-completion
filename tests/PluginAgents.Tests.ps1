# The built-in and plugin agents `--agent` offers next to the user's own
# (see Agents.Tests.ps1 for those). Counterpart of test-agent-names-plugins.sh.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    # Without -Name the file has no frontmatter.
    function Set-Agent {
        param([string]$Path, [string]$Name, [string]$Description)
        if ($Name) { Set-TextFile $Path "---`nname: $Name`ndescription: $Description`n---`nbody`n" }
        else { Set-TextFile $Path "Just a prompt.`n" }
    }

    $script:fakeHome = New-Directory (Join-Path $TestDrive 'home')
    $script:plug = New-Directory (Join-Path $fakeHome 'plug')
    $script:proj = New-Directory (Join-Path $fakeHome 'proj')
    [void](New-Directory (Join-Path $proj '.git'))
    $script:elsewhere = New-Directory (Join-Path $fakeHome 'elsewhere')

    # --- plugins ---
    Set-Agent (Join-Path $plug 'alpha' 'agents' 'top.md') 'top-agent' 'Top level plugin agent'
    Set-Agent (Join-Path $plug 'alpha' 'agents' 'review' 'security.md') 'audit' 'Agent in a subfolder'
    Set-Agent (Join-Path $plug 'alpha' 'agents' 'bare-file.md')
    # The manifest renames the plugin and lists its agents; agents/ is ignored.
    Set-Agent (Join-Path $plug 'renamed' 'custom' 'deep' 'lister.md') 'listed-agent' 'Named by the manifest'
    Set-Agent (Join-Path $plug 'renamed' 'agents' 'ignored.md') 'ignored-agent' 'Default folder is replaced'
    Set-TextFile (Join-Path $plug 'renamed' '.claude-plugin' 'plugin.json') '{"name": "zeta-tools", "agents": ["./custom/deep/lister.md", "./../escape.md", "custom/bare.md", 7]}'
    # Both files exist, so only the path rules keep them out: a path stays
    # inside the plugin and starts with `./`.
    Set-Agent (Join-Path $plug 'escape.md') 'escape-agent' 'Outside the plugin root'
    Set-Agent (Join-Path $plug 'renamed' 'custom' 'bare.md') 'prefixless-agent' 'Path without ./'
    Set-Agent (Join-Path $plug 'single' 'only.md') 'single-agent' 'Listed as one string'
    Set-TextFile (Join-Path $plug 'single' '.claude-plugin' 'plugin.json') '{"agents": "./only.md"}'
    Set-Agent (Join-Path $plug 'off' 'agents' 'hidden.md') 'hidden-agent' 'Plugin is disabled'
    Set-Agent (Join-Path $plug 'dflt' 'agents' 'sleeper.md') 'sleeper-agent' 'Off by default'
    Set-TextFile (Join-Path $plug 'dflt' '.claude-plugin' 'plugin.json') '{"name": "dflt", "defaultEnabled": false}'
    Set-Agent (Join-Path $plug 'woken' 'agents' 'riser.md') 'riser-agent' 'Off by default, enabled by the user'
    Set-TextFile (Join-Path $plug 'woken' '.claude-plugin' 'plugin.json') '{"defaultEnabled": false}'
    Set-Agent (Join-Path $plug 'badmanifest' 'agents' 'survivor.md') 'survivor-agent' 'Manifest is not JSON'
    Set-TextFile (Join-Path $plug 'badmanifest' '.claude-plugin' 'plugin.json') '{ not json'
    Set-Agent (Join-Path $plug 'relit' 'agents' 'back.md') 'back-agent' 'Enabled again by the project'
    Set-Agent (Join-Path $plug 'muted' 'agents' 'quiet.md') 'quiet-agent' 'Disabled by the project'
    Set-Agent (Join-Path $plug 'projonly' 'agents' 'local.md') 'local-agent' 'Project scoped install'
    Set-Agent (Join-Path $plug 'other' 'agents' 'alt.md') 'alt-agent' 'From the alternate config dir'

    function Get-InstallPath { param([string]$Name) (Join-Path $plug $Name) | ConvertTo-Json }
    Set-TextFile (Join-Path $fakeHome '.claude' 'plugins' 'installed_plugins.json') @"
{
  "version": 2,
  "plugins": {
    "alpha@market": [{"scope": "user", "installPath": $(Get-InstallPath alpha)}],
    "renamed@market": [{"scope": "user", "installPath": $(Get-InstallPath renamed)}],
    "single@market": {"installPath": $(Get-InstallPath single)},
    "off@market": [{"scope": "user", "installPath": $(Get-InstallPath off)}],
    "dflt@market": [{"scope": "user", "installPath": $(Get-InstallPath dflt)}],
    "woken@market": [{"scope": "user", "installPath": $(Get-InstallPath woken)}],
    "badmanifest@market": [{"scope": "user", "installPath": $(Get-InstallPath badmanifest)}],
    "relit@market": [{"scope": "user", "installPath": $(Get-InstallPath relit)}],
    "muted@market": [{"scope": "user", "installPath": $(Get-InstallPath muted)}],
    "projonly@market": [{"scope": "project", "projectPath": $((Resolve-RealPath $proj) | ConvertTo-Json), "installPath": $(Get-InstallPath projonly)}],
    "gone@market": [{"scope": "user", "installPath": $(Get-InstallPath does-not-exist)}],
    "nopath@market": [{"scope": "user"}],
    "wrongtype@market": "not a list",
    "numbers@market": [42, null]
  }
}
"@
    Set-TextFile (Join-Path $fakeHome '.claude' 'settings.json') '{"enabledPlugins": {"off@market": false, "alpha@market": true, "relit@market": false, "woken@market": true}}'
    # The project's settings turn one plugin back on and another one off.
    Set-TextFile (Join-Path $proj '.claude' 'settings.json') '{"enabledPlugins": {"relit@market": true, "muted@market": false}}'
    # A settings file that is not JSON must not take the plugins with it.
    Set-TextFile (Join-Path $proj '.claude' 'settings.local.json') 'not json at all'

    # --- user agents ---
    # Same unscoped name as a plugin agent, and same name as a built-in.
    Set-Agent (Join-Path $fakeHome '.claude' 'agents' 'top.md') 'top-agent' 'User agent of that name'
    Set-Agent (Join-Path $fakeHome '.claude' 'agents' 'explore.md') 'Explore' 'User replacement for Explore'

    $script:altConfig = New-Directory (Join-Path $fakeHome 'altconfig')
    Set-TextFile (Join-Path $altConfig 'plugins' 'installed_plugins.json') "{`"plugins`": {`"other@market`": [{`"scope`": `"user`", `"installPath`": $(Get-InstallPath other)}]}}"
}

Describe 'plugin agents' {
    It 'offers them scoped by plugin and subfolder, from inside the project' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $tips = Get-CompletionTip 'claude --agent '
            foreach ($name in 'alpha:top-agent', 'alpha:review:audit', 'alpha:bare-file', 'zeta-tools:listed-agent', 'single:single-agent',
                'badmanifest:survivor-agent', 'projonly:local-agent', 'relit:back-agent', 'woken:riser-agent') {
                $tips.Keys | Should -Contain $name
            }
            $tips['alpha:review:audit'] | Should -Be 'Agent in a subfolder'
            # No frontmatter: named by its file, with Claude's own description.
            $tips['alpha:bare-file'] | Should -Be 'Agent from alpha plugin'
            $tips['zeta-tools:listed-agent'] | Should -Be 'Named by the manifest'
        }
    }

    It 'leaves out <_>' -ForEach @(
        'hidden-agent', 'sleeper-agent', 'ignored-agent', 'renamed:', 'escape', 'prefixless', 'quiet-agent',
        'gone:', 'nopath:', 'wrongtype:', 'numbers:'
    ) {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            (Get-CompletionText 'claude --agent ') -join "`n" | Should -Not -Match ([regex]::Escape($_))
        }
    }

    It 'keeps the unscoped name for the user agent' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $tips = Get-CompletionTip 'claude --agent '
            $tips['top-agent'] | Should -Be 'User agent of that name'
            $tips['alpha:top-agent'] | Should -Be 'Top level plugin agent'
        }
    }

    It 'completes a scoped name with its colons, unquoted' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            Get-CompletionText 'claude --agent alpha:rev' | Should -Be 'alpha:review:audit'
            Get-CompletionText 'claude --agent alpha:' | Should -Be 'alpha:bare-file', 'alpha:review:audit', 'alpha:top-agent'
        }
    }

    It 'uses the same list for claude agents --agent' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $texts = Get-CompletionText 'claude agents --agent '
            $texts | Should -Contain 'alpha:review:audit'
            $texts | Should -Contain 'general-purpose'
        }
    }

    It 'keeps a project-scoped plugin and the project settings inside the project' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $elsewhere {
            $texts = Get-CompletionText 'claude --agent '
            $texts | Should -Contain 'alpha:top-agent'
            $texts | Should -Not -Contain 'projonly:local-agent'
            # The project's settings do not apply here, only the user's.
            $texts | Should -Contain 'muted:quiet-agent'
            $texts | Should -Not -Contain 'relit:back-agent'
        }
    }

    It 'follows CLAUDE_CONFIG_DIR' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -ConfigDir $altConfig -Cwd $elsewhere {
            $tips = Get-CompletionTip 'claude --agent '
            $tips['other:alt-agent'] | Should -Be 'From the alternate config dir'
            $tips.Keys -join ' ' | Should -Not -Match 'alpha'
            # No user agent replaces Explore here.
            $tips['Explore'] | Should -Be 'Fast, read-only agent for searching and analyzing codebases'
        }
    }

    It 'follows CLAUDE_CODE_PLUGIN_CACHE_DIR' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $elsewhere -Environment @{ CLAUDE_CODE_PLUGIN_CACHE_DIR = (Join-Path $altConfig 'plugins') } {
            $texts = Get-CompletionText 'claude --agent '
            $texts | Should -Contain 'other:alt-agent'
            $texts -join ' ' | Should -Not -Match 'alpha'
        }
    }

    It 'keeps the other agents when installed_plugins.json is unreadable' {
        $broken = New-Directory (Join-Path $fakeHome 'brokenconfig')
        Set-TextFile (Join-Path $broken 'plugins' 'installed_plugins.json') '{"plugins": ['
        Set-Agent (Join-Path $broken 'agents' 'mine.md') 'still-here' 'User agent'
        Use-ClaudeEnvironment -HomeDir $fakeHome -ConfigDir $broken -Cwd $elsewhere {
            $Error.Clear()
            $texts = Get-CompletionText 'claude --agent '
            $texts | Should -Contain 'still-here'
            $texts | Should -Contain 'general-purpose'
            $Error.Count | Should -Be 0
        }
    }
}

Describe 'built-in agents' {
    It 'offers them after the user, project and plugin agents' {
        Use-ClaudeEnvironment -HomeDir (New-Directory (Join-Path $TestDrive 'empty-home')) -Cwd $elsewhere {
            Get-CompletionText 'claude --agent ' | Should -Be 'general-purpose', 'statusline-setup', 'claude', 'Explore', 'Plan', 'claude-code-guide'
            (Get-CompletionTip 'claude --agent ')['claude'] | Should -Be 'Catch-all with every tool available to subagents'
        }
    }

    It 'lists a built-in once when a user agent replaces it' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $found = @(Get-Completion 'claude --agent ' | Where-Object CompletionText -EQ 'Explore')
            $found.Count | Should -Be 1
            $found[0].ToolTip | Should -Be 'User replacement for Explore'
        }
    }

    It 'matches without regard to case' {
        Use-ClaudeEnvironment -HomeDir (New-Directory (Join-Path $TestDrive 'empty-home')) -Cwd $elsewhere {
            Get-CompletionText 'claude --agent exp' | Should -Be 'Explore'
            Get-CompletionText 'claude --agent claude' | Should -Be 'claude', 'claude-code-guide'
        }
    }
}
