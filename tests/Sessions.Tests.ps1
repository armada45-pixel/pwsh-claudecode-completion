# Session ids for `claude --resume` / `-r`. Counterpart of test-session-ids.sh.
# Each case builds a fake config directory with a projects/<folder>/ tree.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    # One session file: records as compact JSON lines, and a modification time.
    function New-Session {
        param([string]$ProjectDir, [string]$Id, [object[]]$Records, [datetime]$Modified)
        $lines = foreach ($record in $Records) { if ($record -is [string]) { $record } else { $record | ConvertTo-Json -Compress -Depth 8 } }
        $path = Join-Path $ProjectDir "$Id.jsonl"
        Set-TextFile $path (($lines -join "`n") + "`n")
        if ($Modified) { (Get-Item -LiteralPath $path).LastWriteTimeUtc = $Modified }
        $path
    }

    function New-Prompt {
        param([string]$Text, [string]$Branch = 'main')
        @{ type = 'user'; gitBranch = $Branch; message = @{ content = $Text } }
    }

    # The fixture of test-session-ids.sh.
    #   -Fallback puts the sessions in a folder of another name, to be found
    #   through `originalPath` in sessions-index.json.
    function New-SessionFixture {
        param([string]$ConfigDir, [string]$WorkDir, [switch]$Fallback)
        $recorded = Resolve-RealPath (New-Directory $WorkDir)
        $folder = if ($Fallback) { '-some-other-name' } else { ConvertTo-ProjectFolder $recorded }
        $dir = New-Directory (Join-Path $ConfigDir 'projects' $folder)
        $day = [datetime]::new(2026, 5, 9, 12, 0, 0, [DateTimeKind]::Utc)

        # In the index, and the newest. Its own prompt is hidden by the index summary.
        [void](New-Session $dir 'aaaaaaaa-1111-2222-3333-aaaaaaaaaaaa' @(New-Prompt 'indexed jsonl prompt (should be hidden by summary)') $day)
        Set-TextFile (Join-Path $dir 'sessions-index.json') (@{
                originalPath = $recorded
                entries      = @(@{ sessionId = 'aaaaaaaa-1111-2222-3333-aaaaaaaaaaaa'; gitBranch = 'main'; summary = 'indexed session label' })
            } | ConvertTo-Json -Depth 5)
        # /rename title: outranks the generated title and the prompt.
        [void](New-Session $dir 'eeeeeeee-1111-2222-3333-eeeeeeeeeeee' @(
                (New-Prompt 'some prompt')
                @{ type = 'ai-title'; aiTitle = 'auto-generated-title' }
                @{ type = 'custom-title'; customTitle = 'my-renamed-session' }
            ) $day.AddHours(-23))
        # Generated title: outranks the prompt.
        [void](New-Session $dir 'dddddddd-1111-2222-3333-dddddddddddd' @(
                (New-Prompt 'hello there')
                @{ type = 'ai-title'; aiTitle = 'refactor-auth-flow' }
            ) $day.AddHours(-25))
        # Not in the index: labelled by its first prompt.
        [void](New-Session $dir 'bbbbbbbb-1111-2222-3333-bbbbbbbbbbbb' @(New-Prompt 'jsonl session prompt' 'feature') $day.AddHours(-26))
        # Only a slash command: labelled by the command.
        [void](New-Session $dir 'ffffffff-1111-2222-3333-ffffffffffff' @(New-Prompt "<command-name>/exit</command-name>`n<command-message>exit</command-message>") $day.AddHours(-27))
        # Only command output: nothing to resume, so it is left out.
        [void](New-Session $dir 'cccccccc-1111-2222-3333-cccccccccccc' @(New-Prompt '<command-stdout>boring</command-stdout>') $day.AddDays(-2))
        $dir
    }

    $script:config = Join-Path $TestDrive 'config'
}

