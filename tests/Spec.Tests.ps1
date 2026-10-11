# A sweep over the whole command tree in src/Spec.ps1. The registered
# completer swallows every exception, so a mistake in the tree would only
# show up as a missing completion; here the engine is called directly and
# may throw.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Helpers.ps1')
    $script:module = Get-Module pwsh-claudecode-completion
    $script:spec = & $module { Get-ClaudeSpec }

    # Every command in the tree, once: @{ Path = 'mcp add'; Node = ... }.
    $script:nodes = [Collections.Generic.List[object]]::new()
    $visited = [Collections.Generic.HashSet[object]]::new()
    function Add-Node {
        param($Node, [string]$Path)
        $nodes.Add([pscustomobject]@{ Path = $Path; Node = $Node })
        foreach ($name in $Node.Subs.Keys) {
            if ($visited.Add($Node.Subs[$name])) { Add-Node $Node.Subs[$name] "$Path $name".Trim() }
        }
    }
    Add-Node $spec ''

    # Call the engine the way PowerShell would for a line with the cursor at its end.
    function Invoke-Engine {
        param([string]$Line)
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($Line, [ref]$null, [ref]$null)
        $command = $ast.Find({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
        $word = if ($Line.EndsWith(' ')) { '' } else { $command.CommandElements[-1].Extent.Text }
        & $module {
            param($word, $command, $cursor)
            $ErrorActionPreference = 'Stop'
            @(Get-ClaudeCompletion -WordToComplete $word -CommandAst $command -CursorPosition $cursor)
        } $word $command $Line.Length
    }

    $script:config = New-Directory (Join-Path $TestDrive 'config')
    $env:CLAUDE_CONFIG_DIR = $config
    Push-Location (New-Directory (Join-Path $TestDrive 'work'))
}

AfterAll {
    Pop-Location
    $env:CLAUDE_CONFIG_DIR = $null
}

Describe 'command tree' {
    It 'has a useful number of commands and flags' {
        $nodes.Count | Should -BeGreaterThan 60
        ($nodes.Node.Flags | Measure-Object).Count | Should -BeGreaterThan 300
    }

    It 'gives every flag a name that starts with a dash, and a description' {
        foreach ($entry in $nodes) {
            foreach ($flag in $entry.Node.Flags) {
                $flag.Description | Should -Not -BeNullOrEmpty -Because "claude $($entry.Path) $($flag.Names[0])"
                foreach ($name in $flag.Names) { $name | Should -Match '^--?[A-Za-z]' -Because "claude $($entry.Path)" }
            }
        }
    }

    It 'has no flag twice in one command' {
        foreach ($entry in $nodes) {
            $names = @($entry.Node.Flags.Names)
            $unique = [Collections.Generic.HashSet[string]]::new([string[]]$names, [StringComparer]::Ordinal)
            $unique.Count | Should -Be $names.Count -Because "claude $($entry.Path)"
        }
    }

    It 'describes every subcommand' {
        foreach ($entry in $nodes) {
            foreach ($sub in $entry.Node.SubList) { $sub.Description | Should -Not -BeNullOrEmpty -Because "claude $($entry.Path) $($sub.Name)" }
        }
    }

    It 'only names value completers that exist' {
        $known = @(& $module { $script:ClaudeValueCompleters.Keys }) + 'File', 'Directory'
        foreach ($entry in $nodes) {
            foreach ($item in @($entry.Node.Flags) + @($entry.Node.Args)) {
                foreach ($name in $item.Completer) { $name | Should -BeIn $known -Because "claude $($entry.Path)" }
            }
        }
        foreach ($name in (& $module { $script:ClaudeValueCompleters.Values })) {
            & $module { param($n) Get-Command $n -CommandType Function } $name | Should -Not -BeNullOrEmpty
        }
    }

    It 'only excludes flags and positionals by names that exist' {
        foreach ($entry in $nodes) {
            foreach ($name in @($entry.Node.Flags.Excludes) + @($entry.Node.Args.Unless)) {
                if ($name) { $entry.Node.FlagMap.ContainsKey($name) | Should -BeTrue -Because "claude $($entry.Path) refers to $name" }
            }
        }
    }

    It 'completes at every position of every command without an error' {
        $lines = 0
        foreach ($entry in $nodes) {
            $base = "claude $($entry.Path)".TrimEnd()
            $probes = @("$base ", "$base -", "$base --", "$base x ", "$base x y ", "$base -- ")
            foreach ($flag in $entry.Node.Flags) {
                $name = $flag.Names[-1]
                $probes += "$base $name "
                if ($flag.TakesValue) { $probes += "$base $name=", "$base $name v ", "$base $name v -" }
            }
            foreach ($line in $probes) {
                { Invoke-Engine $line } | Should -Not -Throw -Because $line
                $lines++
            }
        }
        $lines | Should -BeGreaterThan 1000
    }

    It 'offers the values of every flag that has a fixed list' {
        foreach ($entry in $nodes) {
            foreach ($flag in $entry.Node.Flags) {
                if (-not $flag.Values) { continue }
                $line = "claude $($entry.Path)".TrimEnd() + " $($flag.Names[-1]) "
                @((Invoke-Engine $line).CompletionText) | Should -Be $flag.Values -Because $line
            }
        }
    }

    It 'offers every flag of every command for a dash' {
        foreach ($entry in $nodes) {
            $line = "claude $($entry.Path)".TrimEnd() + ' -'
            @((Invoke-Engine $line).CompletionText) | Should -Be @($entry.Node.Flags.Names) -Because $line
        }
    }
}
