> 最新变更（2026-11-03）：42独立写、43独立LDB接口及专用模块已删除；40/C0正常配置与41回读保留。后文早期变更记录中的42说明属于历史。Review见docs/删除42_43命令_Review_20261103.md。

# S54：SCLK连续运行版（替换之前仅缩短帧末间隔的版本）

## 不用Tcl的打开方法

1. 关闭旧仿真并重新打开本目录 build/s54/beam_control_v03.xpr。
2. 在Simulation Sources确认活动集合为sim_continuous，顶层tb_protocol_v03_top。如不是，右键sim_continuous → Make Active。
3. Run Simulation → Run Behavioral Simulation，再点击Run All。不能只Restart旧快照。
4. 观察rx_clk_o[0]或tx_clk_o[0]：5MHz、周期200ns、高低各100ns。UART接收、帧间、空闲、LDB、运行时复位期间都持续翻转。放大时间轴后才能看清连续方波；不要把正常100ns低半周期误认为停钟。

现有sim_1和sim_continuous使用同一个最新testbench，但新集合避免沿用旧WDB、旧编译快照或占用旧运行目录。连续版有效WDB路径为build/s54/beam_control_v03.sim/sim_continuous/behav/xsim/tb_protocol_v03_top_behav.wdb。波形名称仍相同，必须注意目录sim_continuous。

## 改动

此前版本只去掉末位处理导致的额外100ns低电平，事务结束仍停钟；该版本没有满足连续时钟要求，现已替换。

现在array_write_engine中的分频器独立于状态机运行，所有8路SCLK持续输出，line_mask只控制CSB和SDI。CSB在规则下降沿开始一帧；接下来24个上升沿采样数据。末次下降沿后80ns补采最后一位并释放CSB，下一上升沿仍在100ns处，留20ns的CSB建立间隔。两个帧后时钟只作为“完成所需最少时钟”的计数，不再作为停止时钟的条件。该20ns间隔为实现选择，板级验证仍需结合器件时序。

beam_ctrl_core不再因初始化/重新初始化复位写引擎的分频器。array_output_router不再切换复位时钟与写入时钟。beam_ctrl_top运行时复位也不再切换时钟源；array_target_reset对现有连续时钟计数，在低相位改变RSTN，保持128个有效复位周期。

上电POR保持阶段仍按设计把引脚置低；POR释放后直到仿真结束持续供钟。RX/TX的所有8路线阵，包括未选中线阵，都收到同相连续时钟。没有修改RF发射/接收使能策略。

参数仍为50MHz系统时钟、115200 UART、5MHz SCLK、100ns LDB低脉宽，自动初始化开启。仅有CSB低期间的24个上升沿属于SPI帧，CSB高时的持续时钟不计入数据帧。

## 备份与验证

S53完整备份位于同级beam_contorl_V0.3_s53_backup_20261102_232931，未修改。上一版S54源码、脚本和XPR快照保存在本目录snapshots/before_continuous_20261102_234604。

完整回归日志：output/s54_continuous_regression.log；摘要：output/s54_continuous_validation.json。

已通过完整UART协议、SDO末位、SPI位序/时序、写入与LDB模型、reader流水、周期专项、RX/TX初始化、角度计算、脉冲和Flash器件模型。全协议测试挂接16个连续时钟监视器，所有RX/TX物理时钟高低半周期必须各100ns；停止超过120ns也会报Fatal，检查不会在CSB高、空闲、LDB或RSTN低时暂停。运行时复位仍验证128个上升沿。周期专项还检查空闲延时和未选中线阵的时钟。

工程GUI路径复测日志：output/s54_continuous_gui_sim.log。

仿真通过不代表芯片内部行为已经实板验证。未生成新BIT、未下载、未写Flash。

连续版GUI工程复测已完成：122.297670ms结束，TB_V03_PASS，无Fatal；有效WDB已生成。S53原RTL与备份哈希再次一致。

## 2026-11-03：复用P1

40/C0单芯片及42独立写的四路SDI已改为同一目标帧；41读保持P2。全协议及P1逐位一致性检查通过，日志output/s54_p1_protocol.log。连续时钟与100ns LDB保持原设置。早采样复现本次只写思路，见docs/P1策略移植与SDO早采样复现思路_20261103.md，未新增复现模型。修改后需关闭并重新启动行为仿真以重新编译。旧WDB是修改前结果。
