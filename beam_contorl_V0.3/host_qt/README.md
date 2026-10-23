# 阵列波控调试工具 V0.3

Windows 11 x64 桌面程序，使用 C++17、Qt 6 Widgets 和 Qt Serial Port。独立目录，与 V0.3 FPGA RTL 同步维护。

## 运行与调试

下载或复制完整 `release` 目录，在 Windows 11 x64 上双击 `beam_control_host.exe`，不要单独复制可执行文件。首次建议选择“模拟设备”并连接，在左侧选择命令，检查右侧完整报文，发送后观察结果和日志。接入实板时选择“RS422串口”及对应 COM 口；该版本串口参数固定为 115200、8N1。测试接收阵面 J1 时，选择“接收阵面”、线阵编号 0，再选择 SDI1～4 对应的芯片索引与芯内通道 0～3。日志可导出 CSV。

## 当前功能

- 16 种 V0.3 命令模式：通道幅相、线阵复位、波束/区域/选中位置覆盖、状态查询以及 Flash 记录维护；已删除 D0。
- 按协议范围检查字段，生成完整帧并显示十六进制字节；固定字段只读。
- 接收/发射各 8 条线阵，每条 4 颗芯片、每颗 4 通道。通道表支持单发和勾选后顺序发送。
- 模拟设备提供成功、忙、参数错误、分段回包、错误校验和、无应答。真实串口固定 115200、8N1。
- 一个未完成命令对应一个应答，批量任务顺序推进。超时后停止队列，显示结果未知，不自动重发。
- 256 通道配置可保存/载入为 JSON；载入只改变待发送值。
- 通信与任务日志可导出为 UTF-8 CSV。真实串口的 Flash 擦除命令发送前需再次确认。
- 网分仪和扫描架的 C++ 接口预留在 `src/external_interfaces.h`，没有设备驱动。

## 当前限制

- 实板是否下载最新 V0.3 比特流、实际 U22 ID 和阵面响应需现场确认；真实串口连接成功不代表命令得到板端执行。
- V0.3 RTL 已执行 00、40、C0、E0 和 F1/F2/F3/F5；Flash 功能仅通过行为模型仿真，U22 实板尚未验证。20、A0 目前明确返回 05，不能当作已完成波束写入。
- 状态查询的五项附加字节按实施版编码；模拟设备的数值只用于软件流程验证。
- 指向系数编号及缩放、Flash 数据分区、波束计算、厂家初始化和真实 CID 仍待确认；110 脉冲源码的 12 模式实际上是 25% 占空比。
- 本程序未连接射频仪器，也不宣称完成阵面幅相测量。
- 未实现旧 BJN110 文件自动转换；其子阵/芯片编号与本项目不同。可在软件中逐通道编辑或使用新 JSON 配置。

## 构建

安装 Qt 6.5+（包含 Widgets、Serial Port）、CMake 和匹配的 64 位编译器。在 Windows 11 的常规方案为 Qt 6.8.x＋MSVC 2022 x64。

```powershell
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH="<Qt安装目录>"
cmake --build build
ctest --test-dir build --output-on-failure
```

运行 `build/beam_control_host.exe`。交付机器使用同一 Qt 套件的 `windeployqt` 整理依赖。

协议纯 C++ 部分可在没有 Qt 的机器上检查：

```powershell
g++ -std=c++17 -Isrc src/protocol.cpp tests/protocol_tests.cpp -o protocol_tests.exe
./protocol_tests.exe
```

协议依据为 `D:/beam_control/beam_control_demo/beam_contorl_demo/beam_contorl_V0.3/docs/V03协议_按110对齐实施版.md`。本程序的协议层以固定字段顺序组帧，不发送十六进制文本中的空格。
