# Tab completion for the Claude Code CLI (`claude`). Completion only: no
# aliases, no wrapper functions.

. $PSScriptRoot/src/Spec.ps1
. $PSScriptRoot/src/Engine.ps1
. $PSScriptRoot/src/Paths.ps1
. $PSScriptRoot/src/Models.ps1
. $PSScriptRoot/src/Sessions.ps1
. $PSScriptRoot/src/BackgroundSessions.ps1

# `claude` covers the native build; the other names cover an npm install and
# a command typed with its extension.
Register-ArgumentCompleter -Native -CommandName claude, claude.exe, claude.cmd, claude.ps1 -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    # Nothing may be printed into the prompt, whatever goes wrong. A broken
    # file is expected and handled, so it should not show up in $Error either.
    $errorCount = $global:Error.Count
    try {
        $ErrorActionPreference = 'Stop'
        Get-ClaudeCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
    }
    catch { }
    finally {
        $added = $global:Error.Count - $errorCount
        if ($added -gt 0) { $global:Error.RemoveRange(0, $added) }
    }
}
