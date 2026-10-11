# The model aliases Claude accepts in place of a full model name. The list
# mirrors https://code.claude.com/docs/en/model-config#model-aliases. Full
# model ids are left out on purpose: they change with every model release.

$script:ClaudeModels = @(
    [pscustomobject]@{ Name = 'default'; Description = 'Clear any model override and use the default for your account' }
    [pscustomobject]@{ Name = 'best'; Description = 'Fable where it is available to you, otherwise the same model as opus' }
    [pscustomobject]@{ Name = 'fable'; Description = 'Fable, for your hardest and longest-running tasks' }
    [pscustomobject]@{ Name = 'sonnet'; Description = 'Latest Sonnet, for daily coding tasks' }
    [pscustomobject]@{ Name = 'opus'; Description = 'Latest Opus, for complex reasoning tasks' }
    [pscustomobject]@{ Name = 'haiku'; Description = 'Fast and efficient Haiku, for simple tasks' }
    [pscustomobject]@{ Name = 'sonnet[1m]'; Description = 'Sonnet with a 1 million token context window' }
    [pscustomobject]@{ Name = 'opus[1m]'; Description = 'Opus with a 1 million token context window' }
    [pscustomobject]@{ Name = 'opusplan'; Description = 'opus during plan mode, then sonnet for execution' }
)

function Get-ClaudeModelItem { $script:ClaudeModels }

$script:ClaudeValueCompleters['Models'] = 'Get-ClaudeModelItem'
