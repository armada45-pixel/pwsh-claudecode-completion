# pwsh-claudecode-completion

Tab completion for the [Claude Code](https://github.com/anthropics/claude-code) CLI (`claude`) in PowerShell 7.

It is a native PowerShell port of [zsh-claudecode-completion](https://github.com/wbingli/zsh-claudecode-completion): the same commands, flags and values, and the same rules. Completion only: no aliases, no wrapper functions, no workflow.

Matches Claude Code **2.1.309** (see [`claude-version`](claude-version)).

## What it completes

```powershell
claude <Tab>                          # commands, with descriptions
claude --<Tab>                        # global flags
claude mcp <Tab>                      # subcommands, at every level
claude plugin marketplace add --<Tab> # flags of that subcommand
claude --model <Tab>                  # model aliases
claude --effort <Tab>                 # low medium high xhigh max ultracode
claude --permission-mode <Tab>        # acceptEdits auto bypassPermissions ...
claude --setting-sources user,<Tab>   # the sources not in the list yet
claude --resume <Tab>                 # sessions of this project, newest first
claude --agent <Tab>                  # your own, plugin and built-in agents
claude mcp get <Tab>                  # configured MCP servers
claude plugin enable <Tab>            # installed plugins
claude plugin install <Tab>           # plugins from your marketplaces
claude plugin marketplace update <Tab> # marketplaces
claude attach <Tab>                   # background sessions
claude --add-dir <Tab>                # directories
claude --settings <Tab>               # files
```

With `MenuComplete`, a list that fits the window is shown the way zsh shows it, one item per line with its description:

```
> claude mcp <Tab>
add                      -- Add an MCP server to Claude Code
add-from-claude-desktop  -- Import MCP servers from Claude Desktop (Mac and WSL only)
add-json                 -- Add an MCP server (stdio, SSE, HTTP, or WebSocket) with a JSON string
get                      -- Get details about an MCP server
...
```

A list too long for the window (`claude --<Tab>`) stays a grid of names, because PSReadLine does not page its menu. Every result also carries its description as the tooltip, shown under the menu for the selected item.

## Install

Needs PowerShell 7.2 or newer on Windows, Linux or macOS. Windows PowerShell 5.1 is not supported.

Clone the repository into your module path and import it from your profile:

```powershell
$modules = ($env:PSModulePath -split [IO.Path]::PathSeparator)[0]
git clone https://github.com/armada45-pixel/pwsh-claudecode-completion (Join-Path $modules 'pwsh-claudecode-completion')
Add-Content $PROFILE "`nImport-Module pwsh-claudecode-completion"
```

Or clone it anywhere and import it by path:

```powershell
Add-Content $PROFILE "`nImport-Module C:\path\to\pwsh-claudecode-completion"
```

Open a new PowerShell window, type `claude ` and press Tab.

Importing the module adds about 50 ms to the start of a shell. The command table is only loaded on the first Tab for `claude`.

### Recommended PSReadLine settings

Add these to your `$PROFILE` as well:

```powershell
# Tab opens a menu you can move through with the arrow keys; the
# description of the selected item is shown below it.
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

# Show predictions as a list instead of inline.
Set-PSReadLineOption -PredictionViewStyle ListView
```

`MenuComplete` is what shows the descriptions. The ListView shows predictions, which come from your history unless a predictor plugin adds more.

## Where the dynamic values come from

They are read from Claude's own files. Completion never runs `claude` and never uses the network.

| Value | Read from |
| --- | --- |
| Sessions (`--resume`, `-r`) | `<config>/projects/<project folder>/*.jsonl` and `sessions-index.json` |
| Background sessions (`attach`, `logs`, `stop`, `kill`, `respawn`, `rm`) | `<config>/jobs/<id>/state.json` |
| Agents (`--agent`) | `.claude/agents/` from the working directory up to the repository root, `<config>/agents/`, the agents of installed plugins, and the built-in agents |
| MCP servers (`mcp get`, `remove`, `login`, `logout`) | `~/.claude.json` (user and local scope) and `.mcp.json` (project scope) |
| Installed plugins | `<config>/plugins/installed_plugins.json` |
| Marketplaces | `<config>/plugins/known_marketplaces.json` |
| Installable plugins (`plugin install`) | `<config>/plugins/marketplaces/*/.claude-plugin/marketplace.json` |

`<config>` is `~/.claude`.

- A missing, empty or malformed file means "no matches". Nothing is printed into the prompt.
- Control characters are stripped from everything read from a file before it is shown.
- The query string of an MCP server or marketplace URL is not shown, since it can hold a token.

### Environment variables

| Variable | Effect |
| --- | --- |
| `CLAUDE_CONFIG_DIR` | Used instead of `~/.claude`. `.claude.json` is then read from inside it. |
| `CLAUDE_CODE_PLUGIN_CACHE_DIR` | Used instead of `<config>/plugins`. |
| `CLAUDE_COMPLETION_SESSION_LIMIT` | How many sessions `--resume` offers. Default 20; 0 or less means no limit. |
| `CLAUDE_COMPLETION_DESCRIPTIONS` | Set to `tooltip` to list plain names only; descriptions are then shown just as the tooltip. |

### Sessions

`claude --resume <Tab>` lists the sessions started in the current directory. The menu shows the start of each id and its title; the tooltip adds age, branch and size, as `/resume` does:

```
3 hours ago · main · 1.2MB - Fix the login redirect
```

The title is the `/rename` title, else the generated title, else the first user message. Only the start and the end of each session file are read, and results are cached until the file changes: 400 session files take about 50 ms on the first Tab.

### Windows notes

- Claude names a project folder by replacing every character of the path other than `a-z`, `A-Z` and `0-9` with `-`. `C:\Users\me\repo` is stored in `projects\C--Users-me-repo`.
- `.claude.json` is at `%USERPROFILE%\.claude.json`.
- Its `projects` keys have been written both as `C:\Users\me\repo` and as `C:/Users/me/repo`, so they are compared as paths, without case.

## Differences from the zsh plugin

- No `jq` needed. JSON is read with .NET.
- Values match without regard to case (`--agent exp` completes `Explore`). Flags match exactly, because `-h` and `-H` differ.
- A value PowerShell would not pass on as one word is quoted: `'sonnet[1m]'`.
- In a comma-separated list (`--setting-sources`, `--fallback-model`) the comma is not added for you. Type it and press Tab again for the remaining values.
- Where a position takes free text (a prompt, a new server name) and the word is still empty, the flags of the command are listed.
- An optional value with nothing to offer, such as `--resume` in a directory without sessions, goes on to the commands and flags that can follow.
- When there is no match at all for a required value, PowerShell falls back to file names. A completer cannot turn that off.
- Sessions follow `CLAUDE_CONFIG_DIR`. The zsh plugin always reads them from `~/.claude`.
- `--resume`, `--debug`, `--from-pr` and `--prompt-suggestions` take an optional value, as `claude --help` says. So `claude --debug mcp <Tab>` completes the `mcp` subcommands.
- A few flags from `claude --help` 2.1.309 that `_claude` does not have: `--json` for `plugin marketplace add|remove|update`, and `--help` on the command groups.

## Development

```
pwsh-claudecode-completion.psd1   manifest
pwsh-claudecode-completion.psm1   loads src/ and registers the completer
src/Spec.ps1                      the command tree: commands, flags, values, descriptions
src/Engine.ps1                    walks the typed words through the tree, builds the results
src/Paths.ps1                     config directory, project directories, safe file and JSON reading
src/Models.ps1  Sessions.ps1  BackgroundSessions.ps1  McpServers.ps1  Plugins.ps1  Agents.ps1
tests/*.Tests.ps1                 Pester tests, one file per feature
tools/Compare-ClaudeHelp.ps1      compares the tree with `claude --help`
```

Run the tests with [Pester](https://pester.dev) 5 or newer:

```powershell
Invoke-Pester ./tests
```

The tests drive completion through `CommandCompletion.CompleteInput`, the way PSReadLine does, with fixture directories under `TestDrive` that `CLAUDE_CONFIG_DIR` and `HOME` point to. They never read your real `~/.claude`.

### Updating to a new Claude Code version

1. Update `claude` and run `./tools/Compare-ClaudeHelp.ps1`. It lists flags and commands that `claude --help` has and the tree lacks, and the other way round.
2. Edit `src/Spec.ps1`. Flags listed as "only in tree" are mostly ones the CLI accepts without documenting them; keep them unless the CLI rejects them.
3. Put the new version in `claude-version` and run the tests.

### Things that have gone wrong before

- String searches must be ordinal: pass a `[char]` or a `StringComparison`. Under some cultures `'user,pro'.LastIndexOf(',')` is 8, not 4.
- `JsonElement.TryGetProperty` needs a typed `[ref]` variable, or PowerShell finds no overload.
- Completers must not throw or write errors. A caught exception still lands in `$Error`; the registered script block removes those again.

## License

[MIT](LICENSE). Command descriptions come from Claude Code's own help text by way of zsh-claudecode-completion.
