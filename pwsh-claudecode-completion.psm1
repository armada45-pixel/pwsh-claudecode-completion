# Tab completion for the Claude Code CLI (`claude`). Completion only: no
# aliases, no wrapper functions.

. $PSScriptRoot/src/Spec.ps1
. $PSScriptRoot/src/Engine.ps1
. $PSScriptRoot/src/Models.ps1

# `claude` covers the native build; the other names cover an npm install and
# a command typed with its extension.
Register-ArgumentCompleter -Native -CommandName claude, claude.exe, claude.cmd, claude.ps1 -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    # Nothing may be printed into the prompt, whatever goes wrong.
    try {
        $ErrorActionPreference = 'Stop'
        Get-ClaudeCompletion -WordToComplete $wordToComplete -CommandAst $commandAst -CursorPosition $cursorPosition
    }
    catch { }
}
