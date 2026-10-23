# 阵列波控 V0.3 FPGA 工程

器件 XC7A200T-1FBG484I，Vivado 2022.2。完整帧和当前指令的执行边界见 [V0.3 协议实施版](docs/V03协议_按110对齐实施版.md)；[110 对齐更新与验证清单](docs/V03按110对齐更新与验证清单.md)记录设计决策。旧协议草案及早期 Flash 方案是历史资料，不再作为本工程的实施依据。

## 已接入的控制

J18 RS422 使用 115200、8N1，帧为 `AA DD 01 LEN CMD ARRAY PAYLOAD SUM 55`。`00` 在 RSTN 低期间产生 128 个完整 CLK 复位周期；`40` 写单通道 6 位移相/衰减并完成 24 位 SDI 与 LDB；`C0` 按 110 原行为覆盖选中位置，不对旧码做加减；`E0` 查询阵面及 U22 探测状态。接收、发射阵面各 8 条线阵，单线阵 4 颗四通道芯片。实际硬件 CID 仍需实板确认。

`40/C0` 的收发门控独立。110 原源码中可确定的连续与计数脉冲已接入，`12` 实际为 1250/5000（25%）；需要旧板外部同步输入的模式明确返回不支持。串/并口衰减、STC、窗函数、非零频率等没有执行链的 `40` 字段返回 `05`。

U22 独立数据 Flash 使用 AA15/AA13/V13/Y14/Y13/AA14 六个 FPGA 管脚。上电先以 SPIx1 读取 JEDEC ID；只有 `20 BA 18` 才允许修改。`F1` 擦 64 KiB 扇区，`F2` 写空白 16 字节记录槽并读回比较，`F3` 逐条校验后重建缓存，`F5` 逐扇区擦所选阵面的 8 MiB 数据分区。所有 Flash 命令的回包在实际操作结束后发出。F1 的擦除粒度会影响同扇区其他记录，必须按协议实施版使用。U5 FPGA 配置 Flash 不在这些命令的目标中。U22 实物型号、装配、写保护和真实读写尚待板上验证。

`D0` 和独立预装载已删除，写入命令完成自身写入即生效。`20/A0` 暂返回 `05`；110 的角度计算源码与 COE 保存在 `reference/bjn110_cal_phase`，独立数值仿真已通过，但本项目的阵元几何、频点映射及 128 通道批量执行尚未确定。F3 缓存目前不自动向阵面写 SDI/LDB。

## 仿真与构建

在本目录运行 `./scripts/run_sim.ps1`。三组自动仿真分别覆盖 UART→SDI/Flash→应答、110 脉冲计数、U22 底层写使能/页写/擦除/轮询/读回。端到端测试包括 F1 扇区擦除、F2 四种记录、F3 重载、F5 所选分区擦除、重复写入拒绝、D0 拒绝和坏校验恢复。测试所用 U22 是行为模型，不代替实板测试。

普通板级构建：

```powershell
& 'D:\Vivado\Vivado\2022.2\bin\vivado.bat' -mode batch -source scripts\create_project.tcl
& 'D:\Vivado\Vivado\2022.2\bin\vivado.bat' -mode batch -source scripts\run_build.tcl
```

设置 `$env:V03_ENABLE_ILA='1'` 后运行同两条命令可生成含 ILA 的调试版；`$env:V03_BUILD_FLAVOR='review'` 可隔离验证构建，避免覆盖 `base/debug` 原产物。BIT 和 LTX 在 `output` 对应目录，报告在 `reports`。调试版须使用同一构建的 BIT 与 LTX。V20 板载单端时钟接在 N 侧，本版只为 IBUF→BUFG 保留 `CLOCK_DEDICATED_ROUTE FALSE` 临时例外；DRC 的 `PLCK-12` 警告和外部 I/O 时序限制须在板级验证时持续跟踪。

上位机源代码在本目录 `host_qt`，Windows 可执行版本位于 `D:/beam_control/beam_control_host_qt/release`。当前优先使用接收阵面 J1 做现场验证，核对 CID、单通道幅相、CLK/CSB/LDB/RSTN、U22 ID 与实物数据。数字仿真和内部 50 MHz 时序通过不等于射频幅相或所有外部接口时序通过。
