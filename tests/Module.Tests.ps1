# The module itself: it loads, registers the completer and adds nothing else
# to the session. Counterpart of test-syntax.sh and test-harness-errors.sh.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    $script:root = Join-Path $PSScriptRoot '..'
}

Describe 'module' {
    It 'has a valid manifest' {
        $manifest = Test-ModuleManifest (Join-Path $root 'pwsh-claudecode-completion.psd1')
        $manifest.Name | Should -Be 'pwsh-claudecode-completion'
        $manifest.PowerShellVersion | Should -Be ([version]'7.2')
    }

    It 'parses without syntax errors: <_>' -ForEach @(
        (Get-ChildItem (Join-Path $PSScriptRoot '..') -Recurse -Include *.ps1, *.psm1, *.psd1).FullName
    ) {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($_, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'is completion only: no commands, aliases or variables are exported' {
        $module = Get-Module pwsh-claudecode-completion
        $module.ExportedCommands.Count | Should -Be 0
        $module.ExportedAliases.Count | Should -Be 0
        $module.ExportedVariables.Count | Should -Be 0
    }

    It 'tracks a Claude version' {
        (Get-Content (Join-Path $root 'claude-version') -Raw).Trim() | Should -Match '^\d+\.\d+\.\d+$'
    }

    It 'completes for <_>' -ForEach 'claude', 'claude.exe', 'claude.cmd' {
        Get-CompletionText "$_ mcp ge" | Should -Be 'get'
    }

    It 'returns CompletionResult objects with a tooltip' {
        $match = (Get-Completion 'claude --versio')[0]
        $match | Should -BeOfType ([System.Management.Automation.CompletionResult])
        $match.CompletionText | Should -Be '--version'
        $match.ToolTip | Should -Be 'Output the version number'
    }

    It 'does not write errors while completing' {
        $Error.Clear()
        foreach ($line in 'claude ', 'claude --', 'claude mcp ', 'claude --resume ', 'claude --agent ', 'claude plugin install ', 'claude nonsense --x=') {
            [void](Get-Completion $line)
        }
        $Error.Count | Should -Be 0
    }
}
