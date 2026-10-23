# The command tree of the Claude Code CLI: commands, subcommands, flags, flag
# values and their descriptions. This file is data. It is the PowerShell
# counterpart of the `_arguments` blocks in `_claude` of
# zsh-claudecode-completion, and matches the CLI version in `claude-version`.
#
#   Sub  <names> <descriptions> [-SubsFirstOnly] { ... }
#       A command. Several names share one definition; give one description
#       for all of them or one per name.
#   Flag <names> <description> [-Arg <label>] [-Optional] [-Values ...]
#        [-Completer ...] [-Separator ','] [-Repeat] [-Variadic] [-Excludes ...]
#       An option. -Arg means it takes a value, -Optional that the value may be
#       left out. -Repeat keeps it on offer after its first use. -Variadic
#       takes every word up to the next option. -Excludes names options that
#       cannot be combined with it.
#   Pos  <label> [-Values ...] [-Completer ...] [-Rest] [-Unless ...]
#       A positional argument, in order. -Rest covers every later word too.
#
# -Completer names a value completer from Completers.ps1 (Models, Agents,
# Sessions, BackgroundSessions, McpServers, InstalledPlugins, Marketplaces,
# MarketplacePlugins) or File / Directory.

using namespace System.Collections.Generic

$script:ClaudeSpecNode = $null

function New-ClaudeSpecNode {
    [pscustomobject]@{
        Flags         = [List[object]]::new()
        FlagMap       = [Dictionary[string, object]]::new([StringComparer]::Ordinal)
        Subs          = [Dictionary[string, object]]::new([StringComparer]::Ordinal)
        SubList       = [List[object]]::new()
        Args          = [List[object]]::new()
        SubsFirstOnly = $false
    }
}

function Sub {
    param([string[]]$Names, [string[]]$Description, [scriptblock]$Body, [switch]$SubsFirstOnly)
    $parent = $script:ClaudeSpecNode
    $node = New-ClaudeSpecNode
    $node.SubsFirstOnly = [bool]$SubsFirstOnly
    for ($i = 0; $i -lt $Names.Count; $i++) {
        $parent.Subs[$Names[$i]] = $node
        $parent.SubList.Add([pscustomobject]@{
                Name        = $Names[$i]
                Description = $Description[[Math]::Min($i, $Description.Count - 1)]
            })
    }
    $script:ClaudeSpecNode = $node
    try { & $Body } finally { $script:ClaudeSpecNode = $parent }
    # Commands are listed in alphabetical order, whatever order they are declared in.
    $node.SubList.Sort([Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Name, $b.Name) })
}

function Flag {
    param(
        [string[]]$Names, [string]$Description, [string]$Arg, [string[]]$Values, [string[]]$Completer,
        [string]$Separator, [string[]]$Excludes, [switch]$Optional, [switch]$Repeat, [switch]$Variadic
    )
    $flag = [pscustomobject]@{
        Names       = $Names
        Description = $Description
        Arg         = $Arg
        TakesValue  = [bool]$Arg
        Optional    = [bool]$Optional
        Values      = $Values
        Completer   = $Completer
        Separator   = $Separator
        Repeat      = [bool]$Repeat
        Variadic    = [bool]$Variadic
        Excludes    = $Excludes
    }
    $script:ClaudeSpecNode.Flags.Add($flag)
    foreach ($name in $Names) { $script:ClaudeSpecNode.FlagMap[$name] = $flag }
}

function Pos {
    param([string]$Label, [string[]]$Values, [string[]]$Completer, [string[]]$Unless, [switch]$Rest)
    $script:ClaudeSpecNode.Args.Add([pscustomobject]@{
            Arg       = $Label
            Values    = $Values
            Completer = $Completer
            Separator = ''
            Unless    = $Unless
            Rest      = [bool]$Rest
        })
}

# The whole tree. Engine.ps1 loads this file and calls this on the first Tab.
function New-ClaudeSpec {
    $script:ClaudeSpecNode = New-ClaudeSpecNode
    Initialize-ClaudeSpec
    $root = $script:ClaudeSpecNode
    $root.SubList.Sort([Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Name, $b.Name) })
    $script:ClaudeSpecNode = $null
    $root
}

