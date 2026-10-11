# Agent names for `--agent`: the user's and the project's `.claude/agents/`.
# Counterpart of test-agent-names.sh.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    # Raw bytes: the fixtures need CRLF, a byte-order mark and binary content.
    function Set-AgentFile {
        param([string]$Path, [string]$Text, [byte[]]$Prefix = @())
        [void](New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path))
        [IO.File]::WriteAllBytes($Path, [byte[]]($Prefix + [Text.UTF8Encoding]::new($false).GetBytes($Text)))
    }

    $script:fakeHome = New-Directory (Join-Path $TestDrive 'home')
    $script:userAgents = Join-Path $fakeHome '.claude' 'agents'
    $script:proj = New-Directory (Join-Path $fakeHome 'proj')
    [void](New-Directory (Join-Path $proj '.git'))
    $script:deeper = New-Directory (Join-Path $proj 'sub' 'deeper')
    $script:outside = New-Directory (Join-Path $TestDrive 'outside')

    # --- user agents ---
    Set-AgentFile (Join-Path $userAgents 'user-simple.md') "---`nname: user-simple`ndescription: Plain user agent`n---`nbody`n"
    # In a subfolder, and the file name differs from the agent name.
    Set-AgentFile (Join-Path $userAgents 'review' 'some-file.md') "---`nname: nested-reviewer`ndescription: Lives in a subfolder`n---`n"
    Set-AgentFile (Join-Path $userAgents 'commented.md') "---`nname: commented # not part of the name`ndescription: Has a comment # also dropped`n---`n"
    Set-AgentFile (Join-Path $userAgents 'tabbed.md') "---`nname: tabbed`t`ndescription: Trailing tab`n---`n"
    Set-AgentFile (Join-Path $userAgents 'quoted.md') "---`nname: `"quoted-name`"`ndescription: 'Single quoted text'`n---`n"
    Set-AgentFile (Join-Path $userAgents 'crlf.md') "---`r`nname: crlf-agent`r`ndescription: Windows line endings`r`n---`r`n"
    Set-AgentFile (Join-Path $userAgents 'bom.md') "---`nname: bom-agent`ndescription: Starts with a byte-order mark`n---`n" -Prefix 0xEF, 0xBB, 0xBF
    Set-AgentFile (Join-Path $userAgents 'block.md') "---`nname: block-agent`ndescription: |`n  First line of the block`n  second line`n---`n"
    Set-AgentFile (Join-Path $userAgents 'escaped.md') "---`nname: escaped-agent`ndescription: Use this agent when asked.\n\nExamples:\n<example>one</example>`n---`n"
    Set-AgentFile (Join-Path $userAgents 'long.md') "---`nname: long-agent`ndescription: $('w' * 200)`n---`n"
    Set-AgentFile (Join-Path $userAgents 'no-description.md') "---`nname: bare-agent`n---`n"
    Set-AgentFile (Join-Path $userAgents 'control.md') "---`nname: control-agent`ndescription: Has an $([char]27)[31mescape$([char]7) in it`n---`n"
    # --- files that must be skipped ---
    Set-AgentFile (Join-Path $userAgents 'plain.md') "no frontmatter here`nname: no-frontmatter`n"
    Set-AgentFile (Join-Path $userAgents 'colon.md') "---`nname: scoped:name`ndescription: Colon is reserved`n---`n"
    Set-AgentFile (Join-Path $userAgents 'nameless.md') "---`ndescription: Has no name`n---`n"
    Set-AgentFile (Join-Path $userAgents 'empty.md') ''
    Set-AgentFile (Join-Path $userAgents 'binary.md') " binary`n" -Prefix 0x00, 0x01, 0x02, 0xFF, 0xFE
    Set-AgentFile (Join-Path $userAgents 'after-end.md') "---`ndescription: Name comes too late`n---`nname: after-end`n"
    Set-AgentFile (Join-Path $userAgents 'notes.txt') "---`nname: not-markdown`n---`n"
    # --- project agents ---
    Set-AgentFile (Join-Path $proj '.claude' 'agents' 'proj-agent.md') "---`nname: proj-agent`ndescription: Project level agent`n---`n"
    Set-AgentFile (Join-Path $proj '.claude' 'agents' 'team' 'member.md') "---`nname: team-agent`ndescription: Project agent in a subfolder`n---`n"
    Set-AgentFile (Join-Path $proj '.claude' 'agents' 'shared.md') "---`nname: shared-name`ndescription: Farther definition`n---`n"
    Set-AgentFile (Join-Path $proj 'sub' '.claude' 'agents' 'shared.md') "---`nname: shared-name`ndescription: Closest definition`n---`n"

    # Only the agents these fixtures define. Plugin agents are scoped with
    # `:`; the built-in ones are covered by PluginAgents.Tests.ps1.
    function Get-OwnAgent {
        param([string]$Line = 'claude --agent ')
        $builtIn = 'general-purpose', 'statusline-setup', 'claude', 'Explore', 'Plan', 'claude-code-guide'
        $tips = Get-CompletionTip $Line
        foreach ($name in @($tips.Keys)) { if ($name -in $builtIn) { $tips.Remove($name) } }
        $tips
    }
}

