$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$vivadoBin = 'D:\Vivado\Vivado\2022.2\bin'
$rtl = @(
    'beam_cmd_pkg.sv', 'array_write_engine.sv', 'array_load_ctrl.sv',
    'array_reset_ctrl.sv', 'array_output_router.sv', 'beam_ctrl_core.sv',
    'uart_rx.sv', 'channel_executor.sv', 'protocol_v03_parser.sv',
    'uart_tx_byte.sv', 'protocol_v03_response.sv', 'array_target_reset.sv',
    'pulse_gate_110.sv', 'u22_spi_master.sv', 'u22_flash_probe.sv',
    'u22_flash_device.sv',
    'u22_flash_record_service.sv',
    'protocol_v03_dispatcher.sv', 'beam_ctrl_top.sv'
) | ForEach-Object { Join-Path $project ('rtl\' + $_) }
Push-Location $project
try {
    & (Join-Path $vivadoBin 'xvlog.bat') -sv @rtl `
        (Join-Path $project 'sim\tb_protocol_v03_top.sv') `
        (Join-Path $project 'sim\tb_pulse_gate_110.sv') `
        (Join-Path $project 'sim\tb_u22_flash_device.sv')
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & (Join-Path $vivadoBin 'xelab.bat') tb_protocol_v03_top -s tb_v03
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }
    $simOutput = & (Join-Path $vivadoBin 'xsim.bat') tb_v03 -runall
    $simOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
    if (($simOutput -join "`n") -notmatch 'TB_V03_PASS' -or
        ($simOutput -join "`n") -match 'Fatal:') { throw 'testbench did not pass' }
    & (Join-Path $vivadoBin 'xelab.bat') tb_pulse_gate_110 -s tb_pulse
    if ($LASTEXITCODE -ne 0) { throw 'pulse elaboration failed' }
    $pulseOutput = & (Join-Path $vivadoBin 'xsim.bat') tb_pulse -runall
    $pulseOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or ($pulseOutput -join "`n") -notmatch 'TB_PULSE_PASS' -or
        ($pulseOutput -join "`n") -match 'Fatal:') { throw 'pulse testbench did not pass' }
    & (Join-Path $vivadoBin 'xelab.bat') tb_u22_flash_device -s tb_u22
    if ($LASTEXITCODE -ne 0) { throw 'U22 device elaboration failed' }
    $flashOutput = & (Join-Path $vivadoBin 'xsim.bat') tb_u22 -runall
    $flashOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or ($flashOutput -join "`n") -notmatch 'TB_U22_DEVICE_PASS' -or
        ($flashOutput -join "`n") -match 'Fatal:') { throw 'U22 device testbench did not pass' }
} finally { Pop-Location }
