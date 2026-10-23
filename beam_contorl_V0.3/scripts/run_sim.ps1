$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$vivadoBin = 'D:\Vivado\Vivado\2022.2\bin'
$rtl = @(
    'beam_cmd_pkg.sv', 'array_write_engine.sv', 'array_load_ctrl.sv',
    'array_reset_ctrl.sv', 'array_output_router.sv', 'beam_ctrl_core.sv',
    'uart_rx.sv', 'channel_executor.sv', 'protocol_v03_parser.sv',
    'uart_tx_byte.sv', 'protocol_v03_response.sv', 'array_target_reset.sv',
    'protocol_v03_dispatcher.sv', 'beam_ctrl_top.sv'
) | ForEach-Object { Join-Path $project ('rtl\' + $_) }
Push-Location $project
try {
    & (Join-Path $vivadoBin 'xvlog.bat') -sv @rtl (Join-Path $project 'sim\tb_protocol_v03_top.sv')
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & (Join-Path $vivadoBin 'xelab.bat') tb_protocol_v03_top -s tb_v03
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }
    & (Join-Path $vivadoBin 'xsim.bat') tb_v03 -runall
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
} finally { Pop-Location }
