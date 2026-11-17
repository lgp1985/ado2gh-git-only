$ErrorActionPreference = 'Stop'

& gh extension install github/gh-ado2gh --pin v1.35.0
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install github/gh-ado2gh v1.35.0 (exit code $LASTEXITCODE)."
}
