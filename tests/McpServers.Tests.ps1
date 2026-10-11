# MCP server names for `claude mcp get|remove|login|logout`.
# Counterpart of test-mcp-server-names.sh.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')

    $script:fakeHome = New-Directory (Join-Path $TestDrive 'home')
    $script:proj = New-Directory (Join-Path $fakeHome 'proj')
    [void](New-Directory (Join-Path $proj '.git'))
    $script:deeper = New-Directory (Join-Path $proj 'sub' 'deeper')
    $script:elsewhere = New-Directory (Join-Path $fakeHome 'elsewhere')
    $script:other = New-Directory (Join-Path $fakeHome 'other')

    function Set-UserConfig {
        param([string]$Path, [string]$ProjectKey = (Resolve-RealPath $proj))
        Set-TextFile $Path (@{
                mcpServers = [ordered]@{
                    'user-srv'     = @{ type = 'stdio'; command = 'npx' }
                    'url-srv'      = @{ type = 'http'; url = 'https://example.com/mcp?token=SECRETVALUE' }
                    'scoped:srv'   = @{ command = 'node' }
                    'broken-entry' = @('not', 'an', 'object')
                }
                projects   = [ordered]@{
                    $ProjectKey                  = @{ mcpServers = @{ 'local-srv' = @{ command = 'python' } } }
                    (Resolve-RealPath $other)    = @{ mcpServers = @{ 'other-project-srv' = @{ command = 'x' } } }
                    (Resolve-RealPath $elsewhere) = 'not an object'
                }
            } | ConvertTo-Json -Depth 6)
    }
    function Set-ProjectConfig {
        Set-TextFile (Join-Path $proj '.mcp.json') '{ "mcpServers": { "project-srv": { "type": "sse", "url": "https://example.org/sse" } } }'
    }
}

