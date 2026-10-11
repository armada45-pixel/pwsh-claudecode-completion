# How results are laid out in PSReadLine's menu: one per line, the name
# followed by its description, as zsh shows them. The other test files turn
# this off (see Helpers.ps1) and look at names and tooltips separately.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    $env:CLAUDE_CONFIG_DIR = New-Directory (Join-Path $TestDrive 'config')
    $script:work = New-Directory (Join-Path $TestDrive 'work')
    [void](New-Directory (Join-Path $work 'some-dir'))
    Push-Location $work
}

AfterAll {
    Pop-Location
    $env:CLAUDE_CONFIG_DIR = $null
    $env:CLAUDE_COMPLETION_DESCRIPTIONS = 'tooltip'
}

Describe 'list layout' {
    BeforeEach { $env:CLAUDE_COMPLETION_DESCRIPTIONS = $null }

    It 'shows each command with its description on one line' {
        $found = Get-Completion 'claude mcp '
        $found[0].ListItemText | Should -Be 'add                      -- Add an MCP server to Claude Code'
        ($found | Where-Object CompletionText -EQ 'get').ListItemText | Should -Be 'get                      -- Get details about an MCP server'
        # The word that is inserted, and the tooltip, are unchanged.
        $found[0].CompletionText | Should -Be 'add'
        $found[0].ToolTip | Should -Be 'Add an MCP server to Claude Code'
    }

    It 'lines the descriptions up after the longest name' {
        $columns = (Get-Completion 'claude mcp ').ListItemText | ForEach-Object { $_.IndexOf(' -- ', [StringComparison]::Ordinal) }
        $columns | Select-Object -Unique | Should -HaveCount 1
    }

    It 'does the same for flags and for values with a description' {
        (Get-Completion 'claude install -')[0].ListItemText | Should -Be '--force  -- Force installation even if already installed'
        (Get-Completion 'claude --model ' | Where-Object CompletionText -EQ 'opus').ListItemText | Should -Be 'opus        -- Latest Opus, for complex reasoning tasks'
        # The list shows the name; quotes are only in the inserted word.
        (Get-Completion 'claude --model ' | Where-Object CompletionText -EQ "'sonnet[1m]'").ListItemText | Should -Be 'sonnet[1m]  -- Sonnet with a 1 million token context window'
    }

    It 'cuts a line that would not fit the window' {
        $longest = ((Get-Completion 'claude plugin ').ListItemText | Measure-Object Length -Maximum).Maximum
        # 120 columns when there is no console to ask.
        $longest | Should -BeLessOrEqual 118
        (Get-Completion 'claude plugin ' | Where-Object CompletionText -EQ 'tag').ListItemText | Should -BeLike 'tag * -- Create a {name}--v{version} git tag*...'
    }

    It 'leaves values without a description as plain names' {
        (Get-Completion 'claude --effort ').ListItemText | Should -Be 'low', 'medium', 'high', 'xhigh', 'max', 'ultracode'
    }

    It 'leaves a list that is too long for the window as a grid of names' {
        $found = Get-Completion 'claude --'
        $found.Count | Should -BeGreaterThan 60
        $found[0].ListItemText | Should -Be '--add-dir'
    }

    It 'leaves file names as they are, next to described names' {
        $found = Get-Completion 'claude plugin eval '
        ($found | Where-Object CompletionText -EQ 'init').ListItemText | Should -BeLike 'init* -- Author an eval suite*'
        ($found | Where-Object CompletionText -EQ (Join-Path '.' 'some-dir')).ListItemText | Should -Be 'some-dir'
    }

    It 'keeps the plain names with CLAUDE_COMPLETION_DESCRIPTIONS=tooltip' {
        $env:CLAUDE_COMPLETION_DESCRIPTIONS = 'tooltip'
        (Get-Completion 'claude mcp ')[0].ListItemText | Should -Be 'add'
    }

    It 'does not reformat a single result' {
        (Get-Completion 'claude mcp ge').ListItemText | Should -Be 'get'
    }
}

Describe 'an optional value with nothing to offer' {
    It 'goes on to the commands instead of file names' {
        # No sessions in this directory.
        $texts = Get-CompletionText 'claude --resume '
        $texts | Should -Contain 'mcp'
        $texts | Should -Not -Contain (Join-Path '.' 'some-dir')
    }

    It 'still offers the flags after it' {
        Get-CompletionText 'claude --resume --mod' | Should -Be '--model'
    }
}
