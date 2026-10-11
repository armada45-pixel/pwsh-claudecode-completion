@{
    RootModule           = 'pwsh-claudecode-completion.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '6b0f3d0e-5c0b-4c58-9d5e-2f1c3a7e9b41'
    Author               = 'armada45-pixel'
    Copyright            = '(c) armada45-pixel. MIT License.'
    Description          = 'Tab completion for the Claude Code CLI (claude) in PowerShell 7: commands, flags, flag values, sessions, agents, MCP servers and plugins.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @()
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('claude', 'claude-code', 'completion', 'tab-completion', 'argument-completer', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            LicenseUri = 'https://github.com/armada45-pixel/pwsh-claudecode-completion/blob/main/LICENSE'
            ProjectUri = 'https://github.com/armada45-pixel/pwsh-claudecode-completion'
        }
    }
}