Describe 'MCP server names' {
    BeforeEach {
        Set-UserConfig (Join-Path $fakeHome '.claude.json')
        Set-ProjectConfig
    }

    It 'offers user, local and project servers, from a project subdirectory' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $deeper {
            Get-CompletionText 'claude mcp get ' | Should -Be 'user-srv', 'url-srv', 'scoped:srv', 'local-srv', 'project-srv'
        }
    }

    It 'describes each server by scope, type and target' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $deeper {
            $tips = Get-CompletionTip 'claude mcp get '
            $tips['user-srv'] | Should -Be 'user - stdio npx'
            $tips['scoped:srv'] | Should -Be 'user - stdio node'
            $tips['local-srv'] | Should -Be 'local - stdio python'
            $tips['project-srv'] | Should -Be 'project - sse https://example.org/sse'
        }
    }

    It 'leaves out other projects, bad entries and the query string of a URL' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $deeper {
            $tips = Get-CompletionTip 'claude mcp get '
            $tips.Keys | Should -Not -Contain 'other-project-srv'
            $tips.Keys | Should -Not -Contain 'broken-entry'
            $tips['url-srv'] | Should -Be 'user - http https://example.com/mcp'
            $tips.Values -join ' ' | Should -Not -Match 'SECRETVALUE'
        }
    }

    It 'finds the project through a symbolic link' {
        $link = Join-Path $fakeHome 'link'
        if (-not (Test-Path $link)) {
            try { [void](New-Item -ItemType SymbolicLink -Path $link -Target $proj -ErrorAction Stop) }
            catch { Set-ItResult -Skipped -Because 'symbolic links cannot be created here'; return }
        }
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd (Join-Path $link 'sub') {
            $texts = Get-CompletionText 'claude mcp get '
            $texts | Should -Contain 'local-srv'
            $texts | Should -Contain 'project-srv'
        }
    }

    It 'offers only user servers outside the project' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $elsewhere {
            Get-CompletionText 'claude mcp get ' | Should -Be 'user-srv', 'url-srv', 'scoped:srv'
        }
    }

    It 'uses the same list for claude mcp <_>' -ForEach 'remove', 'login', 'logout' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $texts = Get-CompletionText "claude mcp $_ "
            $texts | Should -Contain 'user-srv'
            $texts | Should -Contain 'project-srv'
        }
    }

    It 'filters by what is typed and offers one server per command' {
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            Get-CompletionText 'claude mcp get u' | Should -Be 'user-srv', 'url-srv'
            Get-CompletionText 'claude mcp remove --scope user loc' | Should -Be 'local-srv'
            Get-CompletionText 'claude mcp get user-srv ' | Should -Not -Contain 'url-srv'
        }
    }

    It 'reads .claude.json from CLAUDE_CONFIG_DIR when it is set' {
        $alt = New-Directory (Join-Path $fakeHome 'altconfig')
        Set-TextFile (Join-Path $alt '.claude.json') '{ "mcpServers": { "alt-srv": { "command": "alt" } } }'
        Use-ClaudeEnvironment -HomeDir $fakeHome -ConfigDir $alt -Cwd $elsewhere {
            Get-CompletionText 'claude mcp get ' | Should -Be 'alt-srv'
        }
    }

    It 'matches a Windows project recorded with forward slashes or another case' -Skip:(-not $IsWindows) {
        $key = (Resolve-RealPath $proj).Replace('\', '/').ToUpperInvariant()
        Set-UserConfig (Join-Path $fakeHome '.claude.json') -ProjectKey $key
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $deeper {
            Get-CompletionText 'claude mcp get ' | Should -Contain 'local-srv'
        }
    }

    It 'offers a server once when two scopes define it' {
        Set-TextFile (Join-Path $proj '.mcp.json') '{ "mcpServers": { "user-srv": { "command": "again" }, "project-srv": { "command": "p" } } }'
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $texts = Get-CompletionText 'claude mcp get '
            @($texts | Where-Object { $_ -eq 'user-srv' }).Count | Should -Be 1
            (Get-CompletionTip 'claude mcp get ')['user-srv'] | Should -Be 'user - stdio npx'
        }
    }

    It 'keeps the user and local servers when .mcp.json is malformed' {
        Set-TextFile (Join-Path $proj '.mcp.json') '{ "mcpServers": { "project-srv": '
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $Error.Clear()
            Get-CompletionText 'claude mcp get ' | Should -Be 'user-srv', 'url-srv', 'scoped:srv', 'local-srv'
            $Error.Count | Should -Be 0
        }
    }

    It 'keeps the project servers when .claude.json is malformed' {
        Set-TextFile (Join-Path $fakeHome '.claude.json') '{ "mcpServers": '
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $Error.Clear()
            Get-CompletionText 'claude mcp get ' | Should -Be 'project-srv'
            $Error.Count | Should -Be 0
        }
    }

    It 'offers nothing, and no error, when <case>' -ForEach @(
        @{ case = 'both files are missing'; user = $null; project = $null }
        @{ case = 'both files are empty'; user = ''; project = '' }
        @{ case = 'the files hold other JSON'; user = '[1, 2]'; project = '"text"' }
        @{ case = 'mcpServers is not an object'; user = '{ "mcpServers": 3, "projects": [] }'; project = '{ "mcpServers": null }' }
    ) {
        Remove-Item (Join-Path $fakeHome '.claude.json'), (Join-Path $proj '.mcp.json') -ErrorAction Ignore
        if ($null -ne $user) { Set-TextFile (Join-Path $fakeHome '.claude.json') $user }
        if ($null -ne $project) { Set-TextFile (Join-Path $proj '.mcp.json') $project }
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $Error.Clear()
            Get-CompletionText 'claude mcp get x' | Should -BeNullOrEmpty
            Get-CompletionText 'claude mcp get ' | Should -Be '-h', '--help'
            $Error.Count | Should -Be 0
        }
    }

    It 'strips control characters and skips names that contain them' {
        $escape = [char]27
        Set-TextFile (Join-Path $proj '.mcp.json') (@{ mcpServers = [ordered]@{
                    "evil${escape}[2Jname" = @{ command = 'x' }
                    "multi`nline"          = @{ command = 'x' }
                    'plain'                = @{ type = "st${escape}[31mdio"; command = "run`r`nme" }
                }
            } | ConvertTo-Json -Depth 4)
        Remove-Item (Join-Path $fakeHome '.claude.json')
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            $match = Get-Completion 'claude mcp get '
            $match.CompletionText | Should -Be 'plain'
            $match.ToolTip | Should -Be 'project - st [31mdio run me'
        }
    }

    It 'quotes a name PowerShell would not pass on as one word' {
        Set-TextFile (Join-Path $proj '.mcp.json') '{ "mcpServers": { "my server": { "command": "x" }, "it''s": { "command": "y" } } }'
        Remove-Item (Join-Path $fakeHome '.claude.json')
        Use-ClaudeEnvironment -HomeDir $fakeHome -Cwd $proj {
            Get-CompletionText 'claude mcp get ' | Should -Be "'my server'", "'it''s'"
            (Get-Completion 'claude mcp get ')[0].ListItemText | Should -Be 'my server'
            Get-CompletionText "claude mcp get 'my" | Should -Be "'my server'"
        }
    }
}
