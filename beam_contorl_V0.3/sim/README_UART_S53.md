# s53 按板上参数进行串口仿真

默认顶层：tb_protocol_v03_top，参数BOARD_TIMING=1。硬件顶层beam_ctrl_top不能直接作为仿真顶层，否则输入悬空为Z。

## 手动操作（不需要Tcl）

1. 关闭当前仿真；在Simulation Sources中添加sim/tb_protocol_v03_top.sv（已有则不用重复添加）。
2. 右键tb_protocol_v03_top，选择Set as Top；正确层级为tb_protocol_v03_top → dut:beam_ctrl_top。
3. 若曾在Simulation Settings中覆盖BOARD_TIMING，将其设为1或删除覆盖；不要向testbench传递硬件顶层的ENABLE_DEBUG_ILA/LDB_LOW_CYCLES参数。
4. Run Simulation → Run Behavioral Simulation，再点击Run All。修改激励后应关闭并重新启动仿真，单纯Restart不会重新编译。
5. 波形中观察sys_clk_i、debug_rx_i、debug_tx_o、active_command，以及dut的rx_sdi_o/rx_clk_o/rx_csb_o/rx_ldb_o。后半段覆盖spare_rx_i/spare_tx_o。

## 当前参数

| 项目 | 设置 |
|---|---|
| 系统时钟 | 50MHz，20ns周期 |
| UART | 115200，整数分频434，每位8680ns |
| SPI | 5MHz，200ns周期，100ns半周期 |
| 帧后时钟 | 2个完整周期 |
| CS低末位保持 | 100ns |
| LDB保护计数 | 10系统周期，要求至少200ns；当前命令路径实际660ns |
| LDB低脉宽 | 5系统周期，100ns（已按用户要求恢复；原s53 BIT为1µs） |
| 上电POR | 4系统周期 |
| 复位时钟/后等待 | 128个SPI周期/10系统周期 |
| 自动初始化 | 开启，与硬件同样发送每颗512帧 |
| 诊断指令 | 开启（41/42/43）；仿真不实例化ILA调试IP |

激励等待初始化与Flash探测完成后再发协议。启动初始化帧与后续命令帧分开统计，避免512帧使命令捕获数组越界。UART逐位发送和响应采样均使用434周期分频。超时上限500ms。

约2.760360ms完成启动初始化并开始首条40请求；首条请求约4.757ms发送完，40命令应答约5.638ms结束。可重点放大4.75～4.78ms，查看两帧SPI及LDB。初始化在0～2.76ms。时间日志以ps显示，例如2760360000对应2.760360ms。

同一文件内的tb_s53_pin_timing自动检查RX J1和TX J1：帧内200ns周期/100ns高电平、24个时钟、CS末位100ns保持、帧间至少两个上升沿，以及LDB保护间隔/100ns低脉宽。其他线阵可在波形中查看，此监视器不等于全端口外部时序验证。

SDO仍由mock_sdo提供；Flash仍使用行为模型。通过表示FPGA按s53参数产生了预期协议和引脚时序，不证明芯片内部幅相处理在停钟时能工作。

## ROM与波形

beam_phase_rom读取rtl/rom/tri.mem。当前s53的XSim运行目录已补齐该路径。若手动清理仿真运行目录，需用资源管理器将工程rtl/rom/tri.mem复制到build/s53/beam_control_v03.sim/sim_1/behav/xsim/rtl/rom/tri.mem，随后重新启动仿真。

有效波形：build/s53/beam_control_v03.sim/sim_1/behav/xsim/tb_protocol_v03_top_behav.wdb，不是旧的beam_ctrl_top_behav.wdb。

原加速配置保留为BOARD_TIMING=0，仅供回归；本次默认使用板上参数。历史42.736810ms PASS属于加速配置，不能用作当前配置的结果。

## 本次验证结果（2026-11-02）

Vivado 2024.2，默认BOARD_TIMING=1，122.246550ms结束并打印TB_V03_PASS，无Fatal。启动J1初始化捕获512帧；RX/TX J1时序监视断言通过，命令40路径CS到LDB为660ns，独立43命令的间隔因串口事务而更长。测试覆盖原协议序列及复位后完整重新初始化。

日志：output/uart_s53_board_timing.log。GUI点击Run All即可运行同一默认激励，无需在Tcl Console输入命令。

2026-11-02调整：LDB恢复100ns；同时修改s53 XPR泛型为5。此前122.246550ms PASS记录对应调整前的1µs设置。已有BIT及板上配置不随源码/XPR修改自动改变。
`n100ns配置验证通过：122.234850ms结束，TB_V03_PASS；RX/TX J1的100ns低脉宽断言通过。日志output/uart_s53_ldb100ns_isolated.log。为避免占用用户正在打开的仿真，波形保存在build/ldb100ns_check/ldb100ns_check.sim/sim_1/behav/xsim/tb_protocol_v03_top_behav.wdb。
