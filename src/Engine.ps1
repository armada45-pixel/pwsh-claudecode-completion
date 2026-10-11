# Decides what to offer at the cursor: walks the words already typed through
# the tree from Spec.ps1, then completes a flag, a flag's value, a subcommand
# or a positional argument.
#
# String searches here are ordinal on purpose (a [char] argument, or an
# explicit StringComparison). The culture-aware overloads treat punctuation
# as ignorable under some cultures: 'user,pro'.LastIndexOf(',') is 8 under
# th-TH, not 4.

using namespace System.Collections.Generic
using namespace System.Management.Automation

# Value completers by the name Spec.ps1 uses for them. Each one is a function
# that takes the context (see Get-ClaudeCompletion) and returns objects with
# Name, Description and, optionally, ListText.
$script:ClaudeValueCompleters = @{}

# The command tree is by far the largest file here, so it is loaded and
# built on the first Tab rather than on import: a profile that imports the
# module pays for it only in sessions that complete `claude`.
$script:ClaudeSpec = $null
function Get-ClaudeSpec {
    if (-not $script:ClaudeSpec) {
        . (Join-Path $PSScriptRoot 'Spec.ps1')
        $script:ClaudeSpec = New-ClaudeSpec
    }
    $script:ClaudeSpec
}

# Anything read from a file is shown through this: control characters would
# otherwise reach the terminal. Line breaks and tabs become a space, the
# other control characters (escape, bell, ...) are dropped.
function ConvertTo-ClaudeDisplayText {
    param([string]$Text)
    if (-not $Text) { return '' }
    $Text = [regex]::Replace($Text, '[\t\n\v\f\r\x85\p{Zl}\p{Zp}]+', ' ')
    [regex]::Replace($Text, '\p{Cc}', '').Trim()
}

# Quote a value when PowerShell would not pass it on as one literal word.
function ConvertTo-ClaudeArgument {
    param([string]$Value)
    if ($Value -match '^[\p{L}\p{N}_./\\:%+=~^-][\p{L}\p{N}_./\\:@%+=~^-]*$') { return $Value }
    "'" + $Value.Replace("'", "''") + "'"
}

function New-ClaudeResult {
    param(
        [string]$Text, [string]$ListText, [string]$ToolTip,
        [CompletionResultType]$Type = [CompletionResultType]::ParameterValue,
        [string]$Prefix = ''
    )
    if (-not $Text -or $Text -match '[\p{Cc}\p{Zl}\p{Zp}]') { return }
    $list = ConvertTo-ClaudeDisplayText $ListText
    if (-not $list) { $list = $Text }
    $tip = ConvertTo-ClaudeDisplayText $ToolTip
    if (-not $tip) { $tip = $list }
    [CompletionResult]::new($Prefix + (ConvertTo-ClaudeArgument $Text), $list, $Type, $tip)
}

# Lay a short list of results out the way zsh does: one per line, the name
# followed by its description. PSReadLine's menu shows the list text, and a
# list text as wide as this makes it a single column.
#   CLAUDE_COMPLETION_DESCRIPTIONS=tooltip keeps the plain names; the
#   description is then only the tooltip under the menu.
# A list too long for the window stays a grid of names: PSReadLine does not
# page a menu, it scrolls the prompt away.
function Format-ClaudeResultList {
    param([object[]]$Results)
    if ($Results.Count -lt 2 -or $env:CLAUDE_COMPLETION_DESCRIPTIONS -eq 'tooltip') { return $Results }
    $width = 120
    $height = 40
    try {
        if ([Console]::WindowWidth -gt 20) { $width = [Console]::WindowWidth }
        if ([Console]::WindowHeight -gt 5) { $height = [Console]::WindowHeight }
    }
    catch { }
    if ($Results.Count -gt $height - 4) { return $Results }

    # Results that already show more than a name (sessions), and file names, stay as they are.
    $plain = { param($r) $r.ResultType -in [CompletionResultType]::ParameterValue, [CompletionResultType]::ParameterName -and $r.ToolTip -cne $r.ListItemText -and -not $r.ListItemText.Contains([char]' ') }
    $pad = 0
    foreach ($result in $Results) { if ((& $plain $result) -and $result.ListItemText.Length -gt $pad) { $pad = $result.ListItemText.Length } }
    if (-not $pad) { return $Results }

    foreach ($result in $Results) {
        if (-not (& $plain $result)) { $result; continue }
        $line = $result.ListItemText.PadRight($pad) + '  -- ' + $result.ToolTip
        if ($line.Length -gt $width - 2) { $line = $line.Substring(0, $width - 5) + '...' }
        [CompletionResult]::new($result.CompletionText, $line, $result.ResultType, $result.ToolTip)
    }
}

function Get-ClaudePathResult {
    param([string]$Current, [switch]$DirectoryOnly)
    foreach ($result in [CompletionCompleters]::CompleteFilename($Current)) {
        if ($DirectoryOnly -and $result.ResultType -ne [CompletionResultType]::ProviderContainer) { continue }
        $result
    }
}

