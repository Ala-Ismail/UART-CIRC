# Keep the latest complete, verified source-matching set, including all suites.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'check_gate.ps1')
$gate = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'results/gate.json') -Raw | ConvertFrom-Json
if ($gate.status -ne 'PASS' -or $gate.passed_tests -ne $gate.required_tests) {
    throw 'Refusing cleanup without a complete passing simulation gate.'
}
$runRoot = (Resolve-Path -LiteralPath (Join-Path $repoRoot 'build/sim')).ProviderPath.TrimEnd('\')
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'build/sim')).TrimEnd('\')
if (-not $runRoot.Equals($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Simulation output root does not match the intended workspace directory.'
}
foreach ($directory in @((Split-Path -Parent $runRoot), $runRoot)) {
    if ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing cleanup through a directory link: $directory"
    }
}
$keep = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($run in ($gate.results.run | Sort-Object -Unique)) {
    $path = (Resolve-Path -LiteralPath (Join-Path $repoRoot $run)).ProviderPath
    if (-not (Split-Path -Parent $path).Equals($runRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Gate references an unexpected run directory: $path"
    }
    [void]$keep.Add($path)
}
$remove = @()
foreach ($directory in Get-ChildItem -LiteralPath $runRoot -Directory -Force) {
    $path = (Resolve-Path -LiteralPath $directory.FullName).ProviderPath
    if (-not (Split-Path -Parent $path).Equals($runRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing removal outside the simulation output root: $path"
    }
    if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing cleanup of a directory link: $path"
    }
    if (-not $keep.Contains($path)) {
        $links = Get-ChildItem -LiteralPath $path -Recurse -Force |
            Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }
        if ($links) { throw "Refusing cleanup of a run containing links: $path" }
        $remove += $path
    }
}
# All resolved targets were checked before the first deletion.
foreach ($path in $remove) {
    Remove-Item -LiteralPath $path -Recurse -Force
    Write-Host "Removed superseded run: $([IO.Path]::GetFileName($path))"
}
Write-Host "Kept $($keep.Count) run directories for the latest $($gate.passed_tests)-test verified set; removed $($remove.Count) older runs."
