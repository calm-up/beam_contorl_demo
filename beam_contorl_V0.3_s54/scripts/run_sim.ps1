$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$vivadoBin = 'D:\Vivado\Vivado\Vivado\2024.2\bin'
$rtl = @(
    'beam_cmd_pkg.sv', 'beam_phase_rom.sv', 'beam_formula_calc.sv',
    'beam_phase_calc.sv',
    'array_write_engine.sv', 'array_load_ctrl.sv',
    'array_reset_ctrl.sv', 'array_output_router.sv', 'beam_ctrl_core.sv',
    'uart_rx.sv', 'channel_executor.sv', 'protocol_v03_parser.sv',
    'uart_tx_byte.sv', 'protocol_v03_response.sv', 'array_target_reset.sv',
    'pulse_gate_110.sv', 'u22_spi_master.sv', 'u22_flash_probe.sv',
    'u22_flash_device.sv',
    'u22_flash_record_service.sv',
    'protocol_v03_dispatcher.sv', 'protocol_v03_rs485_port.sv',
    'chip_sdo_reader.sv', 'beam_ctrl_top.sv'
) | ForEach-Object { Join-Path $project ('rtl\' + $_) }
$reference = @('tri_fun.v', 'cal_formula.v') |
    ForEach-Object { Join-Path $project ('reference\bjn110_cal_phase\' + $_) }
Push-Location $project
try {
    & (Join-Path $vivadoBin 'xvlog.bat') -sv @rtl @reference `
        (Join-Path $project 'sim\tb_protocol_v03_top.sv') `
        (Join-Path $project 'sim\s53_reference_array_write_engine.sv') `
        (Join-Path $project 'sim\tb_s54_periodic_clock.sv') `
        (Join-Path $project 'sim\tb_beam_formula_calc.sv') `
        (Join-Path $project 'sim\tb_pulse_gate_110.sv') `
        (Join-Path $project 'sim\tb_u22_flash_device.sv') `
        (Join-Path $project 'sim\tb_array_write_sdo.sv') `
        (Join-Path $project 'sim\tb_tr_spi_timing.sv') `
        (Join-Path $project 'sim\tb_tr_pipeline_model.sv') `
        (Join-Path $project 'sim\tb_chip_sdo_pipeline.sv') `
        (Join-Path $project 'sim\tb_ccar10405l_init.sv')
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    & (Join-Path $vivadoBin 'xelab.bat') tb_protocol_v03_top -s tb_v03
    if ($LASTEXITCODE -ne 0) { throw 'xelab failed' }
    $simOutput = & (Join-Path $vivadoBin 'xsim.bat') tb_v03 -runall
    $simOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) { throw 'xsim failed' }
    if (($simOutput -join "`n") -notmatch 'TB_V03_PASS' -or
        ($simOutput -join "`n") -match 'Fatal:') { throw 'testbench did not pass' }
    & (Join-Path $vivadoBin 'xelab.bat') tb_beam_formula_calc -s tb_formula
    if ($LASTEXITCODE -ne 0) { throw 'formula elaboration failed' }
    $formulaOutput = & (Join-Path $vivadoBin 'xsim.bat') tb_formula -runall
    $formulaOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or ($formulaOutput -join "`n") -notmatch 'TB_BEAM_FORMULA_PASS' -or
        ($formulaOutput -join "`n") -match 'Fatal:') { throw 'formula testbench did not pass' }
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
    & (Join-Path $vivadoBin 'xelab.bat') tb_array_write_sdo -s tb_sdo
    if ($LASTEXITCODE -ne 0) { throw 'SDO alignment elaboration failed' }
    $sdoOutput = & (Join-Path $vivadoBin 'xsim.bat') tb_sdo -runall
    $sdoOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or ($sdoOutput -join "`n") -notmatch 'ARRAY_WRITE_SDO_PASS' -or
        ($sdoOutput -join "`n") -match 'Fatal:') { throw 'SDO alignment testbench did not pass' }
    foreach ($test in @(@('tb_tr_spi_timing','tb_tr_spi','TR_SPI_TIMING_PASS'),
                         @('tb_tr_pipeline_model','tb_tr_model','TR_PIPELINE_MODEL_PASS'),
                         @('tb_chip_sdo_pipeline','tb_chip_pipeline','CHIP_SDO_PIPELINE_PASS'),
                         @('tb_s54_periodic_clock','tb_s54_periodic','S54_PERIODIC_CLOCK_PASS'))) {
        & (Join-Path $vivadoBin 'xelab.bat') $test[0] -s $test[1]
        if ($LASTEXITCODE -ne 0) { throw "TR test elaboration failed: $($test[0])" }
        $trOutput = & (Join-Path $vivadoBin 'xsim.bat') $test[1] -runall
        $trOutput | ForEach-Object { Write-Output $_ }
        if ($LASTEXITCODE -ne 0 -or ($trOutput -join "`n") -notmatch $test[2] -or
            ($trOutput -join "`n") -match 'Fatal:') { throw "TR test failed: $($test[0])" }
    }
    & (Join-Path $vivadoBin 'xelab.bat') tb_ccar10405l_init -s tb_init
    if ($LASTEXITCODE -ne 0) { throw 'chip init elaboration failed' }
    $initOutput = & (Join-Path $vivadoBin 'xsim.bat') tb_init -runall
    $initOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0 -or ($initOutput -join "`n") -notmatch 'CCAR10405L_INIT_PASS' -or
        ($initOutput -join "`n") -match 'Fatal:') { throw 'chip init testbench did not pass' }
} finally { Pop-Location }