# Complete the value of a flag or a positional argument.
#   Current: the part of the word PowerShell will replace, without quotes.
#   Typed:   the whole value typed so far. It differs from Current in a
#            comma-separated list, where PowerShell replaces the last item only.
#   Prefix:  text to put back in front of each result (`--flag=`).
function Get-ClaudeValueResult {
    param($Spec, [string]$Current, [string]$Typed, [string]$Prefix = '', $Context)

    $used = @()
    if ($Spec.Separator) {
        $separator = $Spec.Separator
        if ($Current.Contains($separator)) {
            # A quoted list is replaced as a whole, so keep the items before the last one.
            $cut = $Current.LastIndexOf($separator, [StringComparison]::Ordinal) + 1
            $Prefix += $Current.Substring(0, $cut)
            $used = $Current.Substring(0, $cut).Split($separator)
            $Current = $Current.Substring($cut)
        }
        elseif ($Typed.Contains($separator)) {
            $used = $Typed.Substring(0, $Typed.LastIndexOf($separator, [StringComparison]::Ordinal)).Split($separator)
        }
    }

    foreach ($value in $Spec.Values) {
        if ($value -in $used -or -not $value.StartsWith($Current, [StringComparison]::OrdinalIgnoreCase)) { continue }
        New-ClaudeResult -Text $value -Prefix $Prefix
    }

    foreach ($name in $Spec.Completer) {
        if ($name -in 'File', 'Directory') {
            # A path after `--flag=` would need its quoting redone; leave that to the default.
            if (-not $Prefix) { Get-ClaudePathResult -Current $Current -DirectoryOnly:($name -eq 'Directory') }
            continue
        }
        $completer = $script:ClaudeValueCompleters[$name]
        if (-not $completer) { continue }
        foreach ($item in (& $completer $Context)) {
            if (-not $item.Name -or $item.Name -in $used) { continue }
            if (-not $item.Name.StartsWith($Current, [StringComparison]::OrdinalIgnoreCase)) { continue }
            New-ClaudeResult -Text $item.Name -ListText $item.ListText -ToolTip $item.Description -Prefix $Prefix
        }
    }
}