Describe 'session ids' {
    BeforeEach {
        if (Test-Path $config) { Remove-Item -Recurse -Force $config }
        [void](New-Directory $config)
    }

    Context 'project folder name' {
        It 'replaces every character other than a-z, A-Z and 0-9: <path>' -ForEach @(
            @{ path = 'C:\Users\me\repo'; folder = 'C--Users-me-repo' }
            @{ path = 'C:\'; folder = 'C--' }
            @{ path = 'D:\web\my project_x\v1.2'; folder = 'D--web-my-project-x-v1-2' }
            @{ path = '/home/me/.config/repo'; folder = '-home-me--config-repo' }
            @{ path = '/home/me/üñí'; folder = '-home-me----' }
            # Beyond U+FFFF: two UTF-16 code units, so two hyphens.
            @{ path = "/home/me/emoji$([char]::ConvertFromUtf32(0x1F4A9))/work"; folder = '-home-me-emoji---work' }
        ) {
            & (Get-Module pwsh-claudecode-completion) { param($p) ConvertTo-ClaudeProjectFolder $p } $path | Should -Be $folder
        }
    }

    Context 'claude --resume' {
        It 'lists the sessions of the project, newest first' {
            # A dot in the path: it is replaced like every other character.
            $work = Join-Path $TestDrive 'my.project' 'work'
            [void](New-SessionFixture $config $work)
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                Get-CompletionText 'claude --resume ' | Should -Be @(
                    'aaaaaaaa-1111-2222-3333-aaaaaaaaaaaa'
                    'eeeeeeee-1111-2222-3333-eeeeeeeeeeee'
                    'dddddddd-1111-2222-3333-dddddddddddd'
                    'bbbbbbbb-1111-2222-3333-bbbbbbbbbbbb'
                    'ffffffff-1111-2222-3333-ffffffffffff'
                )
            }
        }

        It 'describes each session with its title, age, branch and size' {
            $work = Join-Path $TestDrive 'my.project' 'work'
            [void](New-SessionFixture $config $work)
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                $tips = Get-CompletionTip 'claude -r '
                # The index summary, not the prompt in the file.
                $tips['aaaaaaaa-1111-2222-3333-aaaaaaaaaaaa'] | Should -Match '^\d+ (week|month|year)s? ago · main · \d+B - indexed session label$'
                $tips['bbbbbbbb-1111-2222-3333-bbbbbbbbbbbb'] | Should -BeLike '* ago · feature · * - jsonl session prompt'
                $tips['dddddddd-1111-2222-3333-dddddddddddd'] | Should -BeLike '* - refactor-auth-flow'
                $tips['eeeeeeee-1111-2222-3333-eeeeeeeeeeee'] | Should -BeLike '* - my-renamed-session'
                $tips['ffffffff-1111-2222-3333-ffffffffffff'] | Should -BeLike '* - /exit'
                $tips.Values -join "`n" | Should -Not -Match 'hello there|auto-generated-title|should be hidden'

                $first = (Get-Completion 'claude -r ')[0]
                $first.ListItemText | Should -Be 'aaaaaaaa  indexed session label'
            }
        }

        It 'filters by the id typed so far and completes --resume=' {
            $work = Join-Path $TestDrive 'my.project' 'work'
            [void](New-SessionFixture $config $work)
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                Get-CompletionText 'claude -r bbbb' | Should -Be 'bbbbbbbb-1111-2222-3333-bbbbbbbbbbbb'
                Get-CompletionText 'claude --resume=dd' | Should -Be '--resume=dddddddd-1111-2222-3333-dddddddddddd'
            }
        }

        It 'finds the project through originalPath when no folder has its name' {
            $work = Join-Path $TestDrive 'fallback.dir' 'work'
            [void](New-SessionFixture $config $work -Fallback)
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                $tips = Get-CompletionTip 'claude -r '
                $tips['aaaaaaaa-1111-2222-3333-aaaaaaaaaaaa'] | Should -BeLike '* - indexed session label'
            }
        }

        It 'handles a space and an underscore in the path, without an index' {
            $work = Join-Path $TestDrive 'my project_x' 'work'
            $dir = New-SessionFixture $config $work
            Remove-Item -Force (Join-Path $dir 'sessions-index.json')
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                $texts = @(Get-CompletionText 'claude -r ')
                $texts | Should -Contain 'bbbbbbbb-1111-2222-3333-bbbbbbbbbbbb'
                # Without the index the newest session falls back to its own prompt.
                (Get-CompletionTip 'claude -r ')['aaaaaaaa-1111-2222-3333-aaaaaaaaaaaa'] | Should -BeLike '* - indexed jsonl prompt*'
            }
        }

        It 'gives a character beyond U+FFFF two hyphens' {
            $work = New-Directory (Join-Path $TestDrive "emoji$([char]::ConvertFromUtf32(0x1F4A9))" 'work')
            $key = ConvertTo-ProjectFolder (Resolve-RealPath $TestDrive)
            $correct = New-Directory (Join-Path $config 'projects' "$key-emoji---work")
            $decoy = New-Directory (Join-Path $config 'projects' "$key-emoji--work")
            [void](New-Session $correct 'aaaaaaaa-5555-2222-3333-aaaaaaaaaaaa' @(New-Prompt 'emoji project session'))
            [void](New-Session $decoy 'bbbbbbbb-5555-2222-3333-bbbbbbbbbbbb' @(New-Prompt 'decoy sibling session'))
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                Get-CompletionText 'claude -r ' | Should -Be 'aaaaaaaa-5555-2222-3333-aaaaaaaaaaaa'
            }
        }

        It 'does not offer the sessions of another project' {
            $work = Join-Path $TestDrive 'one' 'work'
            [void](New-SessionFixture $config $work)
            $other = New-Directory (Join-Path $TestDrive 'two')
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $other {
                Get-CompletionText 'claude -r ' | Should -Not -Contain 'aaaaaaaa-1111-2222-3333-aaaaaaaaaaaa'
            }
        }
    }

    Context 'CLAUDE_COMPLETION_SESSION_LIMIT' {
        BeforeEach {
            $script:work = Join-Path $TestDrive 'cap.test' 'work'
            $dir = New-SessionFixture $config $work
            $old = [datetime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
            foreach ($n in 1..30) {
                [void](New-Session $dir ('{0:d8}-9999-2222-3333-000000000000' -f $n) @(New-Prompt "old session $n") $old.AddMinutes($n))
            }
        }

        It 'offers the 20 most recent sessions by default' {
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                $texts = @(Get-CompletionText 'claude -r ')
                $texts.Count | Should -Be 20
                $texts[0] | Should -Be 'aaaaaaaa-1111-2222-3333-aaaaaaaaaaaa'
                # Five from the fixture, then the newest of the thirty.
                $texts[5] | Should -Be '00000030-9999-2222-3333-000000000000'
            }
        }

        It 'caps the list at <limit>' -ForEach @(
            @{ limit = '1'; count = 1 }
            @{ limit = '3'; count = 3 }
            # 0 or less lifts the cap.
            @{ limit = '0'; count = 35 }
            @{ limit = '-1'; count = 35 }
            # Not a number: the default applies.
            @{ limit = 'many'; count = 20 }
        ) {
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work -Environment @{ CLAUDE_COMPLETION_SESSION_LIMIT = $limit } {
                $texts = @(Get-CompletionText 'claude -r ')
                $texts.Count | Should -Be $count
                $texts[0] | Should -Be 'aaaaaaaa-1111-2222-3333-aaaaaaaaaaaa'
            }
        }
    }

    Context 'where the sessions are read from' {
        It 'uses ~/.claude without CLAUDE_CONFIG_DIR, and CLAUDE_CONFIG_DIR with it' {
            $fakeHome = New-Directory (Join-Path $TestDrive 'home')
            $work = New-Directory (Join-Path $TestDrive 'where' 'work')
            $folder = ConvertTo-ProjectFolder (Resolve-RealPath $work)
            [void](New-Session (New-Directory (Join-Path $fakeHome '.claude' 'projects' $folder)) 'aaaaaaaa-0000-0000-0000-000000000001' @(New-Prompt 'from home'))
            [void](New-Session (New-Directory (Join-Path $config 'projects' $folder)) 'bbbbbbbb-0000-0000-0000-000000000002' @(New-Prompt 'from config dir'))

            Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $work {
                Get-CompletionText 'claude -r ' | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
            }
            Use-ClaudeEnvironment -HomeDir $fakeHome -ConfigDir $config -Cwd $work {
                Get-CompletionText 'claude -r ' | Should -Be 'bbbbbbbb-0000-0000-0000-000000000002'
            }
        }

        It 'finds the project from a symbolic link to it' {
            $real = New-Directory (Join-Path $TestDrive 'linked' 'real')
            $link = Join-Path $TestDrive 'linked' 'link'
            try { [void](New-Item -ItemType SymbolicLink -Path $link -Target $real -ErrorAction Stop) }
            catch { Set-ItResult -Skipped -Because 'symbolic links cannot be created here'; return }
            $dir = New-Directory (Join-Path $config 'projects' (ConvertTo-ProjectFolder (Resolve-RealPath $real)))
            [void](New-Session $dir 'aaaaaaaa-0000-0000-0000-00000000000a' @(New-Prompt 'through a link'))
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $link {
                Get-CompletionText 'claude -r ' | Should -Be 'aaaaaaaa-0000-0000-0000-00000000000a'
            }
        }
    }

    Context 'session files that are missing, broken or hostile' {
        BeforeEach {
            $script:work = New-Directory (Join-Path $TestDrive 'broken' 'work')
            $script:dir = New-Directory (Join-Path $config 'projects' (ConvertTo-ProjectFolder (Resolve-RealPath $work)))
        }

        It 'offers nothing, and no error, without a projects directory' {
            Remove-Item -Recurse -Force (Join-Path $config 'projects')
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                $Error.Clear()
                Get-CompletionText 'claude -r aaaa' | Should -BeNullOrEmpty
                $Error.Count | Should -Be 0
            }
        }

        It 'skips empty and malformed files without hiding the valid ones' {
            $now = [datetime]::UtcNow
            Set-TextFile (Join-Path $dir '11111111-0000-0000-0000-000000000000.jsonl') ''
            Set-TextFile (Join-Path $dir '22222222-0000-0000-0000-000000000000.jsonl') "not json at all`n{`"type`":`"user`",`n[1,2,3]`n`"user`"`n"
            [void](New-Session $dir '33333333-0000-0000-0000-000000000000' @(
                    '{"type":"user","message":"not an object"}'
                    '{"type":"user","message":{"content":42}}'
                    '{"type":"user","isMeta":true,"message":{"content":"a meta prompt"}}'
                    '{"type":"user","message":{"content":[{"type":"image"},{"type":"text","text":"prompt after an image"}]}}'
                ) $now)
            Set-TextFile (Join-Path $dir 'sessions-index.json') '{ broken'
            Set-TextFile (Join-Path $dir 'notes.txt') 'not a session'
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                $Error.Clear()
                $tips = Get-CompletionTip 'claude -r '
                $tips.Keys | Should -Be '33333333-0000-0000-0000-000000000000'
                $tips['33333333-0000-0000-0000-000000000000'] | Should -BeLike '* · ? · * - prompt after an image'
                $Error.Count | Should -Be 0
            }
        }

        It 'strips control characters from what it shows' {
            $escape = [char]27
            [void](New-Session $dir '44444444-0000-0000-0000-000000000000' @(
                    @{ type = 'user'; gitBranch = "ma${escape}[31min"; message = @{ content = "first line`r`nsecond${escape}[2J line`ttabbed$([char]7)" } }
                ))
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                $match = Get-Completion 'claude -r '
                $match.ToolTip | Should -Not -Match '[\p{Cc}]'
                $match.ListItemText | Should -Not -Match '[\p{Cc}]'
                $match.ToolTip | Should -BeLike '* - first line second*line tabbed'
            }
        }

        It 'cuts a long title to 80 characters' {
            [void](New-Session $dir '55555555-0000-0000-0000-000000000000' @(New-Prompt ('x' * 500)))
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                (Get-Completion 'claude -r ').ListItemText | Should -Be ('55555555  ' + 'x' * 80)
            }
        }

        It 'finds the prompt at the start and a title at the end of a large file' {
            $filler = '{"type":"assistant","message":{"content":"' + ('y' * 2000) + '"}}'
            $records = @((New-Prompt 'prompt at the start')) + @($filler) * 1500 + @(@{ type = 'custom-title'; customTitle = 'title at the end' })
            $path = New-Session $dir '66666666-0000-0000-0000-000000000000' $records
            (Get-Item $path).Length | Should -BeGreaterThan 2MB
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                (Get-Completion 'claude -r ').ToolTip | Should -Match ' · main · 2(\.\d)?MB - title at the end$'
            }
        }

        It 'picks up a title added to a session after it was first listed' {
            $path = New-Session $dir '77777777-0000-0000-0000-000000000000' @(New-Prompt 'before the rename')
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                (Get-Completion 'claude -r ').ToolTip | Should -BeLike '* - before the rename'
                Add-Content -LiteralPath $path -Value '{"type":"custom-title","customTitle":"after the rename"}'
                (Get-Completion 'claude -r ').ToolTip | Should -BeLike '* - after the rename'
            }
        }
    }

    Context 'speed' {
        It 'stays quick with hundreds of session files' {
            $work = New-Directory (Join-Path $TestDrive 'many' 'work')
            $dir = New-Directory (Join-Path $config 'projects' (ConvertTo-ProjectFolder (Resolve-RealPath $work)))
            $filler = '{"type":"assistant","message":{"content":"' + ('y' * 1000) + '"}}'
            $body = ((@((New-Prompt 'a prompt' | ConvertTo-Json -Compress)) + @($filler) * 300) -join "`n") + "`n"
            $start = [datetime]::UtcNow.AddDays(-1)
            foreach ($n in 1..400) {
                $path = Join-Path $dir ('{0:d8}-0000-0000-0000-000000000000.jsonl' -f $n)
                [IO.File]::WriteAllText($path, $body)
                [IO.File]::SetLastWriteTimeUtc($path, $start.AddSeconds($n))
            }
            Use-ClaudeEnvironment -ConfigDir $config -Cwd $work {
                $cold = Measure-Command { $texts = @(Get-CompletionText 'claude -r ') }
                $texts.Count | Should -Be 20
                $texts[0] | Should -Be '00000400-0000-0000-0000-000000000000'
                $warm = Measure-Command { [void](Get-CompletionText 'claude -r ') }
                # Generous limits: slow CI disks must not make this flaky.
                $cold.TotalMilliseconds | Should -BeLessThan 3000
                $warm.TotalMilliseconds | Should -BeLessThan 1000
                Write-Host "      400 session files: first Tab $([int]$cold.TotalMilliseconds) ms, next Tab $([int]$warm.TotalMilliseconds) ms"
            }
        }
    }
}
