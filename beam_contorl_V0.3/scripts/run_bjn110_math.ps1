param([string]$Python = 'C:\Users\LENOVO\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$out=Join-Path $root 'build\bjn110_math'
$vivado='D:\Vivado\Vivado\2022.2\bin'
New-Item -ItemType Directory -Force $out | Out-Null
& $Python (Join-Path $PSScriptRoot 'check_bjn110_math.py') --out $out
if($LASTEXITCODE -ne 0){throw 'Golden vector generation failed'}
$src=@('tri_fun.v','wave_veight.v','group_gen.v','cal_formula.v','cal_axi.v','cal_phase.v') |
    ForEach-Object {Join-Path $root ('reference\bjn110_cal_phase\'+$_)}
Push-Location $out
try {
    & (Join-Path $vivado 'xvlog.bat') -sv @src (Join-Path $root 'sim\bjn110_algorithm\rom_models.sv') (Join-Path $root 'sim\bjn110_algorithm\tb_bjn110_math.sv')
    if($LASTEXITCODE -ne 0){throw 'xvlog failed'}
    & (Join-Path $vivado 'xelab.bat') tb_bjn110_math -s bjn110_math -timescale 1ns/1ps
    if($LASTEXITCODE -ne 0){throw 'xelab failed'}
    $failed=$false
    foreach($offset in @(0,10)) {
        & (Join-Path $vivado 'xsim.bat') bjn110_math -testplusarg "SLOW_OFFSET_$offset" -runall -log "offset_$offset.log"
        if($LASTEXITCODE -ne 0 -or !(Select-String -Path "offset_$offset.log" -Pattern 'BJN110_NUMERIC_PASS' -Quiet)) {$failed=$true}
        if(Test-Path rtl_results.csv){Copy-Item rtl_results.csv "rtl_results_offset_$offset.csv" -Force}
    }
    if($failed){throw 'Original BJN110 verification failed; inspect offset logs and CSV results'}
} finally {Pop-Location}
