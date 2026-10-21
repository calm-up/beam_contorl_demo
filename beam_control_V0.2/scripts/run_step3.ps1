$ErrorActionPreference = 'Stop'

$workspacePath = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$aliasPath = 'D:\beam_fpga_workspace'
$vivadoPath = 'D:\Vivado\Vivado\2022.2\bin\vivado.bat'

if (-not (Test-Path -LiteralPath $vivadoPath)) {
    throw "Vivado 2022.2 was not found at $vivadoPath"
}

if (Test-Path -LiteralPath $aliasPath) {
    $aliasItem = Get-Item -LiteralPath $aliasPath -Force
    if ($aliasItem.LinkType -ne 'Junction' -or $aliasItem.Target -notcontains $workspacePath) {
        throw "The Vivado ASCII alias exists but points elsewhere: $aliasPath"
    }
} else {
    New-Item -ItemType Junction -Path $aliasPath -Target $workspacePath | Out-Null
}

Push-Location $aliasPath
try {
    & uv run python "$aliasPath\beam_control\scripts\generate_xdc.py"
    if ($LASTEXITCODE -ne 0) { throw 'XDC generation failed' }

    foreach ($script in @('create_project.tcl', 'run_sim.tcl', 'run_build.tcl')) {
        $sourcePath = "$aliasPath\beam_control\scripts\$script"
        & $vivadoPath -mode batch -source $sourcePath -nojournal -nolog
        if ($LASTEXITCODE -ne 0) { throw "Vivado failed while running $script" }
    }
} finally {
    Pop-Location
}

Write-Host 'STEP3_FLOW_COMPLETE. Review beam_control/reports/post_synth_drc.rpt; clock-pin DRC remains a hardware blocker until resolved.'