function Get-ClaudeFlagResult {
    param($Node, [string]$Current, [HashSet[string]]$Seen)

    $excluded = [HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($flag in $Node.Flags) {
        if ($flag.Excludes -and $Seen.Contains($flag.Names[0])) {
            foreach ($name in $flag.Excludes) { [void]$excluded.Add($name) }
        }
    }
    foreach ($flag in $Node.Flags) {
        if (-not $flag.Repeat -and $Seen.Contains($flag.Names[0])) { continue }
        if ($excluded.Contains($flag.Names[0])) { continue }
        foreach ($name in $flag.Names) {
            # Flags differ by case (`-h` and `-H`), so the match is exact.
            if (-not $name.StartsWith($Current, [StringComparison]::Ordinal)) { continue }
            New-ClaudeResult -Text $name -ToolTip $flag.Description -Type ([CompletionResultType]::ParameterName)
        }
    }
}

function Get-ClaudeCompletion {
    param([string]$WordToComplete, $CommandAst, [int]$CursorPosition)

    $node = Get-ClaudeSpec
    $context = [pscustomobject]@{
        Cwd = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
    }

    # Only the words before the cursor decide where we are. The word under the
    # cursor is not a command yet, and later words must not change the offer.
    $words = [List[string]]::new()
    $typed = ''
    $elements = $CommandAst.CommandElements
    for ($i = 1; $i -lt $elements.Count; $i++) {
        $element = $elements[$i]
        if ($element.Extent.EndOffset -lt $CursorPosition) {
            if ($element -is [Language.StringConstantExpressionAst]) { $words.Add($element.Value) }
            else { $words.Add($element.Extent.Text) }
        }
        elseif ($element.Extent.StartOffset -lt $CursorPosition) {
            $typed = $element.Extent.Text.Substring(0, $CursorPosition - $element.Extent.StartOffset)
            break
        }
        else { break }
    }

    $current = $WordToComplete
    if ($current.Length -and $current[0] -in [char]39, [char]34) {
        $quote = $current[0]
        $current = $current.Substring(1)
        if ($current.Length -and $current[$current.Length - 1] -eq $quote) {
            $current = $current.Substring(0, $current.Length - 1)
        }
        $typed = $current
    }
    if (-not $typed) { $typed = $current }

    # --- where are we? ------------------------------------------------------
    $seen = [HashSet[string]]::new([StringComparer]::Ordinal)
    $position = 0          # positional arguments given to $node so far
    $consumed = $false     # $node has been given any word at all
    $pending = $null       # flag whose value comes next
    $pendingCount = 0      # values $pending has taken (for -Variadic)
    $literal = $false      # after `--`
    $isRoot = $true

    foreach ($word in $words) {
        if ($pending) {
            $isOption = $word.Length -gt 1 -and $word[0] -eq [char]'-'
            $take = if ($pending.Variadic) { -not $isOption }
            elseif ($pending.Optional) {
                # `claude --debug mcp`: an optional value that names a command is the command.
                -not $isOption -and -not ($isRoot -and $position -eq 0 -and $node.Subs.ContainsKey($word))
            }
            else { $true }
            if ($take) {
                $pendingCount++
                if (-not $pending.Variadic) { $pending = $null }
                continue
            }
            $pending = $null
        }
        if (-not $literal) {
            if ($word -ceq '--') { $literal = $true; $consumed = $true; continue }
            if ($word.Length -gt 1 -and $word[0] -eq [char]'-') {
                $consumed = $true
                $equals = $word.IndexOf([char]'=')
                $name = if ($equals -gt 0) { $word.Substring(0, $equals) } else { $word }
                $flag = $null
                if ($node.FlagMap.TryGetValue($name, [ref]$flag)) {
                    [void]$seen.Add($flag.Names[0])
                    if ($flag.TakesValue -and $equals -lt 0) { $pending = $flag; $pendingCount = 0 }
                }
                continue
            }
        }
        $child = $null
        if ($position -eq 0 -and -not ($node.SubsFirstOnly -and $consumed) -and $node.Subs.TryGetValue($word, [ref]$child)) {
            $node = $child
            $isRoot = $false
            $seen.Clear()
            $position = 0
            $consumed = $false
            $literal = $false
            continue
        }
        $position++
        $consumed = $true
    }

    # --- the value of the flag before the cursor ------------------------------
    $isOption = -not $literal -and $current.Length -and $current[0] -eq [char]'-'
    if ($pending) {
        if ($pending.Variadic -and $pendingCount -gt 0) {
            # It has a value already; another one, or anything else, may follow.
            if (-not $isOption) {
                $values = @(Get-ClaudeValueResult -Spec $pending -Current $current -Typed $typed -Context $context)
                if ($values.Count) { return $values }
            }
        }
        elseif (-not $pending.Optional) {
            return Get-ClaudeValueResult -Spec $pending -Current $current -Typed $typed -Context $context
        }
        elseif (-not $isOption) {
            # The value may be left out. With nothing to offer for it (no
            # sessions here, say), go on to what can follow instead of
            # leaving PowerShell to offer file names.
            $values = @(Get-ClaudeValueResult -Spec $pending -Current $current -Typed $typed -Context $context)
            if ($values.Count) { return $values }
        }
    }

    # --- `--flag=value` ------------------------------------------------------
    if (-not $literal -and $typed.Length -and $typed[0] -eq [char]'-' -and $typed.IndexOf([char]'=') -gt 0) {
        $equals = $typed.IndexOf([char]'=')
        $flag = $null
        if ($node.FlagMap.TryGetValue($typed.Substring(0, $equals), [ref]$flag) -and $flag.TakesValue) {
            $value = $typed.Substring($equals + 1)
            # PowerShell replaces the whole word, or only the last item of a comma list.
            if ($isOption) {
                return Get-ClaudeValueResult -Spec $flag -Current $value -Typed $value -Prefix $typed.Substring(0, $equals + 1) -Context $context
            }
            return Get-ClaudeValueResult -Spec $flag -Current $current -Typed $value -Context $context
        }
        return
    }

    # --- a flag --------------------------------------------------------------
    if ($isOption) {
        return Get-ClaudeFlagResult -Node $node -Current $current -Seen $seen
    }

    # --- a subcommand or a positional argument ------------------------------------
    $results = [List[object]]::new()
    if ($position -eq 0 -and -not ($node.SubsFirstOnly -and $consumed)) {
        foreach ($sub in $node.SubList) {
            if (-not $sub.Name.StartsWith($current, [StringComparison]::OrdinalIgnoreCase)) { continue }
            $results.Add((New-ClaudeResult -Text $sub.Name -ToolTip $sub.Description))
        }
    }
    $argument = $null
    if ($position -lt $node.Args.Count) { $argument = $node.Args[$position] }
    elseif ($node.Args.Count -and $node.Args[$node.Args.Count - 1].Rest) { $argument = $node.Args[$node.Args.Count - 1] }
    if ($argument -and $argument.Unless) {
        foreach ($name in $argument.Unless) { if ($seen.Contains($name)) { $argument = $null; break } }
    }
    $wantsPath = $false
    if ($argument) {
        $wantsPath = [bool]($argument.Completer | Where-Object { $_ -in 'File', 'Directory' })
        foreach ($result in (Get-ClaudeValueResult -Spec $argument -Current $current -Typed $typed -Context $context)) {
            $results.Add($result)
        }
    }
    if ($results.Count) { return $results }

    # Nothing to offer for this position: show the flags instead of leaving
    # PowerShell to fall back to file names.
    if (-not $current -and -not $wantsPath -and -not $literal) {
        return Get-ClaudeFlagResult -Node $node -Current '' -Seen $seen
    }
}
