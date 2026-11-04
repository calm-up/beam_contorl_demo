# 当前工程为独立S54分支

请先阅读 [README_S54.md](README_S54.md)。以下为继承的原工程说明，历史版本和时间参数以S54说明为准。

# 阵列波控 V0.3 FPGA 工程

器件 XC7A200T-1FBG484I，Vivado 2024.2。完整帧和当前指令的执行边界见 [V0.3 协议实施版](docs/V03协议_按110对齐实施版.md)；本轮实施进度、工作量和实板验收门槛见 [后续实施进度](docs/V03后续实施进度与工作量_20261029.md)。旧协议草案及早期 Flash 方案是历史资料。

## 已接入的控制

J21 调试 RS485 与 J18 备用 RS485 使用 115200、8N1，帧为 `AA DD 01 LEN CMD ARRAY PAYLOAD SUM 55`，按入口回包。`00` 在 RSTN 低期间产生 128 个 CLK 复位周期并重写目标芯片初始化表；`40` 写单通道 6 位移相/衰减并完成 24 位 SDI 与 LDB；`C0` 按 110 原行为覆盖选中位置；`41` 两帧读取芯片寄存器；`E0` 查询阵面、初始化及 U22 状态。接收、发射阵面各 8 条线阵，单线阵 4 颗四通道芯片。CID `3210` 有 V0.2 J1 功能验证；DXF 馈线确定每颗芯片左到右为 RF4/RF3/RF1/RF2。

`40/C0` 的收发门控独立。110 原源码中可确定的连续与计数脉冲已接入，`12` 实际为 1250/5000（25%）；需要旧板外部同步输入的模式明确返回不支持。串/并口衰减、STC、窗函数、非零频率等没有执行链的 `40` 字段返回 `05`。

U22 独立数据 Flash 使用 AA15/AA13/V13/Y14/Y13/AA14 六个 FPGA 管脚。上电先以 SPIx1 读取 JEDEC ID；只有 `20 BA 18` 才允许修改。`F1` 擦 64 KiB 扇区，`F2` 写空白 16 字节记录槽并读回比较，`F3` 逐条校验后重建缓存，`F5` 逐扇区擦所选阵面的 8 MiB 数据分区。所有 Flash 命令的回包在实际操作结束后发出。F1 的擦除粒度会影响同扇区其他记录，必须按协议实施版使用。U5 FPGA 配置 Flash 不在这些命令的目标中。U22 实物型号、装配、写保护和真实读写尚待板上验证。

`D0` 和独立预装载已删除，写入命令完成自身写入即生效。`20/A0` 已接入 110 定点角度算法，按已确认的 9.6 mm 间距和 8×16 坐标计算相位，并按 32 路 SDI、四个芯内通道轮次并行写入。`A0` 按三组掩码的组合启用目标通道。芯片 0 在最右侧，芯内 RF 馈线顺序按 DXF 修正；整机纵向安装方向仍须结合实板确定。当前衰减码为 0，未接入 Flash 标定。F3 缓存目前不自动向阵面写 SDI/LDB。

当前测试构建位于 `output/release_20261029/`，含 BIT、U5 SPIx1 MCS 和[固化与测试说明](output/release_20261029/固化与测试说明.md)；上位机位于 `output/host_v03/`。Vivado 2024.2 布局布线完成，50 MHz 建立/保持时间余量分别为 +2.745/+0.006 ns；文件尚未烧录。

## 仿真与构建

在本目录运行 `./scripts/run_sim.ps1`。五组自动仿真分别覆盖双 RS485→SDI/Flash/SDO→应答、110 相位公式的正负数定点向量、110 脉冲计数、U22 底层写使能/页写/擦除/轮询/读回。端到端测试包括 20/A0 并行选区、F1 扇区擦除、F2 四种记录、F3 重载、F5 所选分区擦除、重复写入拒绝、D0 拒绝和坏校验恢复。测试所用 U22 是行为模型，不代替实板测试。

普通板级构建：

```powershell
& 'D:\Vivado\Vivado\Vivado\2024.2\bin\vivado.bat' -mode batch -source scripts\create_project.tcl
& 'D:\Vivado\Vivado\Vivado\2024.2\bin\vivado.bat' -mode batch -source scripts\run_build.tcl
& 'D:\Vivado\Vivado\Vivado\2024.2\bin\vivado.bat' -mode batch -source scripts\create_u5_mcs.tcl
```

设置 `$env:V03_ENABLE_ILA='1'` 后运行同两条命令可生成含 ILA 的调试版；`$env:V03_BUILD_FLAVOR='review'` 可隔离验证构建，避免覆盖 `base/debug` 原产物。BIT 和 LTX 在 `output` 对应目录，报告在 `reports`。调试版须使用同一构建的 BIT 与 LTX。V20 板载单端时钟接在 N 侧，本版只为 IBUF→BUFG 保留 `CLOCK_DEDICATED_ROUTE FALSE` 临时例外；DRC 的 `PLCK-12` 警告和外部 I/O 时序限制须在板级验证时持续跟踪。

上位机源代码在本目录 `host_qt`，本版 Windows 可执行文件位于 `host_qt/release/beam_control_host.exe`。当前优先使用接收阵面 J1 做现场验证，核对 CID、单通道幅相、CLK/CSB/LDB/RSTN、U22 ID 与实物数据。数字仿真和内部 50 MHz 时序通过不等于射频幅相或所有外部接口时序通过。
