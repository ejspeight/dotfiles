# Keep portable tool configuration in the same paths used on macOS and Linux.
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship.toml'
$env:ATUIN_CONFIG_DIR = Join-Path $HOME '.config\atuin'

# Helpful, conservative command suggestions from local history.
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd

    try {
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle InlineView
    } catch {
        # Prediction options require a recent PSReadLine; the rest still works.
    }
}

# Atuin owns searchable history; Starship renders the prompt after it.
if (Get-Command atuin -ErrorAction SilentlyContinue) {
    atuin init powershell | Out-String | Invoke-Expression
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}