Describe 'agent names' {
    It 'offers user and project agents, from a project subdirectory' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $deeper {
            $names = (Get-OwnAgent).Keys
            foreach ($name in 'user-simple', 'nested-reviewer', 'commented', 'tabbed', 'quoted-name', 'crlf-agent', 'bom-agent',
                'block-agent', 'proj-agent', 'team-agent', 'shared-name') {
                $names | Should -Contain $name
            }
        }
    }

    It 'lists the closest project agents first, then the user agents' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $deeper {
            $texts = Get-CompletionText 'claude --agent '
            $texts[0..3] | Should -Be 'shared-name', 'proj-agent', 'team-agent', 'block-agent'
        }
    }

    It 'takes clean names and descriptions from the frontmatter' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $deeper {
            $tips = Get-OwnAgent
            $tips['user-simple'] | Should -Be 'Plain user agent'
            # The agent is named by its frontmatter, not by its file.
            $tips.Keys | Should -Not -Contain 'some-file'
            $tips['nested-reviewer'] | Should -Be 'Lives in a subfolder'
            $tips['commented'] | Should -Be 'Has a comment'
            $tips['tabbed'] | Should -Be 'Trailing tab'
            $tips['quoted-name'] | Should -Be 'Single quoted text'
            $tips['crlf-agent'] | Should -Be 'Windows line endings'
            $tips['bom-agent'] | Should -Be 'Starts with a byte-order mark'
            # `description: |` shows the text, not the `|`.
            $tips['block-agent'] | Should -Be 'First line of the block'
            $tips['escaped-agent'] | Should -Be 'Use this agent when asked.'
            $tips['long-agent'] | Should -Be (('w' * 77) + '...')
            $tips['bare-agent'] | Should -Be 'bare-agent'
            $tips['control-agent'] | Should -Be 'Has an [31mescape in it'
        }
    }

    It 'lets the definition closest to the working directory win' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $deeper {
            (Get-OwnAgent)['shared-name'] | Should -Be 'Closest definition'
        }
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            (Get-OwnAgent)['shared-name'] | Should -Be 'Farther definition'
        }
    }

    It 'skips malformed files without hiding the valid ones' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $deeper {
            $Error.Clear()
            $names = (Get-OwnAgent).Keys
            foreach ($bad in 'no-frontmatter', 'scoped:name', 'scoped', 'nameless', 'empty', 'binary', 'after-end', 'not-markdown') {
                $names | Should -Not -Contain $bad
            }
            $Error.Count | Should -Be 0
        }
    }

    It 'completes a name exactly, without its trailing whitespace or comment' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            Get-CompletionText 'claude --agent tabb' | Should -Be 'tabbed'
            Get-CompletionText 'claude --agent comm' | Should -Be 'commented'
        }
    }

    It 'uses the same list for claude agents --agent' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $names = (Get-OwnAgent 'claude agents --agent ').Keys
            $names | Should -Contain 'proj-agent'
            $names | Should -Contain 'user-simple'
        }
    }

    It 'offers only user agents outside the project' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $outside {
            $names = (Get-OwnAgent).Keys
            $names | Should -Contain 'user-simple'
            $names | Should -Not -Contain 'proj-agent'
            $names | Should -Not -Contain 'shared-name'
        }
    }

    It 'reads the user agents from CLAUDE_CONFIG_DIR when it is set' {
        $alt = New-Directory (Join-Path $TestDrive 'altconfig')
        Set-AgentFile (Join-Path $alt 'agents' 'alt.md') "---`nname: alt-agent`ndescription: From the other config directory`n---`n"
        Use-ClaudeEnvironment -HomeDir $fakeHome -ConfigDir $alt -Cwd $outside {
            (Get-OwnAgent).Keys | Should -Be 'alt-agent'
        }
    }

    It 'offers no agents of its own, and no error, without any agents directory' {
        Use-ClaudeEnvironment -HomeDir (New-Directory (Join-Path $TestDrive 'empty-home')) -Cwd $outside {
            $Error.Clear()
            (Get-OwnAgent).Count | Should -Be 0
            $Error.Count | Should -Be 0
        }
    }

    It 'picks up an agent file changed after it was first listed' {
        $dir = New-Directory (Join-Path $TestDrive 'changing')
        $file = Join-Path $dir '.claude' 'agents' 'a.md'
        Set-AgentFile $file "---`nname: first-name`n---`n"
        Use-ClaudeEnvironment -HomeDir (New-Directory (Join-Path $TestDrive 'empty-home')) -Cwd $dir {
            (Get-OwnAgent).Keys | Should -Be 'first-name'
            Set-AgentFile $file "---`nname: second-name-is-longer`n---`n"
            (Get-OwnAgent).Keys | Should -Be 'second-name-is-longer'
        }
    }
}
