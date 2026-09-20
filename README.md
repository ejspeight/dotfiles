# dotfiles

Setup scripts for a Mac dev environment and a locked-down Windows work laptop.
Pick what you install — nothing is all-or-nothing.

## Mac

```bash
cd mac
./setup.sh
```

Asks which modules you want. To skip the menu:

```bash
./setup.sh --terminal          # one module
./setup.sh --terminal --dev    # several
./setup.sh --all
./setup.sh --all --dry-run     # print what would happen, change nothing
```

Each module also runs on its own: `./modules/terminal.sh`

| Module | Installs |
|---|---|
| `terminal` | Ghostty, zsh with Oh My Zsh, Starship, Atuin, git, fzf, ripgrep, fd, bat, eza, zoxide, jq, tree, htop, wget, JetBrainsMono Nerd Font, and the shell config below |
| `dev` | Neovim with LazyVim, Node via nvm, Go, Python, Rust, gh, lazygit, git-flow, Docker, MySQL, Postgres, AWS CLI |
| `llm` | Ollama and the `llm` CLI, with a local model sized to the Mac's RAM |

**What to expect.** Any module installs Homebrew first if it is missing, so each
one works on a bare machine. Re-running is safe — installed packages are
skipped. Existing config is backed up to `~/.config-backups/dotfiles-<timestamp>/`
before replacement. Anything left for you to do by hand is printed as a numbered
list at the end.

GUI apps are not installed; `brew install --cask <app>` them as needed.

### Config files

Sources live in [`mac/config`](mac/config):

| File | Installed to |
|---|---|
| `zshrc` | `~/.zshrc` |
| `zprofile` | `~/.zprofile` |
| `starship.toml` | `~/.config/starship.toml` |
| `atuin.toml` | `~/.config/atuin/config.toml` |
| `ghostty/config.ghostty` | `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` |
| `ollama/Modelfile` | built into the `terminal-llm` Ollama model |

The shell config degrades on its own: `ls` and `cat` stay as the real commands
when `eza` and `bat` are absent, and SSH is untouched without 1Password.

## Windows (work machine)

For a managed corporate machine with no administrator rights, where the
toolchain is already installed and the friction is TLS inspection. Terminal only
— never languages, runtimes or SDKs.

`work-setup.ps1` is self-contained: it embeds its own PowerShell profile,
Starship config, Atuin config and Windows Terminal fragment, so it can be copied
to the machine on its own without cloning this repository.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\work-setup.ps1
```

Terminal only, with no certificate work and no model download:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\work-setup.ps1 -Terminal
```

Then open a **new** terminal and check it. Not `-NoProfile` — several checks
read what the profile defines:

```powershell
pwsh -File .\verify-work-setup.ps1
```

**What to expect.** Windows Terminal, PowerShell 7, Starship, Atuin, a Nerd Font,
Ollama, `uv` and `llm`, all installed per-user through WinGet's `winget` source,
falling back to the vendor's release archive in `~/.local/bin` where WinGet
cannot. The corporate root CA is detected and every tool that carries its own CA
bundle is pointed at it. TLS verification is never disabled. Safe to re-run;
existing files are backed up first.

### Switches

| Switch | Effect |
|---|---|
| `-Terminal` | Terminal and config only: no certificates, no local LLM |
| `-SkipInstalls` | Certificates and config only |
| `-SkipCerts` | Skip trust settings |
| `-SkipConfig` | Leave config files alone |
| `-SkipLlm` | Skip Ollama, `uv`, `llm` and the model |
| `-LlmModel` | Build `terminal-llm` from a different Ollama tag |
| `-ExtraCaSubject` | Extra root CA subject patterns for an in-house proxy |
| `-ProbeHost` | Hosts to TLS-probe when finding the inspecting root CA |
| `-RemoveCertEnv` | Remove the certificate variables and exit |

`verify-work-setup.ps1` takes `-Benchmark` and `-BenchmarkModel`.

### Certificates

Tools that read the Windows trust store inherit the corporate CA automatically.
Tools carrying their own CA bundle do not, which is why npm, Azure CLI and Mason
fail on an otherwise working machine. Bundles are written to `~/.config/certs/`.

| Variable | Bundle |
|---|---|
| `NODE_EXTRA_CA_CERTS` | corporate roots only (additive) |
| `REQUESTS_CA_BUNDLE`, `SSL_CERT_FILE`, `CURL_CA_BUNDLE`, `PIP_CERT` | full Windows store (replacing) |
| `UV_NATIVE_TLS` | the Windows store directly |

Git uses `http.sslBackend=schannel` and needs no bundle. Re-run after a CA
rotation, or roll back with `-RemoveCertEnv`.

### Local LLM

Runs entirely on the machine. No account, no cloud model, loopback only —
leave **Expose Ollama to the network** off in Ollama's settings.

```powershell
llm "explain what a git rebase does"
llm cmd show the current date        # suggests a command, asks before running
wtf                                  # reruns the last command, explains the failure
ollama ps                            # how much of the model is on the GPU
```

Model follows RAM, as on macOS: `gemma4:e4b` below 16GB, `gemma4:12b` below
32GB, `gemma4:26b` at 32GB or more. Override with `-LlmModel`.

Persistent user variables: `OLLAMA_HOST=127.0.0.1:11434`,
`OLLAMA_FLASH_ATTENTION=1`, `OLLAMA_KV_CACHE_TYPE=q8_0`, `OLLAMA_NUM_PARALLEL=1`,
`OLLAMA_MAX_LOADED_MODELS=1`.

### Troubleshooting

- **`ollama pull` fails immediately with `max retries exceeded: EOF`.** Ollama
  contacts `registry.ollama.ai`, then follows a signed URL to
  `*.r2.cloudflarestorage.com`. Both must be allowed. Changing the model size
  does not help when that redirect is blocked — ask IT to allow the Cloudflare
  R2 host category.
- **Prompt icons render as boxes.** WinGet's Nerd Font package is machine-scope
  and usually refused, so the script installs the font per-user under HKCU
  instead. Close every Windows Terminal window afterwards — a per-user font only
  reaches processes started after it was registered.
- **Documents redirected to OneDrive.** The profile is still written where
  `pwsh` reads it from, and the script says so.
- **`*.ps1` files are pure ASCII with a UTF-8 BOM on purpose.** Windows
  PowerShell 5.1 reads a BOM-less script as ANSI and corrupts every non-ASCII
  character it writes out. `.gitattributes` marks them `-text` so Git cannot
  undo it.
- **Docker builds are not covered.** A container has its own trust store, so an
  image fetching over TLS needs the CA copied in.