function Initialize-ClaudeSpec {
    Sub 'agents' 'Open agent view (manage background sessions)' {
        Flag '--add-dir' 'Additional directory to allow tool access to in dispatched sessions (repeatable)' -Arg 'directory' -Completer Directory -Repeat
        Flag '--agent' 'Default agent for sessions dispatched from agent view. Overrides the agent setting' -Arg 'agent' -Completer Agents
        Flag '--all' 'With --json: also include completed background sessions'
        Flag '--allow-dangerously-skip-permissions' 'Make bypass-permissions mode available to dispatched sessions without defaulting to it'
        Flag '--cwd' 'Show only background sessions started under path' -Arg 'path' -Completer Directory
        Flag '--dangerously-skip-permissions' 'Alias for --permission-mode bypassPermissions'
        Flag '--effort' 'Default effort level for sessions dispatched from agent view' -Arg 'level' -Values 'low','medium','high','xhigh','max','ultracode'
        Flag '-h','--help' 'Display help for command'
        Flag '--json' 'Print active sessions (interactive and background) as a JSON array and exit (for scripting; does not require a TTY)'
        Flag '--mcp-config' 'MCP server configuration to apply to dispatched sessions (repeatable)' -Arg 'config' -Completer File -Repeat
        Flag '--model' 'Default model for sessions dispatched from agent view' -Arg 'model' -Completer Models
        Flag '--permission-mode' 'Default permission mode for sessions dispatched from agent view' -Arg 'mode' -Values 'acceptEdits','auto','bypassPermissions','manual','dontAsk','plan'
        Flag '--plugin-dir' 'Load plugins from specified directory for the agent view and dispatched sessions (repeatable)' -Arg 'path' -Completer Directory -Repeat
        Flag '--restricted' 'Start dispatched sessions in restricted mode'
        Flag '--setting-sources' 'Comma-separated list of setting sources to load (user, project, local)' -Arg 'sources' -Values 'user','project','local' -Separator ','
        Flag '--settings' 'Settings file or JSON string to apply to the agent view and dispatched sessions' -Arg 'file-or-json' -Completer File
        Flag '--strict-mcp-config' 'Only use MCP servers from --mcp-config in dispatched sessions'
    }
    Sub 'attach','logs','stop','kill' 'Open a background session in this terminal','Print a background session''s recent terminal output','Stop a background session','Stop a background session (alias for stop)' {
        Flag '-h','--help' 'Display help for command'
        Pos 'session' -Completer BackgroundSessions
    }
    Sub 'rm' 'Delete a background session and its worktree (works on already-exited sessions)' {
        Flag '--discard-unpushed' 'Also discard the worktree''s unpushed commits (and any uncommitted changes) while it is still the same worktree at that commit - pass the value a previous claude rm <id> reported' -Arg 'commit@worktree-id'
        Flag '--force-remove-worktree' 'Delete the worktree directory even though the WorktreeRemove hook or git couldn''t remove it - pass the value a previous claude rm <id> reported' -Arg 'worktree-id'
        Flag '-h','--help' 'Display help for command'
        Pos 'session' -Completer BackgroundSessions
    }
    Sub 'respawn' 'Restart a background session (or all of them) so it picks up the current Claude binary' {
        Flag '--all' 'Restart every stopped session'
        Flag '-h','--help' 'Display help for command'
        Pos 'session' -Completer BackgroundSessions -Unless '--all'
    }
    Sub 'auth' 'Manage authentication' {
        Flag '-h','--help' 'Display help for command'
        Sub 'login' 'Sign in to your Anthropic account' {
            Flag '--claudeai' 'Use Claude subscription (default)'
            Flag '--console' 'Use Anthropic Console (API usage billing) instead of Claude subscription'
            Flag '--email' 'Pre-populate email address on the login page' -Arg 'email'
            Flag '-h','--help' 'Display help'
            Flag '--sso' 'Force SSO login flow'
        }
        Sub 'logout' 'Log out from your Anthropic account' {
            Flag '-h','--help' 'Display help'
        }
        Sub 'status' 'Show authentication status' {
            Flag '-h','--help' 'Display help'
            Flag '--json' 'Output as JSON (default)'
            Flag '--text' 'Output as human-readable text'
        }
        Sub 'help' 'Display help for command' { }
    }
    Sub 'mcp' 'Configure and manage MCP servers' {
        Flag '-h','--help' 'Display help for command'
        Sub 'serve' 'Start the Claude Code MCP server' {
            Flag '-d','--debug' 'Enable debug mode'
            Flag '-h','--help' 'Display help'
            Flag '--verbose' 'Override verbose mode setting from config'
        }
        Sub 'add' 'Add an MCP server to Claude Code' {
            Flag '--callback-port' 'Fixed port for OAuth callback (for servers requiring pre-registered redirect URIs)' -Arg 'port'
            Flag '--client-id' 'OAuth client ID for HTTP/SSE servers' -Arg 'clientId'
            Flag '--client-secret' 'Prompt for OAuth client secret (or set MCP_CLIENT_SECRET env var)'
            Flag '-e','--env' 'Set environment variables (e.g. -e KEY=value)' -Arg 'env' -Repeat
            Flag '-H','--header' 'Set headers for HTTP/SSE servers (e.g. -H "X-Api-Key: abc123" -H "X-Custom: value")' -Arg 'header' -Repeat
            Flag '-h','--help' 'Display help'
            Flag '-s','--scope' 'Configuration scope (local, user, or project) (default: local)' -Arg 'scope' -Values 'local','user','project'
            Flag '-t','--transport' 'Transport type (stdio, sse, http). Defaults to stdio if not specified' -Arg 'transport' -Values 'stdio','sse','http'
            Pos 'name'
            Pos 'commandOrUrl' -Completer File
            Pos 'args' -Completer File -Rest
        }
        Sub 'remove' 'Remove an MCP server' {
            Flag '-h','--help' 'Display help'
            Flag '-s','--scope' 'Configuration scope (local, user, or project) - if not specified, removes from whichever scope it exists in' -Arg 'scope' -Values 'local','user','project'
            Pos 'name' -Completer McpServers
        }
        Sub 'add-json' 'Add an MCP server (stdio, SSE, HTTP, or WebSocket) with a JSON string' {
            Flag '--client-secret' 'Prompt for OAuth client secret (or set MCP_CLIENT_SECRET env var)'
            Flag '-h','--help' 'Display help'
            Flag '-s','--scope' 'Configuration scope (local, user, or project) (default: local)' -Arg 'scope' -Values 'local','user','project'
            Pos 'name'
            Pos 'json'
        }
        Sub 'add-from-claude-desktop' 'Import MCP servers from Claude Desktop (Mac and WSL only)' {
            Flag '-h','--help' 'Display help'
            Flag '-s','--scope' 'Configuration scope (local, user, or project) (default: local)' -Arg 'scope' -Values 'local','user','project'
        }
        Sub 'get' 'Get details about an MCP server' {
            Flag '-h','--help' 'Display help'
            Pos 'name' -Completer McpServers
        }
        Sub 'list','reset-project-choices' 'List configured MCP servers','Reset all approved and rejected project-scoped (.mcp.json) servers within this project' {
            Flag '-h','--help' 'Display help'
        }
        Sub 'login' 'Authenticate with an MCP server (HTTP, SSE, or claude.ai connector)' {
            Flag '-h','--help' 'Display help'
            Flag '--no-browser' 'Print the authorization URL instead of opening a browser (for SSH/headless sessions - paste the redirect URL back when prompted)'
            Pos 'name' -Completer McpServers
        }
        Sub 'logout' 'Clear stored OAuth credentials for an MCP server' {
            Flag '-h','--help' 'Display help'
            Pos 'name' -Completer McpServers
        }
        Sub 'help' 'Display help for command' { }
    }
    Sub 'plugin','plugins' 'Manage Claude Code plugins' {
        Flag '-h','--help' 'Display help for command'
        Sub 'configure' 'Show a plugin''s options and which are unset, or save values from stdin with --values-stdin' {
            Flag '-h','--help' 'Display help'
            Flag '--json' 'Output as JSON'
            Flag '--values-stdin' 'Read option values from stdin as a JSON object of single-line strings; options left out keep their values'
            Pos 'plugin' -Completer InstalledPlugins
        }
        Sub 'details' 'Show a plugin''s component inventory and projected token cost' {
            Flag '-h','--help' 'Display help'
            Pos 'name' -Completer InstalledPlugins
        }
        Sub 'tag' 'Create a {name}--v{version} git tag for a plugin release, validating that plugin.json and any enclosing marketplace entry agree' {
            Flag '--dry-run' 'Print what would be tagged without creating it'
            Flag '-f','--force' 'Skip the dirty-working-tree and tag-already-exists checks'
            Flag '-h','--help' 'Display help'
            Flag '-m','--message' 'Tag annotation message (use %s for the version)' -Arg 'msg'
            Flag '--push' 'Push the tag to --remote after creating it'
            Flag '--remote' 'Remote to push to with --push (default: origin)' -Arg 'name'
            Pos 'path' -Completer File
        }
        Sub 'test' 'Run a mod''s tests' {
            Flag '-h','--help' 'Display help'
            Pos 'dir' -Completer Directory
        }
        Sub 'validate' 'Validate a plugin or marketplace manifest, or the skills, agents, and commands in a directory' {
            Flag '-h','--help' 'Display help'
            Flag '--json' 'Output the validation report as JSON (same exit codes)'
            Flag '--profile' 'Also exit 1 when the plugin directory (the catalog that plugins are submitted to) would refuse a submission of the plugin on a check this command runs' -Arg 'name' -Values 'directory'
            Flag '--strict' 'Treat warnings as errors (exit 1). Use in CI to fail on unrecognized fields, missing metadata, and other issues that the runtime tolerates'
            Pos 'path' -Completer File
        }
        Sub 'eval' 'Run eval cases against a plugin and report scored results' {
            # `init` is a command only as the first word that is neither an option nor an option's value.
            Sub 'init' 'Author an eval suite under the eval dir' {
                Flag '--bare' 'Write a blank template (prompt.md + graders/criteria.md) instead of running the interview'
                Flag '--eval-dir' 'Directory (below the current directory) to write cases into (default: experimental.evals from the plugin.json in the current directory, else evals/)' -Arg 'dir' -Completer Directory
                Flag '-h','--help' 'Display help'
                Flag '-i','--interactive' 'Run the authoring interview (already the default in a terminal); requires an interactive terminal'
                Pos 'name'
            }
            Flag '--ablation' 'Run a no-plugin baseline arm and report the score delta (none or with-without; default: with-without whenever a plugin resolves by name or target path, none otherwise; with-only graders like tool_used: Skill act as a plugin-fired indicator, not part of the score)' -Arg 'mode' -Values 'none','with-without'
            Flag '--allow-real-servers' 'With --mocks record: also start the plugin''s real MCP server processes for servers with no mock (runs as you, outside the OS sandbox that confines shell tools; use only on plugins you trust)'
            Flag '--allow-tools' 'Operator grant for gated tools (Bash, Write, Edit, WebFetch, mcp__*). Supports Tool(pattern:*) syntax' -Arg 'tools' -Repeat -Variadic
            Flag '--case' 'Filter cases by name glob' -Arg 'glob'
            Flag '--disallow-tools' 'Built-in tools to keep from Claude in every case, even if granted (e.g. Agent TaskStop)' -Arg 'tools' -Repeat -Variadic
            Flag '-j','--concurrency' 'Run up to n agent runs at once (1-8; default 1); each is a full claude child on your own credential sharing one rate limit, results keep case order' -Arg 'n'
            Flag '--eval-dir' 'Directory name (below the plugin) that holds the eval cases; results go to <plugin>/<dir>/results/ (default: the manifest''s experimental.evals value, else evals/)' -Arg 'dir' -Completer Directory
            Flag '-h','--help' 'Display help'
            Flag '--json' 'Print the full run result (prompts, graders, per-run scores) as JSON to stdout, or write it to a .json file' -Arg 'path' -Optional -Completer File
            Flag '--judge-model' 'Override LLM-grader model (default: haiku)' -Arg 'model' -Completer Models
            Flag '--keep-temp' 'Preserve scaffold dirs for debugging'
            Flag '--max-cost-usd' 'Optional hard cost ceiling; abort and report partial results if hit (exit 2). Checked before each run launches, so overrun is bounded to runs in flight; paid graders are skipped on breach while free graders still score' -Arg 'usd'
            Flag '--mocks' 'Mock stand-ins for MCP servers, from <eval dir>/mocks/ (default: record). record: a server with no mock isn''t started (see --allow-real-servers); off: every real server starts, gated by --allow-tools' -Arg 'mode' -Values 'record','off'
            Flag '--model' 'Override model for all cases' -Arg 'model' -Completer Models
            Flag '--no-publish' 'Keep the HTML report local only; skip publishing it to claude.ai'
            Flag '--no-scaffold' 'Explicitly skip scaffold_script'
            Flag '--output-dir' 'Directory for aggregate-result.json (default: ./<eval dir>/results/<timestamp>/)' -Arg 'dir' -Completer Directory
            Flag '--publish-report' 'Also require publishing the report to claude.ai (already the default when your account supports it); explains why if unavailable'
            Flag '--report' 'Write the self-contained HTML report (scores, prompts, grader verdicts) to path instead of the results dir' -Arg 'path' -Completer File
            Flag '--runs' 'Override per-case runs (default: case.runs ?? 3)' -Arg 'n'
            Flag '--scaffold' 'Run each case''s scaffold_script (runs author-supplied bash as you; off by default — only use on case files you authored)'
            Flag '--tag' 'Filter cases by tag (repeatable)' -Arg 'tag' -Repeat -Variadic
            Flag '--threshold' 'Exit 1 if any case score is below this threshold (default: 1.0)' -Arg 'threshold'
            Flag '--trust-plugin' 'Assert that you trust this plugin''s code and eval suite, and skip the first-run trust prompt (for CI; does not imply --scaffold, --allow-tools, or --mocks off)'
            Flag '--verbose' 'Log per-message trace events to the debug log (use --debug-file to read them)'
            Pos 'command-or-target' -Completer InstalledPlugins,File
        }
        Sub 'marketplace' 'Manage Claude Code marketplaces' {
            Flag '-h','--help' 'Display help for command'
            Sub 'add' 'Add a marketplace from a URL, path, or GitHub repo' {
                Flag '--claudeai' 'Add the marketplace of this name that claude.ai hosts for you, by its listed name or its local name'
                Flag '-h','--help' 'Display help'
                Flag '--json' 'Print one machine-readable result line as the last line on stdout (same exit codes)'
                Flag '--scope' 'Where to declare the marketplace: user (default), project, or local' -Arg 'scope' -Values 'user','project','local'
                Flag '--sparse' 'Limit checkout to specific directories via git sparse-checkout (for monorepos), e.g. --sparse .claude-plugin plugins' -Arg 'path' -Completer Directory -Repeat
                Pos 'source' -Completer File
            }
            Sub 'remove','rm' 'Remove a configured marketplace' {
                Flag '-h','--help' 'Display help'
                Flag '--json' 'Print one machine-readable result line as the last line on stdout (same exit codes)'
                Flag '--scope' 'Remove the marketplace declaration from a specific settings scope: user, project, or local. Omit to remove it from every scope' -Arg 'scope' -Values 'user','project','local'
                Pos 'name' -Completer Marketplaces
            }
            Sub 'update' 'Update marketplace(s) from their source - updates all if no name specified' {
                Flag '-h','--help' 'Display help'
                Flag '--json' 'With a marketplace name: print one machine-readable result line as the last line on stdout (same exit codes)'
                Pos 'name' -Completer Marketplaces
            }
            Sub 'list' 'List all configured marketplaces' {
                Flag '-h','--help' 'Display help'
                Flag '--json' 'Output as JSON'
            }
            Sub 'help' 'Display help for command' { }
        }
        Sub 'init','new' 'Scaffold a new plugin at ~/.claude/skills/<name>/' {
            Flag '--author' 'Author name (default: git config user.name)' -Arg 'name'
            Flag '--author-email' 'Author email (default: git config user.email)' -Arg 'email'
            Flag '--description' 'Manifest description' -Arg 'text'
            Flag '-f','--force' 'Overwrite an existing .claude-plugin/ at the target'
            Flag '-h','--help' 'Display help'
            Flag '--with' 'Also scaffold additional components' -Arg 'component' -Values 'skills','agents','hooks','mcp','lsp','output-style','channel' -Repeat
            Pos 'name'
        }
        Sub 'install','i' 'Install a plugin from available marketplaces (use plugin@marketplace for specific marketplace)' {
            Flag '--accept-command' 'Accept the marketplace-declared command (a command-source install, or the headersHelper fetching the archive) whose sha256 a previous --json run reported as shownCommand.sha256; only covers that exact command for that plugin/marketplace' -Arg 'sha256'
            Flag '--config' 'Set a userConfig option declared in the plugin''s manifest (repeatable)' -Arg 'key=value' -Repeat
            Flag '-h','--help' 'Display help'
            Flag '--json' 'Print one machine-readable result line on stdout instead of the human message (same exit codes; a marketplace-declared command is still shown and must be confirmed - pass -y when not interactive)'
            Flag '--marketplace' 'Install <plugin> (its bare name) from the marketplace at this source: owner/repo, a git or https URL, or a path; added first if not yet added' -Arg 'source' -Completer File
            Flag '--registry' 'For a <package>@npm install: resolve and download from this npm registry instead of the one your npm configuration selects' -Arg 'url'
            Flag '-s','--scope' 'Installation scope: user, project, or local (default: user)' -Arg 'scope' -Values 'user','project','local'
            Flag '-y','--yes' 'Accept the displayed marketplace-declared command without the confirmation prompt - a plugin installed by running a command, or one fetched via a headersHelper command (required when stdin or stdout is not a TTY)'
            Pos 'plugin' -Completer MarketplacePlugins
        }
        Sub 'prune','autoremove' 'Remove auto-installed dependencies that are no longer needed' {
            Flag '--dry-run' 'List what would be removed without removing'
            Flag '-h','--help' 'Display help'
            Flag '-s','--scope' 'Prune at scope: user, project, or local (default: user)' -Arg 'scope' -Values 'user','project','local'
            Flag '-y','--yes' 'Skip the confirmation prompt (required when stdin or stdout is not a TTY)'
        }
        Sub 'uninstall','remove' 'Uninstall an installed plugin' {
            Flag '-h','--help' 'Display help'
            Flag '--json' 'Print one machine-readable result line on stdout instead of the human message (same exit codes; not with --prune)'
            Flag '--keep-data' 'Preserve the plugin''s persistent data directory (~/.claude/plugins/data/{id}/)'
            Flag '--prune' 'Also remove auto-installed dependencies that are no longer needed (requires -y in non-interactive contexts)'
            Flag '-s','--scope' 'Uninstall from scope: user, project, or local (default: user)' -Arg 'scope' -Values 'user','project','local'
            Flag '-y','--yes' 'Skip the --prune confirmation prompt (required when stdin or stdout is not a TTY)'
            Pos 'plugin' -Completer InstalledPlugins
        }
        Sub 'enable' 'Enable a disabled plugin' {
            Flag '-h','--help' 'Display help'
            Flag '--json' 'Print one machine-readable result line on stdout instead of the human message (same exit codes)'
            Flag '-s','--scope' 'Installation scope: user, project, local (default: auto-detect)' -Arg 'scope' -Values 'user','project','local'
            Pos 'plugin' -Completer InstalledPlugins
        }
        Sub 'disable' 'Disable an enabled plugin' {
            Flag '-a','--all' 'Disable all enabled plugins'
            Flag '-h','--help' 'Display help'
            Flag '--json' 'Print one machine-readable result line on stdout instead of the human message (same exit codes)'
            Flag '-s','--scope' 'Installation scope: user, project, local (default: auto-detect)' -Arg 'scope' -Values 'user','project','local'
            Pos 'plugin' -Completer InstalledPlugins
        }
        Sub 'update' 'Update a plugin to the latest version (restart required to apply)' {
            Flag '--accept-command' 'Accept the marketplace-declared command (a command-source install, or the headersHelper fetching the archive) whose sha256 a previous --json run reported as shownCommand.sha256; only covers that exact command for that plugin/marketplace' -Arg 'sha256'
            Flag '-h','--help' 'Display help'
            Flag '--json' 'Print one machine-readable result line on stdout instead of the human message (same exit codes; a marketplace-declared command is still shown and must be confirmed - pass -y when not interactive)'
            Flag '-s','--scope' 'Installation scope: user, project, local, managed (default: user)' -Arg 'scope' -Values 'user','project','local','managed'
            Flag '-y','--yes' 'Accept the displayed marketplace-declared command without the confirmation prompt - a changed install command, or the headersHelper command that fetches its archive (required when stdin or stdout is not a TTY)'
            Pos 'plugin' -Completer InstalledPlugins
        }
        Sub 'list' 'List installed plugins' {
            Flag '--available' 'Include available plugins from marketplaces (requires --json)'
            Flag '--data-size' 'Measure each installed plugin''s saved data directory, or only the named plugin''s (requires --json)' -Arg 'plugin' -Optional -Completer InstalledPlugins
            Flag '-h','--help' 'Display help'
            Flag '--json' 'Output as JSON'
        }
        Sub 'help' 'Display help for command' { }
    }
    Sub 'project' 'Deprecated - `claude project purge` is now `claude purge`' {
        Sub 'purge' 'Deprecated alias for `claude purge`' {
            Flag '--all' 'Purge state for every project (mutually exclusive with [path])'
            Flag '--dry-run' 'List what would be deleted without deleting anything'
            Flag '-h','--help' 'Display help'
            Flag '-i','--interactive' 'Prompt for each item before deleting'
            Flag '-y','--yes' 'Skip confirmation prompt'
            Pos 'path' -Completer Directory
        }
        Flag '-h','--help' 'Display help for command'
        Sub 'help' 'Display help for command' { }
    }
    Sub 'purge' 'Delete all Claude Code state for a project (transcripts, tasks, file history, config entry)' {
        Flag '--all' 'Purge state for every project (mutually exclusive with [path])'
        Flag '--dry-run' 'List what would be deleted without deleting anything'
        Flag '-h','--help' 'Display help for command'
        Flag '-i','--interactive' 'Prompt for each item before deleting'
        Flag '-y','--yes' 'Skip confirmation prompt'
        Pos 'path' -Completer Directory
    }
    Sub 'daemon' 'Manage the background session supervisor' {
        Flag '-h','--help' 'Show this help'
        Flag '--json-path' 'Config file (default: ~/.claude/daemon.json)' -Arg 'path' -Completer File
        Flag '--log-file' 'Log file (default: ~/.claude/daemon.log)' -Arg 'path' -Completer File
        Sub 'run' 'Run the supervisor in the foreground (default when piped)' {
            Flag '-h','--help' 'Display help'
            Flag '--json-path' 'Config file (default: ~/.claude/daemon.json)' -Arg 'path' -Completer File
            Flag '--log-file' 'Log file (default: ~/.claude/daemon.log)' -Arg 'path' -Completer File
            Pos 'json-path' -Completer File
        }
        Sub 'stop' 'Shut down the supervisor and terminate background sessions' {
            Flag '--any' 'Also stop a transient (non-service) daemon'
            Flag '-h','--help' 'Display help'
            Flag '--json-path' 'Config file (default: ~/.claude/daemon.json)' -Arg 'path' -Completer File
            Flag '--keep-workers' 'Leave detached sessions running'
            Flag '--log-file' 'Log file (default: ~/.claude/daemon.log)' -Arg 'path' -Completer File
        }
        Sub 'status','logs','uninstall' 'Show daemon pid, version, uptime','Tail the daemon log (Ctrl-C to stop)','Remove the background service (launchctl/systemd)' {
            Flag '-h','--help' 'Display help'
            Flag '--json-path' 'Config file (default: ~/.claude/daemon.json)' -Arg 'path' -Completer File
            Flag '--log-file' 'Log file (default: ~/.claude/daemon.log)' -Arg 'path' -Completer File
        }
    }
    Sub 'self-hosted-runner' 'Start a runner process that hosts Claude Code cloud sessions on your infrastructure' -SubsFirstOnly {
        # setup, doctor and orchestrator are only recognized as the first word;
        # with anything else there (or nothing), the options belong to the runner.
        Sub 'orchestrator' 'Poll the spawn-hints queue and run the spawn-runner hook once per hint' {
            Flag '--agent-proxy-url' 'Agent proxy for the runners the spawn-runner hook starts (passed to the hook as SELF_HOSTED_RUNNER_AGENT_PROXY_URL)' -Arg 'url'
            Flag '--api-url' 'API base URL (default: https://api.anthropic.com)' -Arg 'url'
            Flag '--debug-dir' 'DEV ONLY — writes each work-order JWT + decoded JSON + hook stderr to <dir>/<jti>.{jwt,json,stderr}' -Arg 'path' -Completer Directory
            Flag '--environment-secret-file' 'Path to environment secret file (or set SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET)' -Arg 'path' -Completer File
            Flag '--expected-spawn-seconds' 'p99 boot time for runners this orchestrator spawns (default: 120)' -Arg 'n'
            Flag '--health-port' 'Port for /healthz HTTP listener (default: 8080). 0 disables' -Arg 'port'
            Flag '-h','--help' 'Show this help message'
            Flag '--hook-concurrency' 'Max spawn-runner hooks running in parallel (default: 4)' -Arg 'n'
            Flag '--hook-timeout' 'SIGTERM the hook after <sec> seconds (default: 60)' -Arg 'sec'
            Flag '--hooks-dir' 'Directory containing the spawn-runner hook (REQUIRED)' -Arg 'path' -Completer Directory
            Flag '--log-level' 'Log level: info or debug (default: info)' -Arg 'level' -Values 'info','debug'
            Flag '--min-idle' 'Keep at least <n> idle slots free (free capacity across runners, not runner count; default: 0, disabled)' -Arg 'n'
            Flag '--scm-connector-ca-file' 'Extra CA bundle (PEM) for TLS to the GHES host' -Arg 'path' -Completer File
            Flag '--scm-connector-host' 'GHES hostname to forward to (port defaults to 443). Setting this enables the connector' -Arg 'host'
            Flag '--scm-connector-host-rewrite' 'e2e only — redirect the TCP connect while keeping Host/SNI as --scm-connector-host' -Arg 'from=to_host:to_port'
            Flag '--scm-connector-id' 'ghe_configurations.id for this org (REQUIRED with --scm-connector-host)' -Arg 'n'
            Flag '--scm-connector-provider' 'Provider slug (default: ghe)' -Arg 'provider'
            Flag '--shutdown-drain-sec' 'On SIGTERM, stop polling but give the poll in flight and the running hooks up to <n> seconds to end (default: 0)' -Arg 'n'
        }
        Sub 'setup','doctor' 'Interactive wizard: walks you from zero to a working self-hosted runner environment','Interactive wizard: diagnoses a self-hosted runner deployment' {
            Flag '-h','--help' 'Show this help message'
            # Extra args are passed to the underlying Claude Code session.
            Pos 'args' -Rest
        }
        Flag '--agent-proxy-url' 'Route every session this runner runs through the agent proxy at <url> (https:// only)' -Arg 'url'
        Flag '--api-url' 'API base URL (default: https://api.anthropic.com)' -Arg 'url'
        Flag '--base-dir' 'Base directory for repo checkouts (default: /workspace; required on Windows, which has no default)' -Arg 'path' -Completer Directory
        Flag '--capacity' 'Max concurrent sessions (default: 1)' -Arg 'n'
        Flag '--checkout-hook-timeout-min' 'Wall-clock budget for each run of the checkout lifecycle hook. Default: 30. 0 disables' -Arg 'n'
        Flag '--client-label' 'Observability label sent at registration (default: hostname)' -Arg 'label'
        Flag '--configure-git' 'Set global git identity to Claude <noreply@anthropic.com> and enable commit signing via Anthropic''s signing service, matching 1P sessions'
        Flag '--confine-repo-settings' 'Repo-committed-settings confine guard mode: warn (default), enforce or off' -Arg 'mode' -Values 'warn','enforce','off'
        Flag '--debug-token-dir' 'DEBUG ONLY — writes live tokens to disk. Do not use in production' -Arg 'path' -Completer Directory
        Flag '--defer-shutdown-max-min' 'On the first SIGTERM/SIGINT, stop taking new work and finish shutting down M minutes later instead of draining' -Arg 'm'
        Flag '--diff-finds-nested-repository' 'Let the web session''s Changes pane show a repository cloned into a sub-folder of a no-repository session''s working folder (requires --capacity 1). Default: false' -Arg 'bool' -Optional -Values 'true','false'
        Flag '--drain-grace-sec' 'Keep the runner warm and re-poll the locked account''s queue for that many seconds before exiting (default: 0)' -Arg 'n'
        Flag '--drain-marker-file' 'Marker file a host writes to announce a graceful drain before sending SIGTERM (telemetry only)' -Arg 'path' -Completer File
        Flag '--drain-wait-sec' 'On SIGTERM/SIGINT, wait up to N seconds for each session''s in-flight turn and running background tasks to finish' -Arg 'n'
        Flag '--environment-secret-file' 'Path to environment secret file (or set SELF_HOSTED_RUNNER_ENVIRONMENT_SECRET)' -Arg 'path' -Completer File
        Flag '--exec-path' 'Binary to spawn for child sessions. Default: this process''s own binary' -Arg 'path' -Completer File
        Flag '--exit-if-unused-min' 'Exit the runner if never assigned work for N min (autoscaler scale-down)' -Arg 'n'
        Flag '--git-host-rewrite' 'Rewrite https://<f>/... source URLs to https://<t>/... (repeatable)' -Arg 'from=to' -Repeat
        Flag '--git-ssh-rewrite' 'Rewrite https://<host>/... source URLs to git@<host>:... (repeatable)' -Arg 'host' -Repeat
        Flag '--health-port' 'Port for /healthz HTTP listener (default: 8080). 0 disables' -Arg 'port'
        Flag '-h','--help' 'Show this help message'
        Flag '--hooks-dir' 'Directory of lifecycle hook scripts (checkout, command, post-session)' -Arg 'path' -Completer Directory
        Flag '--host-config-snapshot' 'Where the startup snapshot of the host config directory is held (default: disk)' -Arg 'mode' -Values 'disk','memory'
        Flag '--kill-session-after-min' 'Cap a session child''s wall-clock life at N min (runaway backstop)' -Arg 'n'
        Flag '--lock-to-account' 'Lock runner to a single account at registration (webhook-driven on-demand spawn)' -Arg 'id'
        Flag '--log-file' 'Tee runner logs to a file in append mode. Stdout is unchanged' -Arg 'path' -Completer File
        Flag '--log-level' 'Log level: info or debug (default: info)' -Arg 'level' -Values 'info','debug'
        Flag '--post-session-hook-timeout-sec' 'SIGTERM budget for the post-session lifecycle hook, on every session end including runner shutdown. Default: 60' -Arg 'n'
        Flag '--proxy-authorization-command' 'Shell command whose stdout is the Proxy-Authorization header value, run afresh for each new connection to the egress proxy' -Arg 'shell command'
        Flag '--proxy-authorization-file' 'Same as --proxy-authorization-command, but the header value is read from a file' -Arg 'path' -Completer File
        Flag '--push-outcome-on-release' 'On a runner-initiated non-completed session end, push every tracked outcome branch to origin before deleting it'
        Flag '--release-idle-session-min' 'Release a session slot after N min of no user input' -Arg 'n'
        Flag '--remove-session-state' 'Remove a session''s per-session state under <base-dir>/_sessions/ when it ends on this runner. Default: false' -Arg 'bool' -Optional -Values 'true','false'
        Flag '--retire-at' 'Retire the runner at the given wall-clock time (absolute Unix timestamp, in seconds)' -Arg 'epoch-seconds'
        Flag '--server-auto-mode-lists' 'Which of the server''s auto mode classifier lists a session may receive in its launcher settings: all, no-allow (default) or none' -Arg 'mode' -Values 'all','no-allow','none'
        Flag '--session-stop-grace-sec' 'How long to wait for the Claude process to exit cleanly after a session ends, before force-killing it. Default: 5' -Arg 'n'
        Flag '--startup-timeout-min' 'Release a session slot if the child has not completed initialization N min after spawn. Default: 15. 0 disables' -Arg 'n'
        Flag '--trust-workspace' 'Seed persisted trust for each session''s repo paths so repo-level .claude/settings.json grants are honored by the child. Default: true' -Arg 'bool' -Optional -Values 'true','false'
        Flag '--use-anthropic-git-proxy' 'Opt this runner into Anthropic-managed git. WARNING: deletes and replaces the HOME-level git config of the account running the runner'
    }
    Sub 'auto-mode' 'Inspect auto mode classifier configuration' {
        Flag '-h','--help' 'Display help for command'
        Sub 'critique' 'Get AI feedback on your custom auto mode rules' {
            Flag '-h','--help' 'Display help'
            Flag '--model' 'Override which model is used' -Arg 'model' -Completer Models
        }
        Sub 'reset' 'Reset auto mode configuration to the shipped defaults by removing the autoMode section from your user settings file' {
            Flag '-h','--help' 'Display help'
            Flag '-y','--yes' 'Skip the confirmation prompt'
        }
        Sub 'config' 'Print the effective auto mode config as JSON: your settings where set, defaults otherwise' {
            Flag '-h','--help' 'Display help'
        }
        Sub 'defaults' 'Print the default auto mode environment, allow, soft_deny, and hard_deny rules as JSON' {
            Flag '-h','--help' 'Display help'
            Flag '--label' 'Show only rules whose label starts with this prefix (case-insensitive)' -Arg 'prefix'
        }
        Sub 'help' 'Display help for command' { }
    }
    Sub 'install' 'Install Claude Code native build. Use [target] to specify version (stable, latest, or specific version)' {
        Flag '--force' 'Force installation even if already installed'
        Flag '-h','--help' 'Display help'
        Pos 'target' -Values 'stable','latest'
    }
    Sub 'import' 'Import config from another AI coding agent into Claude Code' {
        Flag '--dry-run' 'Show what would be imported without writing anything'
        Flag '-h','--help' 'Display help'
        Flag '--yes' 'Skip the interactive picker. On headless surfaces, pass --yes=<digest> from the /import preview'
        Pos 'source' -Values 'codex','gemini','cursor'
    }
    Sub 'remote-control' 'Connect your local environment to claude.ai/code' {
        Flag '--capacity' 'Max concurrent sessions in worktree or same-dir mode (default: 32)' -Arg 'n'
        Flag '-c','--continue' 'Resume the last Remote Control session in this directory' -Excludes '--session-id'
        Flag '--create-session-in-dir' 'Pre-create a session in the current directory when the server starts (default: on)'
        Flag '--no-create-session-in-dir' 'Skip pre-creating a session in the current directory'
        Flag '--debug-file' 'Write debug logs to a specific file path' -Arg 'path' -Completer File
        Flag '-h','--help' 'Display help'
        Flag '--name' 'Name for the session (shown in claude.ai/code)' -Arg 'name'
        Flag '--no-sandbox' 'Disable sandboxing'
        Flag '--permission-mode' 'Permission mode for spawned sessions' -Arg 'mode' -Values 'acceptEdits','auto','bypassPermissions','manual','dontAsk','plan'
        Flag '--remote-control-session-name-prefix' 'Prefix for auto-generated session names (default: hostname)' -Arg 'prefix'
        Flag '--sandbox' 'Enable sandboxing for filesystem and network isolation'
        Flag '--session-id' 'Resume a specific Remote Control session by ID (cannot be used with spawn flags or --continue)' -Arg 'id' -Excludes '-c','--continue'
        Flag '--spawn' 'Spawn mode for on-demand sessions (default: same-dir)' -Arg 'mode' -Values 'same-dir','worktree','session'
        Flag '-v','--verbose' 'Show detailed connection and session logs'
    }
    Sub 'gateway' 'Run the enterprise auth/telemetry gateway' {
        Flag '--config' 'Path to gateway YAML config' -Arg 'path' -Completer File
        Flag '-h','--help' 'Display help'
    }
    Sub 'ultrareview' 'Run a cloud-hosted multi-agent code review of the current branch (or a PR number / base branch) and print the findings' {
        Flag '-h','--help' 'Display help'
        Flag '--json' 'Print the raw bugs.json payload instead of formatted findings'
        Flag '--no-post' 'Do not post the findings to the PR (the default; accepted for parity with the /ultrareview and /code-review ultra flags)' -Excludes '--post'
        Flag '--post' 'Post the finished review''s findings to the PR as you (PR targets only; one plain comment, not a review)' -Excludes '--no-post'
        Flag '--timeout' 'Maximum minutes to wait for the review to finish (default: 45)' -Arg 'minutes'
        Flag '--trust-workspace' 'Trust the current folder for this run only, without asking (for scripts and CI)'
        Pos 'target'
    }
    Sub 'setup-token','doctor','update','upgrade' 'Set up a long-lived authentication token (requires Claude subscription)','Check the health of your Claude Code installation','Check for updates and install if available','Check for updates and install if available' {
        Flag '-h','--help' 'Display help'
    }

    # Global flags. Offered only while no command has been typed.
    Flag '--add-dir' 'Additional directories to allow tool access to' -Arg 'directory' -Completer Directory -Repeat
    Flag '--advisor' 'Enable a server-side advisor tool using the specified model' -Arg 'model' -Values 'fable','opus','sonnet'
    Flag '--agent' 'Agent for the current session. Overrides the agent setting' -Arg 'agent' -Completer Agents
    Flag '--agents' 'JSON object defining custom agents' -Arg 'json'
    Flag '--allow-dangerously-skip-permissions' 'Enable bypassing all permission checks as an option, without it being enabled by default. Recommended only for sandboxes with no internet access'
    Flag '--allowedTools' 'Comma or space-separated list of tool names to allow (e.g. "Bash(git:*) Edit")' -Arg 'tools' -Repeat
    Flag '--allowed-tools' 'Comma or space-separated list of tool names to allow (e.g. "Bash(git:*) Edit")' -Arg 'tools' -Repeat
    Flag '--append-subagent-system-prompt' 'Append a system prompt to every Task-tool subagent''s system prompt, propagated to nested subagents (only works with --print)' -Arg 'prompt'
    Flag '--append-subagent-system-prompt-file' 'Read a system prompt from a file and append it to every Task-tool subagent''s system prompt (only works with --print)' -Arg 'file' -Completer File
    Flag '--append-system-prompt' 'Append a system prompt to the default system prompt' -Arg 'prompt'
    Flag '--append-system-prompt-file' 'Append a system prompt from a file to the default system prompt' -Arg 'file' -Completer File
    Flag '--autocompact' 'Auto-compact window size (auto, or 100k-1M tokens)' -Arg 'size'
    Flag '--ax-screen-reader' 'Render screen-reader friendly output (flat text, no decorative borders or animations)'
    Flag '--bare' 'Minimal mode: skip hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, keychain reads, and CLAUDE.md auto-discovery. Sets CLAUDE_CODE_SIMPLE=1'
    Flag '--bg','--background' 'Start the session as a background agent and return immediately (manage with `claude agents`)'
    Flag '--betas' 'Beta headers to include in API requests (API key users only)' -Arg 'betas' -Repeat
    Flag '--brief' 'Enable SendUserMessage tool for agent-to-user communication'
    Flag '--channels' 'MCP servers to listen for channel notifications (e.g. plugin:<name>@<marketplace> or server:<name>)' -Arg 'server' -Repeat
    Flag '--chrome' 'Enable Claude in Chrome integration'
    Flag '--client-data-url' 'URL for a signed configuration document. Claude Code exits if it cannot load it or it does not cover the selected model' -Arg 'url'
    Flag '--cloud','--remote' 'Create a cloud session with the given description, or attach to an existing one by session ID or claude.ai/code URL (--remote is a deprecated alias)' -Arg 'description' -Optional
    Flag '-c','--continue' 'Continue the most recent conversation in the current directory'
    Flag '--dangerously-load-development-channels' 'Bypass the channel plugin allowlist for local testing' -Arg 'server' -Repeat
    Flag '--dangerously-skip-permissions' 'Bypass all permission checks. Recommended only for sandboxes with no internet access'
    Flag '-d','--debug' 'Enable debug mode with optional category filtering (e.g., "api,hooks" or "!1p,!file")' -Arg 'filter' -Optional
    Flag '--debug-file' 'Write debug logs to a specific file path (implicitly enables debug mode)' -Arg 'path' -Completer File
    Flag '--desktop' 'Open in the Claude Desktop app instead of the terminal (with --continue or --resume <id> to pick the session)'
    Flag '--disable-slash-commands' 'Disable all skills'
    Flag '--disallowedTools' 'Comma or space-separated list of tool names to deny (e.g. "Bash(git:*) Edit")' -Arg 'tools' -Repeat
    Flag '--disallowed-tools' 'Comma or space-separated list of tool names to deny (e.g. "Bash(git:*) Edit")' -Arg 'tools' -Repeat
    Flag '--effort' 'Effort level for the current session (low, medium, high, xhigh, max)' -Arg 'level' -Values 'low','medium','high','xhigh','max','ultracode'
    Flag '--environment' 'Create a new cloud session that runs on the given self-hosted environment (ccpool_...)' -Arg 'environment_id'
    Flag '--exclude-dynamic-system-prompt-sections' 'Move per-machine sections (cwd, env info, memory paths, git status) from the system prompt into the first user message. Improves cross-user prompt-cache reuse. Only applies with the default system prompt (ignored with --system-prompt)'
    Flag '--exec' 'Run a shell command as a background job instead of a Claude session (requires --bg)' -Arg 'command'
    Flag '--fallback-model' 'Enable automatic fallback to specified model(s) when default model is overloaded or not available. Accepts a comma-separated list to try each in order. Re-tries the primary at the start of each user turn (only works with --print)' -Arg 'model' -Completer Models -Separator ','
    Flag '--file' 'File resources to download at startup. Format: file_id:relative_path (e.g., --file file_abc:doc.txt file_def:img.png)' -Arg 'file' -Repeat
    Flag '--fork-session' 'When resuming, create a new session ID instead of reusing the original (use with --resume or --continue)'
    Flag '--forward-subagent-text' 'Forward subagent text and thinking blocks as assistant/user messages with parent_tool_use_id set (only works with --print and --output-format=stream-json)'
    Flag '--from-pr' 'Resume a session linked to a PR by PR number/URL, or open interactive picker with optional search term' -Arg 'value' -Optional
    Flag '-h','--help' 'Display help for command'
    Flag '--ide' 'Automatically connect to IDE on startup if exactly one valid IDE is available'
    Flag '--include-hook-events' 'Include all hook lifecycle events in the output stream (only works with --output-format=stream-json)'
    Flag '--include-partial-messages' 'Include partial message chunks as they arrive (only works with --print and --output-format=stream-json)'
    Flag '--init' 'Run Setup hooks with the init matcher before starting the session'
    Flag '--init-only' 'Run Setup hooks with the init matcher, then exit'
    Flag '--input-format' 'Input format (only works with --print): "text" (default), or "stream-json" (realtime streaming input)' -Arg 'format' -Values 'text','stream-json'
    Flag '--json-schema' 'JSON Schema for structured output validation. Example: {"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}' -Arg 'schema'
    Flag '--maintenance' 'Run Setup hooks with the maintenance matcher, then continue'
    Flag '--max-budget-usd' 'Maximum dollar amount to spend on API calls (only works with --print)' -Arg 'amount'
    Flag '--max-turns' 'Limit the number of agentic turns (only works with --print)' -Arg 'turns'
    Flag '--mcp-config' 'Load MCP servers from JSON files or strings (space-separated)' -Arg 'config' -Completer File -Repeat
    Flag '--model' 'Model for the current session. Provide an alias for the latest model (e.g. ''fable'', ''opus'', or ''sonnet'') or a model''s full name (e.g. ''claude-fable-5'')' -Arg 'model' -Completer Models
    Flag '-n','--name' 'Set a display name for this session (shown in the prompt box, /resume picker, and terminal title)' -Arg 'name'
    Flag '--no-chrome' 'Disable Claude in Chrome integration'
    Flag '--no-session-persistence' 'Disable session persistence - sessions will not be saved to disk and cannot be resumed (only works with --print)'
    Flag '--output-format' 'Output format (only works with --print): "text" (default), "json" (single result), or "stream-json" (realtime streaming)' -Arg 'format' -Values 'text','json','stream-json'
    Flag '--permission-mode' 'Permission mode to use for the session' -Arg 'mode' -Values 'acceptEdits','auto','bypassPermissions','manual','dontAsk','plan'
    Flag '--permission-prompt-tool' 'MCP tool name to handle permission prompts (only works with --print)' -Arg 'tool'
    Flag '--permission-prompts' 'Who answers permission prompts with --print: host (the SDK host or --permission-prompt-tool) or none (deny automatically)' -Arg 'target' -Values 'host','none'
    Flag '--plugin-dir' 'Load a plugin from a directory or .zip for this session only (repeatable: --plugin-dir A --plugin-dir B.zip)' -Arg 'directory' -Completer Directory -Repeat
    Flag '--plugin-url' 'Fetch a plugin .zip from a URL for this session only (repeatable: --plugin-url A --plugin-url B)' -Arg 'url' -Repeat
    Flag '-p','--print' 'Print response and exit (useful for pipes). Note: The workspace trust dialog is skipped when Claude is run in non-interactive mode. Only use this in directories you trust'
    Flag '--prompt-suggestions' 'Enable prompt suggestions. In print/SDK mode, emits a prompt_suggestion message after each turn with a predicted next user prompt' -Arg 'value' -Optional -Values 'true','false','1','0','yes','no','on','off'
    Flag '--ref' 'Branch, tag, or SHA to check out in the remote session; defaults to local current branch (requires --cloud or --environment)' -Arg 'ref'
    Flag '--remote-control','--rc' 'Start an interactive session with Remote Control enabled (optionally named)' -Arg 'name' -Optional
    Flag '--remote-control-session-name-prefix' 'Prefix for auto-generated Remote Control session names (default: hostname)' -Arg 'prefix'
    Flag '--replay-user-messages' 'Re-emit user messages from stdin back on stdout for acknowledgment (only works with --input-format=stream-json and --output-format=stream-json)'
    Flag '--restricted' 'Restricted mode: removes the built-in tools that run commands or code (Bash, PowerShell, REPL and the other code-running tools) and WebFetch unless --tools names them, and ignores user, project and local settings files (managed settings and --settings still apply; add --strict-mcp-config to skip MCP servers too). Also confines the file tools to the working directories (--add-dir included), refuses bypassPermissions, and lets only a person or the configured permission handler approve writes to settings, git and tool-configuration files'
    Flag '-r','--resume' 'Resume a conversation by session ID, or open interactive picker with optional search term' -Arg 'session' -Optional -Completer Sessions
    Flag '--safe-mode' 'Start with all customizations disabled — useful for troubleshooting a broken configuration. Admin-managed settings still apply. Sets CLAUDE_CODE_SAFE_MODE=1'
    Flag '--session-id' 'Use a specific session ID for the conversation (must be a valid UUID)' -Arg 'uuid'
    Flag '--setting-sources' 'Comma-separated list of setting sources to load (user, project, local)' -Arg 'sources' -Values 'user','project','local' -Separator ','
    Flag '--settings' 'Path to a settings JSON file or a JSON string to load additional settings from' -Arg 'file' -Completer File
    Flag '--strict-mcp-config' 'Only use MCP servers from --mcp-config, ignoring all other MCP configurations'
    Flag '--system-prompt' 'System prompt to use for the session' -Arg 'prompt'
    Flag '--system-prompt-file' 'Read system prompt from a file' -Arg 'file' -Completer File
    Flag '--system-prompt-snapshot' 'Record the system prompt once per conversation and reuse it verbatim on every request and resume' -Arg 'mode' -Values 'on','off'
    Flag '--teammate-mode' 'Set agent team display mode' -Arg 'mode' -Values 'auto','tmux','iterm2','in-process'
    Flag '--teleport' 'Resume a cloud session in the local terminal, or open an interactive picker with optional session ID' -Arg 'session-id' -Optional
    Flag '--tmux' 'Create a tmux session for the worktree (requires --worktree). Uses iTerm2 native panes when available; use --tmux=classic for traditional tmux' -Arg 'style' -Optional -Values 'classic'
    Flag '--tools' 'Specify the list of available tools from the built-in set. Use "" to disable all tools, "default" to use all tools, or specify tool names (e.g. "Bash,Edit,Read")' -Arg 'tools' -Repeat
    Flag '--verbose' 'Override verbose mode setting from config'
    Flag '-v','--version' 'Output the version number'
    Flag '-w','--worktree' 'Create a new git worktree for this session (optionally specify a name)' -Arg 'name' -Optional
    Pos 'prompt' -Rest
}
