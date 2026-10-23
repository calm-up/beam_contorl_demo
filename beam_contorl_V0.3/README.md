# 阵列波控 V0.3 FPGA demo

未实现模式的原因、A0/D0补齐方案和U5/U22最新连线核查，见 [V0.3未实现指令与双Flash核查及实现方案](docs/V03未实现指令与双Flash核查及实现方案.md)。其中U22用户I/O的设计连接已经核实；实物装配及读ID仍待板上确认。

器件：XC7A200T-1FBG484I；Vivado：2022.2。工程独立于仓库内的 V0.2 目录，约束以已验证的 V0.2 板级 XDC 为基线。上位机对应 `D:/beam_control/beam_control_host_qt`。本目录不含自动校准或扫描架控制。

## 当前功能边界

- RS422 J18，115200、8N1，帧格式 `AA DD 01 LEN CMD ARRAY PAYLOAD SUM 55`。有效请求执行完毕后通过 FPGA_422_TXD 回 `7F` 应答；校验错误帧直接丢弃。
- `40`：接收或发射单通道开关、6位移相和0～31衰减码；两轮24bit SDI帧及一次LDB结束后才回成功。目标芯片用CID映射，默认 `3210` 仍需实板确认。
- `C0`：对已经成功提交的通道作有符号增量；相位模64，衰减限幅0～31。没有已提交旧值时回 `07`。
- `00`：只复位指定阵面与线阵；RSTN低期间产生128个完整时钟，再清对应控制缓存与门控。
- `E0`：返回初始化、忙、错误、接收使能线阵掩码和发射使能线阵掩码，五个字节各占1字节；状态字前3个目前为0/1。
- `20/A0/D0/F1/F2/F3/F5`：保留V0.3命令入口，当前执行路径返回 `05` 不支持，不进行任何Flash操作或波束计算。
- 脉冲形式 `00/01/02` 用于当前静态线阵T/R门控。百分比脉冲和外部同步未接入。

`reference/bjn110_cal_phase/` 保存110的计算模块源码和三张原始COE表，尚未加入板级综合或协议执行链。现已按110顶层参数完成独立数值仿真；方法、范围和D0说明见 [110角度计算验证](docs/BJN110角度计算源码验证与D0说明.md)，运行脚本为 `scripts/run_bjn110_math.ps1`。该验证不等于20/A0已接入或当前128通道阵列几何已确认。

## 自动仿真

在PowerShell中执行：

```powershell
cd D:\beam_control\beam_control_demo\beam_contorl_demo\beam_contorl_V0.3
.\scripts\run_sim.ps1
```

自动检查Qt文档示例的目标帧 `0x221510`、两轮写入/LDB、`7F`应答、E0状态、C0增量、目标复位128时钟、不支持命令以及坏校验后重新同步。成功标记为 `TB_V03_PASS`。测试台为加速串口仿真使用较低的参数时钟，硬件构建仍为50MHz/115200。

## Vivado构建

普通版：

```powershell
& 'D:\Vivado\Vivado\2022.2\bin\vivado.bat' -mode batch -source scripts\create_project.tcl
& 'D:\Vivado\Vivado\2022.2\bin\vivado.bat' -mode batch -source scripts\run_build.tcl
```

带ILA版：

```powershell
$env:V03_ENABLE_ILA='1'
& 'D:\Vivado\Vivado\2022.2\bin\vivado.bat' -mode batch -source scripts\create_project.tcl
& 'D:\Vivado\Vivado\2022.2\bin\vivado.bat' -mode batch -source scripts\run_build.tcl
```

生成的项目在 `build/base` 或 `build/debug`。输出位流及调试探针文件在 `output` 对应子目录；在Hardware Manager中使用**同一次构建的** `.bit` 和 `.ltx`。运行日志、DRC、时序和资源报告在 `reports`。生成物已在 `.gitignore` 排除。

板上首验以接收阵面J1为目标。`ila_v03_protocol` 的9组探针观察RX字节、接收进度、命令、状态和TX应答事件；`ila_v03_array` 的8组探针观察J1的4路SDI、CLK/CSB/LDB/RSTN、R门控、SDI1帧及执行事件。两核均由自由运行的系统时钟采样。连续采样4096点不能覆盖完整23字节UART帧，可分别触发帧接收或使用上位机日志对照；阵面组8192点用于SDI周期级检查。ILA看到的是FPGA内部信号，连接器电平仍由示波器测量。

XDC保留现板V20单端时钟的临时布线例外。该方案需查看构建时序报告及实板稳定性；设计改板后的时钟位置应重新约束，不把当前例外扩展到其他时钟。未核实芯片CID、芯内通道与阵元位置、厂家初始化流程及射频响应前，不将数字时序通过等同于阵面幅相实测通过。

2026-10-23 带 ILA 版已在 Vivado 2022.2 完成综合、布局布线和位流生成；仿真出现 `TB_V03_PASS`。内部 50 MHz 时序的 WNS 为 6.103 ns、WHS 为 0.030 ns。DRC 无错误，保留两项警告：`PLCK-12` 对应 V20 非专用时钟路径，`RTSTAT-10` 指向 ILA 调试 hub 内无可布线负载的网络。外部阵面接口和 RS422 的输入/输出延迟尚未定量，因此这份时序通过不能替代板级时序确认。

## 源码结构

- `rtl/protocol_v03_parser.sv`：变长帧、校验、超时恢复。
- `rtl/protocol_v03_dispatcher.sv`：字段检查、命令执行、已提交状态与错误应答。
- `rtl/channel_executor.sv`：两轮芯片写入及LDB；由V0.2控制器适配。
- `rtl/array_target_reset.sv`：目标阵面/线阵复位。
- `rtl/protocol_v03_response.sv`、`uart_tx_byte.sv`：8N1应答。
- `rtl/beam_ctrl_top.sv`：板级连线、输出安全门控和ILA实例。
- `sim/tb_protocol_v03_top.sv`：真实UART位流至阵面输出的端到端测试。

协议参考：`D:/beam_control/波控调试协议草案_V0.3_参考BJN110.md`。110复用依据：`D:/beam_control/V0.3_FPGA实现方案与BJN110复用审查.md`。
