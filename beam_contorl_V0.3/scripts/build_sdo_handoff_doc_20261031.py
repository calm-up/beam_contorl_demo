from pathlib import Path
import csv,json,re
from datetime import datetime
from docx import Document
from docx.shared import Inches,Pt,RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT,WD_CELL_VERTICAL_ALIGNMENT

ROOT=Path(__file__).resolve().parents[1]
OUT=Path(r'D:\beam_control\交付归档\SDO调试交接_20261031')
doc=Document(); sec=doc.sections[0]
sec.page_width=Inches(8.5);sec.page_height=Inches(11)
sec.top_margin=sec.bottom_margin=Inches(.66);sec.left_margin=sec.right_margin=Inches(.68)
sec.header_distance=sec.footer_distance=Inches(.27)
for name in ['Normal','Title','Subtitle','Heading 1','Heading 2','Heading 3']:
 s=doc.styles[name];s.font.name='Calibri';s.font.color.rgb=RGBColor(0,0,0)
 s._element.rPr.rFonts.set(qn('w:eastAsia'),'Microsoft YaHei')
doc.styles['Normal'].font.size=Pt(10.5)
doc.styles['Normal'].paragraph_format.line_spacing=1.15
doc.styles['Normal'].paragraph_format.space_after=Pt(6)
doc.styles['Title'].font.size=Pt(23)
doc.styles['Heading 1'].font.size=Pt(17)
doc.styles['Heading 2'].font.size=Pt(12)
for name in ['Heading 1','Heading 2']:
 doc.styles[name].paragraph_format.space_before=Pt(8)
 doc.styles[name].paragraph_format.space_after=Pt(7)
for style in doc.styles:
 for borders in style.element.findall('.//' + qn('w:pBdr')):
  borders.getparent().remove(borders)
h=sec.header.paragraphs[0]; h.text='阵列波束控制 V0.3    SDO与动态幅相调试交接'
h.runs[0].font.size=Pt(8)
f=sec.footer.paragraphs[0];f.alignment=WD_ALIGN_PARAGRAPH.RIGHT
f.add_run('记录截止 2026年10月31日18时24分    第 ')
fld=OxmlElement('w:fldSimple');fld.set(qn('w:instr'),'PAGE');f._p.append(fld);f.add_run(' 页')
for r in f.runs:r.font.size=Pt(8)

def p(text,bold=False):
 a=doc.add_paragraph();a.add_run(text).bold=bold;return a
def h2(text):doc.add_heading(text,2)
def page(title):
 heading=doc.add_heading(title,1)
 heading.paragraph_format.page_break_before=True
def table(headers,rows,widths=None,size=9):
 t=doc.add_table(rows=1, cols=len(headers));t.alignment=WD_TABLE_ALIGNMENT.CENTER;t.autofit=False
 for i,x in enumerate(headers):t.rows[0].cells[i].text=str(x)
 rep=OxmlElement('w:tblHeader');t.rows[0]._tr.get_or_add_trPr().append(rep)
 for row in rows:
  for cell,x in zip(t.add_row().cells,row):cell.text=str(x)
 for ri,row in enumerate(t.rows):
  trpr=row._tr.get_or_add_trPr();n=OxmlElement('w:cantSplit');trpr.append(n)
  for ci,c in enumerate(row.cells):
   if widths:c.width=Inches(widths[ci])
   c.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER
   pr=c._tc.get_or_add_tcPr();mar=OxmlElement('w:tcMar')
   for edge in ['top','left','bottom','right']:
    z=OxmlElement('w:'+edge);z.set(qn('w:w'),'75');z.set(qn('w:type'),'dxa');mar.append(z)
   pr.append(mar);b=OxmlElement('w:tcBorders')
   for edge in ['top','left','bottom','right']:
    z=OxmlElement('w:'+edge);z.set(qn('w:val'),'single');z.set(qn('w:sz'),'4');z.set(qn('w:color'),'D9D9D9');b.append(z)
   pr.append(b)
   if ri==0 or ri%2==0:
    z=OxmlElement('w:shd');z.set(qn('w:fill'),'DDE7EF' if ri==0 else 'F5F7F9');pr.append(z)
   for a in c.paragraphs:
    a.paragraph_format.space_after=Pt(2);a.paragraph_format.line_spacing=1.03
    for run in a.runs:run.font.size=Pt(size);run.bold=ri==0
 doc.add_paragraph().paragraph_format.space_after=Pt(1)
 return t
def src(text):
 a=p('证据：'+text)
 for r in a.runs:r.font.size=Pt(8.5)
def rows(path):return list(csv.DictReader(path.open(encoding='utf-8-sig')))

doc.add_heading('SDO回读与幅相控制调试交接报告',0)
p('阵列波束控制 V0.3    接收阵面 J1    2026年10月30日至31日',True)
p('本报告面向接手RTL、板级SPI和射频调试的工程师，记录SDO开始出现有效回读后，到s53独立写入与独立LDB实验完成为止的调试过程。内容按时间与因果关系排列，并附可核查的发送帧、原始ILA证据、版本产物及未闭合问题。早于有效回读的全高问题仅作必要背景。')
h2('当前结论')
p('初始化寄存器的数字回读已有通过证据：s51完成J1四芯片Control_Reg共512项；s52完成Control_Reg及四类查表共2048项的一轮集中回读。但动态幅相写后回读仍未通过：复位后的J1全16通道测试数据区均为零，最新s53单通道三轮分离写入与LDB实验同样未随040和080变化。')
p('尚不能将问题定为LDB脉宽不足、芯片损坏、共享SDO争用或RTL读请求填零。现有证据支持优先核对动态幅相读写语义、芯片实际接收和装载路径。通道开关有响应不等于衰减或移相已配置成功。')
h2('交付内容')
table(['内容','定位'],[
('本报告','完整过程、逐版变更、数字与RF结果、下一步操作'),
('01_最新版s53','RTL与依赖、BIT、LTX、routed DCP、报告和构建日志'),
('02_历史版本','各版原始BIT/LTX及综合输入、实现日志和报告'),
('03_原始调试证据','逐次ILA CSV、离线解码、统计JSON/CSV和串口日志'),
('04_原始说明与计划','继承工作流及历史说明原件'),
('05_芯片资料','本轮新码表、CCAR10405L V2.1及配套SPI手册原件')],[1.5,5.6],10)
p('报告中“通过”仅对应其明确列出的项目与当时状态。SDO全高时的实验保留为故障证据，不计入动态寄存器验证。未测项目不会以仿真或历史个别成功替代。')

page('一 现场条件与编号约定')
table(['项目','本次实际使用或限制'],[
('工程','beam_contorl_V0.3；原机位于D盘beam_control工程树'),
('FPGA与工具','XC7A200T FBG484 -1；Vivado 2024.2；系统时钟50 MHz'),
('硬件连接','Digilent JTAG序列号210251190311；COM5，115200，8N1'),
('测试范围','接收阵面RX的J1；只确认SDO1可用，不外推其他线阵'),
('SDO飞线','用户最终确认U9.12 → U9.37；先前“22脚”口述已更正'),
('测点','J1.20为阵面SDO；J1.24为LDB；FPGA侧SDO映射H19'),
('芯片与RF编号','逻辑芯片0～3；RF1～RF4对应软件通道编码0～3'),
('可测范围','后期用户明确只能量到J1.20，不能测芯片本体管脚'),
('供电与串口','多次发现供电/连接状态变化；COM5占用时由脚本关闭或用户释放')],[1.35,5.75],10)
h2('CID定义与独立SDI及共享SDO')
p('顶层CHIP_CID_MAP=16\'h3210，以CID_MAP[chip*4 +: 4]取半字节。因此逻辑芯片0/1/2/3分别使用CID0/1/2/3，对应四路独立SDI。SPI帧D23～D20是CID，D19是读写位。SDO为同一J1上的共享返回线，回读不是等待四颗芯片汇总；每次选一颗芯片和一个目标地址，取共享线上的24位返回。')
p('CID与逻辑SDI的对应有初始化读回支持，但不能据此自动得到物理U位号和RF连接器的完整映射。用户曾误选“芯片SDO有跳变、J1.20无跳变”，随后说明点错；此条不作为芯片端已经测到有效SDO的证据。')
h2('现场信号完整性风险的边界')
p('历史原理图分析提示U9方向/使能与飞线可能造成争用，需测U9 DIR/OE实际电平和波形确认。现有记录未完成此项闭环；不得将电路分析写为已确认故障。示波器照片中小幅振铃也不能单独证明数字门限有效或无效。')
src('E01 diag_sdo_raw在线复测；E03 s50寄存器复测；04_原始说明与计划中的物理映射记录。')

page('二 寄存器空间与验证标准')
p('“四个初始配置寄存器”在本轮排查中按四类幅相查表理解：TXPS、RXPS、TXATT、RXATT；此外还必须检查Control_Reg。五类初始化空间与动态幅相索引寄存器应分别验证。')
table(['对象','SPI功能','地址与数据','每芯片初始化帧数'],[
('Control_Reg','100','地址0～127，8位数据','128'),
('TXPS','101','字节地址0～127，每表项16位分高低字节','128'),
('TXATT','110','索引0～63，每项10位','64'),
('RXPS','101','字节地址128～255，每表项16位分高低字节','128'),
('RXATT','111','索引0～63，每项10位','64'),
('TX动态幅相','001','通道D15～D12，衰减D11～D6，相位D5～D0','不在512内'),
('RX动态幅相','010','同上，6位衰减索引和6位相位索引','不在512内'),
('通道使能','000','有效通道掩码，本芯片用低4位','单独控制')],[1.15,.75,4.25,.95],9.5)
p('初始化顺序为Control 128 → TXPS 128 → TXATT 64 → RXPS 128 → RXATT 64，共512帧。四路SDI并行写各自CID；读回逐颗逐项进行，因此J1总检查数为4×512=2048。普通动态40命令先写通道使能、再写幅相、再LDB，不在每次幅相写前重刷整套初始表。')
h2('新码表核对')
p('资料为10405W_12_18_HP_SPI裸片详测码表_20261028.xlsx。独立比较记录显示Control_Reg 128项与RTL零差异，512条初始化帧与期望展开零差异。源码比较只证明“准备发送的值正确”；只有板级有效回读才证明当时的可读寄存器内容匹配。')
h2('通过判据')
p('传输通过：两帧时序有效、响应CID/功能/地址匹配、read_done=1且read_error=0。写后验证通过：在传输通过基础上，返回数据区必须等于本次写值，并能重复跟随不同非零值变化。RF通过：固定连续波与同一Marker设置下，衰减或相位变化与期望一致；数字通过不能替代RF通过。')
p('最初调试步骤还要求16项逐写逐读，以及16项集中写后集中读两种顺序。本轮完成了后述实际记录中的扫描和写后读取，不等于这两种顺序对全部寄存器及三轮复位都已验收。未执行部分继续保留为后续任务。')
src('E04新码表比较与基线CSV；E07 s52全表；docs中的寄存器链说明。')

page('三 版本演进与对应产物')
table(['构建','已核实的主要变更与用途','对应验证'],[
('diag_sdo_raw','早期SDO观察基线；仍存在旧采样时序，构建早于10月30日初始化顺序调整','最初SDO全高，后续有效回读定位的对照'),
('l50','构建泛型LDB_LOW_CYCLES=50，即由100 ns延至1 µs；其余共同源码变更不以缺失历史快照推断','衰减未恢复；SDO出现可解码但右移一位'),
('s50','array_write_engine补采末位并移位对齐；加入延迟SDO回归','Control0=04、103=11；后发现86末位仍异常'),
('s51','第24个SCLK下降沿后新增100 ns CSB低保持，再补采末位并升高CSB','Control_Reg 512/512通过'),
('s52','扩展动态TX/RX读与24位read_value及done/error观测；集中验证五类初始化空间','2048/2048；动态16通道复测0/16'),
('s53','纳入chip_diag_op，增加debug-only 42独立单帧写与43独立LDB；保留s51采样保护','三轮040/080，LDB前后均零')],[.95,4.45,1.7],9.5)
p('归档另保留diag_sdo_fix前置产物，作为早期调试背景；没有充分独立源码快照支持逐行变更说明，不将它伪装为本轮有效回读后的主线版本。l50、s50、s51、s52、s53的综合输入均确认ENABLE_DEBUG_ILA=1、LDB_LOW_CYCLES=50。s53默认ENABLE_DIAG跟随ENABLE_DEBUG_ILA。')
h2('版本追溯限制')
p('Vivado历史工程使用add_files引用共享rtl文件，没有为每版复制独立RTL。当前找到的是历史BIT/LTX、综合输入文件清单、综合/实现日志和调试记录；无法提供可信的历史完整源码包或逐行diff。本次冻结最新s53源码及SHA256，并保留当次routed DCP，后续修改应以此为起点单独建版本。')
p('当前RTL文件最后修改时间早于s53综合开始，综合输入中包含chip_diag_op；这与构建日志共同支持其对应关系。归档的完整脚本目录包含后来新增的统计/交付脚本，这些不会改变已经构建的BIT。')
src('02_历史版本各版synthesis_inputs.tcl；版本产物清单.json；01_最新版s53/source_manifest.json。')

page('四 首次有效回读与右移一位定位')
h2('背景与目的')
p('早期diag_sdo_raw下载后，读J1控制地址0和RXATT地址31均报06。ILA确认每帧24个SCLK，目标读请求与占位正确，但SDO采样全部为1。用户确认只有SDO1有效并纠正飞线为U9.12至U9.37。之后供电/连接调整，l50下出现非全高SDO，开始具备位序分析条件。')
h2('可重现的位偏差')
table(['控制地址','FPGA原24次采样','完整期望响应','关系'],[
('0','060002','0C0004','右移1位'),
('116','063A2F','0C745F','右移1位'),
('103','063388','0C6711','右移1位且末位丢失')],[1.1,1.65,1.65,2.7],10)
p('地址103用于区分末位：第24个SCLK上升沿时FPGA看到SDO=0，而第24个下降沿附近及之后看到SDO=1。原引擎只采24次上升沿，收进首个旧位、未收最后新位。上述三个样例不能解释为寄存器实际数据整体右移；它们指出采样窗口与FPGA端数据到达时间不一致。')
h2('s50修正及当时结果')
p('array_write_engine在最后下降沿后、两个帧间后续SCLK之前再采一次SDO，将原移位寄存器左移一位并拼入末位。增加tb_array_write_sdo延迟位模型并纳入run_sim.ps1，ARRAY_WRITE_SDO_PASS及协议回归通过。s50下载DONE=1后，协议ILA捕获Control0返回04、地址103返回11，状态00。')
p('这里的“离线解码器”是读取ILA CSV并按选定采样规则拼24位帧的Python程序，不是芯片内功能，也不是证明FPGA一个系统周期采不完24位数据。SPI本来就是24个串行时钟逐位接收；问题是采样相位和末位窗口。')
p('不能把“补采后某两项正确”外推为所有寄存器完成验收。当时COM5回包仍不稳定，主要有效证据来自ILA，而非端到端串口成功响应。')
src('E01 output/diag_sdo_raw/SDO_在线复测_20261030.md；E02 output/s50/SDO_位对齐在线复测_20261030.md。')

page('五 s50供电与全高复现及批量扫描')
h2('重新上电后的复测')
p('10月31日首次连接时FPGA无ILA核，重新下载s50后恢复。用户随后发现阵面板未供电并恢复供电，FPGA配置又丢失，再次下载同一BIT。对芯片0控制地址116、0和芯片1地址0，SDI读请求和同CID占位正确，但两帧SDO仍FFFFFF。供电问题只能解释其中一段失败，不能解释恢复供电后所有全高。')
p('为回答“是否先写再读”，抓取复位初始化帧。四颗芯片控制地址0分别发送040004、140004、240004、340004；地址1分别040104、140104、240104、340104；地址2同理。此证据证明FPGA发过值04，仍不能单独证明TR芯片已接收。')
h2('短暂恢复后的批量结果')
p('供电与连接调整后，芯片0地址0重新读到原采样060002，补采结果0C0004。四颗芯片地址0均得到0C0004、1C0004、2C0004、3C0004。随后逐地址扫描0～24、四芯片共100项全部匹配。')
p('到地址25时，芯片0的两帧SDO呈全0，重构000001；芯片1呈全1。脚本停止。单独重试地址25及此前通过的地址0，芯片0均变FFFFFF。因此故障具有随现场状态变化的特点，不能把“地址25”认定为固定坏地址。该轮余下412项未验收。')
h2('当时排查措施与限制')
p('增加单项停止式扫描和独立解码脚本；检查JTAG target被占、COM5句柄及自动重连；用户曾暂停、复位及重新上电。由于芯片本体测不到，后续板级判断限于J1.20、U9飞线和FPGA端ILA，不能宣称芯片64脚已测到跳变。')
p('后来进一步检查发现s50在地址86得到03，而码表期望02。此时SDO并非全高，属于独立的末位采样问题，引出s51保护窗口修正。')
src('E03 output/s50/寄存器回读复测_20261031.md及同目录原始CSV、扫描日志。')

page('六 s51末位保护与控制寄存器全量通过')
h2('问题触发与RTL改动')
p('s50对控制地址86返回03而非02，引脚ILA显示末位在原补采点之后仍变化。s51不再在第24个下降沿立即结束CSB，而进入ST_FINAL：保持SCLK低、CSB低5个50 MHz时钟，即100 ns；窗口末端补采最后一位并升高CSB，再产生帧间两个完整时钟。')
p('此100 ns是用于给返回末位建立余量的工程参数，不是手册明确规定的最低数值。后续CSB高阶段的两个SCLK仍保留，状态机完成握手发生在保护和后续时钟完成之后，不与下一帧重叠。')
h2('验证链')
table(['检查','实际结果'],[
('延迟末位仿真','XSim通过，包含末位变化用例'),
('实现时序','WNS 2.383 ns，TNS 0，仅覆盖已约束路径'),
('帧内位数','两帧各24个CSB低期间的SCLK上升沿'),
('末位保护','第24下降沿至CSB上升为5个FPGA周期，即100 ns'),
('帧间要求','CSB高至下一帧之间有2个SCLK上升沿'),
('指定地址86','芯片2引脚重构2C5602，数据02'),
('全量Control_Reg','J1 4芯片×128地址=512项，通过512，失败0')],[1.7,5.4],10)
p('地址86、87、92、97等曾敏感项四颗芯片均通过。芯片0/1/3还在协议ILA捕获到数据字节02、状态00。芯片2的编号字节本身也为02，单纯按字节触发无法区分编号与数据，因此其通过依据使用全量引脚帧比较。')
h2('可支持与不能支持的结论')
p('支持s51在该次J1工作状态下，控制寄存器读值与码表一致，末位采样错误得到受控修正。不支持四类ATT/PS查表、动态幅相、RF衰减/移相均已通过；这些需要后续独立测试。')
src('E05 output/s51/verification_20261031.md；full_control_20261031/summary.csv；chip2_addr086_array_timing.csv。')

page('七 衰减及LDB板级测试完整记录')
p('下表读数来自用户对频谱仪的现场回复；后期明确为固定频率固定功率连续波、Marker峰值。不是程序自动采集的仪表文件，早期部分回复缺少确切时间及完整设置，按试验次序记录，不据此计算统计置信度。')
table(['试验条件','设置','现场读数 dBm','结论边界'],[
('原脉宽 单芯片RF1','00 → 1F','-56 → -56','未观察到衰减变化'),
('原脉宽 芯片3四路','全00 → 全1F','-54 → -54','未观察到衰减变化'),
('1 µs 芯片3 RF1','00 → 1F','-56 → -56','延长脉宽未恢复'),
('1 µs 芯片3四路','均1F','-54','通道数变化影响功率'),
('1 µs 芯片2和3八路','全1F → 全00','-50 → -50','八路同调仍无变化'),
('后续RF1对照','00 → 1F','-57 → -57','无稳定衰减变化'),
('通道关闭试验','关前 → 关后','-63 → -74','用户更正-63为关前'),
('RF1重新打开','00 → 0F','-57 → -57','中档索引无稳定变化'),
('RF1保持1F约20秒','1F','常见-58，曾跳至-65','波动不作为稳定衰减'),
('RF1单最高位','10','-57','未见独立最高位效应'),
('最终八路 芯片2和3','全00 → 全1F','-49 → -49','仍未验证衰减成功')],[1.75,1.35,1.65,2.35],9)
p('00、0F、10、1F均为十六进制索引。衰减索引1F=31，按标称0.5 dB步进对应15.5 dB，不等于6位索引的最大63。每次动态帧中衰减占D11～D6，相位占D5～D0；读取RXATT表的31号单元只能证明该表项，不证明动态索引31已进入并被LDB装载。')
p('LDB关联TR芯片低有效装载输入LDB/LDAC_N，资料标芯片62脚。用户在J1.24测得低脉冲约1 µs、3.3 V/0 V。它证明连接器有合适量级脉冲；不等于芯片管脚波形或片内二级寄存器已更新。没有完成独立移相仪表验收。')
src('用户现场回复；E06衰减无效与LDB脉宽核查；output/l50/；output/s51/attenuation_20261031/。')

page('八 s52五类初始化寄存器全量回读')
h2('新增观测与目标')
p('在s51末位保护基础上，s52扩展动态功能1/2读取，并直接观测完整24位read_value及read_busy/read_done/read_error，避免只看串口数据字节或只查RXATT。读取集中覆盖Control、TXPS、RXPS、TXATT、RXATT，与新工作簿独立展开的基线逐项比较。')
table(['空间','每颗芯片','四芯片检查数','本轮结果'],[
('Control_Reg','128','512','全部匹配'),('TXPS字节','128','512','全部匹配'),
('RXPS字节','128','512','全部匹配'),('TXATT','64','256','全部匹配'),
('RXATT','64','256','全部匹配'),('合计','512','2048','2048通过 0失败')],[1.8,1.2,1.7,2.4],10)
p('这是一轮上电初始化后的集中回读，不是每写一项立即读一项，也不是三次独立复位循环。因此“2048通过”应作为该次全表状态证据，不能改写为所有计划中的顺序及重复性验收都完成。')
h2('首次下载全高及恢复过程')
p('s52首次下载后曾出现SDO全高；40次重读和一次阵面复位未恢复。切换到s51，四颗芯片地址0读正确；再次切回s52也正确。没有闭合原因，不能把偶发全高归咎于s52功能改动。s53阶段再次发生首次全高，复位后恢复，说明仍需独立记录和追查读链启动状态。')
h2('构建与配置')
p('s52 BIT SHA256为399D005DCDC58423890F22027611A1DB405058CCF30BBAC598969BF9753AE7B4。实现WNS 3.077 ns、TNS 0。五项SPI属性检查通过，下载DONE=1。此配置不涉及U5固化；数字初始化全表通过也不能代替动态幅相和RF验证。')
src('E07 output/s52/verification_progress_20261031.md；direct_sweep/；output/register_baseline_20261031.csv。')

page('九 读流水与共享SDO策略的核对')
h2('读请求和回读结果为什么帧头相同')
p('手册规定：第N帧写入读请求，SYNC上升时准备SDO缓冲；第N+1帧输出该请求对应的数据。第N+1帧同时输入的SDI仍会执行。当前reader先发请求、再发正确目标CID的占位读帧，只在WAIT_DUMMY发布结果；WAIT_READ不发布结果。')
p('例如芯片3/RF2：写321040 → 请求3A1000 → 占位380000。若成功写入且功能2返回此前写入的幅相数据，期望3A1040。响应中的3A1与请求一致是寻址字段相同；低12位000而非040才是不匹配。仅凭整个响应恰好等于请求不能直接认定回显。')
h2('目标与非目标SDI')
p('读阶段：目标SDI分别发送读请求与同CID占位，其他SDI发送F80000。F80000不是手册明确要求的固定非目标帧，而是设计采用CID=F不匹配时不驱动共享SDO的隔离策略；需板级验证三态和实际CID。因为CSB/SCLK共享，非目标芯片仍会收到时钟并看到自身SDI上的24位，不能理解为它们没有收到帧。')
p('普通40写和s53诊断写阶段，非目标SDI使用各自正确CID的080000/180000/280000/380000。该策略与reader不同，需要后续一次只改变一种策略对照。现有证据不能证明存在或不存在多源驱动。')
h2('RTL和模型能够证明什么')
p('联合仿真实例化实际reader和底层core，故意让第一帧SDO数据错误、下一帧正确，验证发布的是第二帧；CID交错和非零数据向量通过。它证明状态机遵循模型中的流水关系，不证明实际芯片与该模型的读写语义完全一致。')
p('离线重构SDO与内部read_value一致，支持没有额外的软件搬移或结果选路错误。但离线算法沿用RTL采样规则，二者不是完全独立的采样正确性证明。是否应在读请求SDI数据区复写旧值，当前RTL没有这样做；现阶段还未完成填零与填原值的板级对照，不应凭文字推断宣布必须或禁止。')
src('E08 TR手册读写时序与RTL核对；sim/tb_chip_sdo_pipeline.sv；rtl/chip_sdo_reader.sv。')

page('十 动态幅相首次单通道与四通道读取')
h2('芯片3 RF1的具体事务')
table(['步骤','24位帧或观测','含义'],[
('写入','320040','CID3，RX功能2，通道0，衰减1，相位0'),
('装载','LDB低50 FPGA周期','FPGA侧1 µs，已观察core_load_done'),
('读请求','3A0000','请求RF1 RX幅相'),
('占位','380000','正确CID3，读写位1，其余零'),
('实际返回','3A0000','头/地址正确，数据区000'),
('按写值预期','3A0040','数据区应为040才构成该次写读匹配')],[1.1,2.1,3.9],10)
p('索引0写入后返回零自然匹配，不能用它验证非零数据进入寄存器。随后索引1返回仍为零；芯片0也出现相同行为。写RF2后再读取RF1～RF4，多次数据区为零。')
h2('RF2曾出现040的证据与修正')
p('后续某次芯片3/RF2写321040、请求3A1000、占位380000，得到3A1040，与期望一致。在首轮全通道统计中也出现同一通道匹配。由于没有保留该次写之前的可读旧值，不能证明这就是本次写引起的改变。')
p('“可能是旧状态”只是假设：指该次读出的040也可能在本次写前已经存在，或受当时状态影响；不是证明来自某次已知旧写入。复位后的多值测试和第二轮全16通道没有重复该成功，因此不再将RF2定义为稳定通过通道。')
h2('错误标志与数据比较的区别')
p('reader只校验返回CID、功能和地址，并不持有本次写值做比较。因此3A1000也可产生read_done=1、read_error=0。该状态说明响应格式校验通过，不说明321040已成功写入或LDB装载生效。')
src('E09 s52的chip3_rf1_att01_write.csv、chip3_rf1_dynamic_sdo.csv、chip3_dynamic_channel*.csv；E10首轮统计。')

page('十一 首轮J1全16通道统计')
p('板载s52。每个通道分别执行通道使能及RX幅相写，衰减索引01、相位00，期望低12位040；再发读请求和占位，保存写/读引脚ILA及内部读值。16项均捕获到读双帧，CID和通道头匹配，read_done=1、read_error=0。')
a=rows(ROOT/'output/s52/J1_all_channels_20261031_172029/summary.csv')
table(['芯片','RF','写帧','读请求','占位期间返回','数据匹配'],[(x['chip'],x['rf'],x['write_frame'],x['read_request'],x['sdo_return'],'是' if x['match']=='True' else '否') for x in a],[.5,.6,1.35,1.35,1.75,1.55],9.5)
p('共16项，1项匹配、15项不匹配。唯一匹配为芯片3/RF2，返回3A1040。其他均为目标正确的头和地址加000。它说明当时共享SDO不只是始终全高，也存在非零返回，但不足以建立动态写入可靠性。')
p('本轮没有重新下载BIT。每项的write_frame、read_request、dummy_frame、sdo_return、fpga_read_value和expected均在summary.csv/JSON；完整位流在同目录chip*_write/read相关CSV。')
src('E10 output/s52/J1_all_channels_20261031_172029/；docs/J1四芯片十六通道幅相写后回读统计_20261031.md。')

page('十二 复位后的多值对照和初始化抽查')
h2('为何复位后换值再测')
p('用户要求排查15项不匹配后，对芯片3/RF1和RF2分别写入衰减索引2、0、3、1，相位0，以080、000、0C0、040四种数据分离固定零值与真正写跟随。该组共8笔，FPGA引脚写帧、两帧读事务及内部读值均保存。')
table(['对象','写入数据序列','实际返回数据','判断'],[
('芯片3 RF1','080、000、0C0、040','全部000','非零均不匹配'),
('芯片3 RF2','080、000、0C0、040','全部000','此前040未复现')],[1.25,2.25,1.6,2.0],10)
p('全零写入的匹配属于必要的零值对照，不能计为成功改变寄存器。8笔低12位始终零，因此没有证据说明某个通道已恢复可靠动态写入。')
h2('同时核对初始化链是否整体失效')
p('对4个CID各读Control地址0、RXPS字节地址131、RXATT索引1，共12项：数据分别为04、40、004，全部正确。芯片3示例完整响应为3C0004、3D8340、3F0404。此抽查支持初始化与返回链没有整体失效，但不是重复2048项全表验收。')
h2('写入与LDB的引脚观测')
p('当时写波形CSB在样点577上升，LDB在610下降、660上升：CSB→LDB为33×20 ns=660 ns；LDB低为50×20 ns=1 µs。写帧之间CSB高包含两个SCLK上升沿。该证据属于FPGA数字端，不代表芯片焊盘已收到同样波形。')
p('综合这些结果，排查目标从“15个独立通道问题”转向动态幅相共用写/装载/读取行为。下一轮用每个通道不同数据，进一步排除误读同一目标和偶然零值匹配。')
src('E11 output/s52/J1_vary_data_20261031_172555/；E12 output/s52/init_spotcheck_20261031/。')

page('十三 第二轮J1全16通道唯一值复测')
p('复位后按芯片和通道组合依次写RX衰减索引01～10，即十进制1～16，相位均0。每项使用唯一的非零数据040、080……400，避免仅检查相同常量。下表占位帧均为目标CID加80000；完整逐项占位和内部值保存在统计CSV。')
a=rows(ROOT/'output/s52/J1_all_channels_20261031_174022/summary.csv')
table(['芯片 RF','索引','写入','读请求','实际响应','预期响应'],[(x['chip']+' '+x['rf'],f"{int(x['attenuation_index']):02X}",x['write_frame'],x['read_request'],x['sdo_return'],x['expected']) for x in a],[.9,.55,1.4,1.4,1.4,1.45],9.5)
p('结果0/16匹配。16项写帧、读请求、占位帧字段均符合目标，SDO重构与内部read_value一致；16项read_done=1、read_error=0，但所有返回低12位均000。先前RF2的040没有重现。')
p('这一轮比首轮更支持共性原因：不能再将结论表述为“只有RF2正常、其余15路异常”。正确表述应是“动态非零写后回读尚无可重复成功通道”。')
src('E13 output/s52/J1_all_channels_20261031_174022/summary.csv、summary.json和逐项decoded.json。')

page('十四 实际抓取时序与关键间隔')
p('以下图使用第二轮芯片3/RF2的实际ILA采样生成。写321380表示衰减索引0E、相位0；请求3A1000，占位380000；响应3A1000，预期3A1380。分段采集之间没有共同绝对时间轴，不将图中段间空白解释为真实软件等待。')
image=ROOT/'output/s52/J1_all_channels_20261031_174022/timing_chip3_rf2.png'
if image.exists():
 doc.add_picture(str(image),width=Inches(4.6))
 doc.paragraphs[-1].alignment=WD_ALIGN_PARAGRAPH.CENTER
table(['项目','FPGA侧观测或实现值'],[
('系统时钟','50 MHz，20 ns/周期'),('SCLK','5 MHz，200 ns/周期，高低各100 ns'),
('单帧','CSB低期间24个SCLK上升沿，MSB先行'),
('末位保护','第24下降沿后CSB继续低100 ns'),
('帧间','CSB高至少2个SCLK上升沿'),
('普通写后的装载','CSB上升至LDB下降660 ns，约3.3个SCLK周期'),
('LDB低','1 µs，50个FPGA周期；J1.24也由用户测到约1 µs')],[1.8,5.3],9.5)
p('660 ns由400 ns帧后时钟、约60 ns握手及200 ns装载保护构成，满足现有至少一个SCLK周期的间隔要求。s53独立LOAD与WRITE之间隔着读事务及软件调度，不能把660 ns当作s53分离实验的写到装载间隔。')
p('s53内部时序WNS 2.647 ns、WHS 0.020 ns、TNS 0；同时报告19个无输入延迟端口、151个无输出延迟端口。内部通过不证明TR芯片端SDI建立/保持和SDO返回采样余量满足所有条件。')
src('E13 timing_chip3_rf2.png/svg及原始CSV；E08时序核对；01_最新版s53/reports/timing_impl.rpt。')

page('十五 s53诊断RTL与构建验证')
h2('具体源码变更')
table(['文件或接口','本版纳入的行为'],[
('chip_diag_op.sv','新增IDLE/ISSUE/WAIT_DONE状态机；单帧只写或单独LOAD；使用原core握手，不自动将两者绑定'),
('protocol_v03_dispatcher.sv','增加debug诊断42/43分派、长度/目标/CID/读写方向校验及完成等待'),
('beam_ctrl_top.sv','接入诊断模块与core仲裁；ENABLE_DIAG默认随ENABLE_DEBUG_ILA'),
('42负载','[line,chip,frame_hi,frame_mid,frame_lo]；例如[0,3,32,10,40]发送321040'),
('43负载','[line]；例如[0]仅对RX J1产生LDB'),
('保留限制','42只允许写方向及正确CID；41读请求数据仍固定0，尚不能指定原值填充')],[1.65,5.45],9.5)
p('42负载示例中的32/10/40为十六进制字节，line/chip为0/3；外围UART阵面字段ARRAY=0选择RX。诊断写的非目标四路占位使用其自身正确CID。42操作不自动开通RF通道，因此本次实验只对数字寄存器作结论。')
h2('构建前后检查')
p('构建前run_sim.ps1回归覆盖协议及42写不触发LDB、43单独LDB、错误CID拒绝、SDO末位、TR时序、读流水、512帧初始化等，全部通过。芯片相关行为模型不是厂家模型；不以它证明芯片实际语义。')
p('构建泛型：ENABLE_DEBUG_ILA=1、LDB_LOW_CYCLES=50；flavor=s53。18:20:18完成实现报告，18:20:55 JTAG下载完成，DONE=1且识别两个ILA。BIT SHA256：83CF37BFFDB07A1673AC4493448A4E142C640C050CEF572EF43371E2CC34F9DD。未生成新MCS，未写U5或U22。')
p('继承SPI配置五项全部实查：CFGBVS=VCCO、CONFIG_VOLTAGE=3.3、CONFIG_MODE=SPIx1、BITSTREAM.CONFIG.SPI_BUSWIDTH=1、BITSTREAM.CONFIG.CONFIGRATE=3。')
src('E14 s53_prebuild_sim.log、s53_build.log、s53_program.log；rtl与综合输入清单；spi_config_properties.txt。')

page('十六 s53独立写与独立LDB实验')
h2('首次全高与有效实验的分界')
p('首次s53下载后，基线SDO全高、没有正常read_done。第一次用read_done触发导致等待，改用read_busy捕获错误路径后保留了整轮全高数据。这一轮不满足计划前置条件，应作废为动态寄存器证据；仅用于记录读链启动故障。目录182059和182232均不能与后续有效结果混算。')
p('随后通过RX J1复位命令并等待2秒，再读芯片3初始化抽查：Control0=3C0004，RXPS131=3D8340，RXATT1=3F0404，均read_done=1、read_error=0。动态RF2基线3A1000。有效采集目录isolate_20261031_182445。脚本随后加入基线无有效done即停止的保护。')
h2('执行次序与原始帧')
p('每轮先42只写321040、不发LDB → 41读3A1000/380000 → 43单独LDB → 再读同一目标；然后对321080重复。三个轮次共6组写入、12笔LDB前后回读。ILA核实每次写捕获恰好一帧且没有LDB下降沿；单独LOAD捕获恰好一个LDB下降沿且没有SPI帧。')
table(['轮次','只写帧','LDB前响应','LDB后响应','按写值预期'],[
('1','321040','3A1000','3A1000','3A1040'),('1','321080','3A1000','3A1000','3A1080'),
('2','321040','3A1000','3A1000','3A1040'),('2','321080','3A1000','3A1000','3A1080'),
('3','321040','3A1000','3A1000','3A1040'),('3','321080','3A1000','3A1000','3A1080')],[.55,1.55,1.65,1.65,1.7],10)
p('12笔回读均有单次read_done且无read_error；引脚第二帧SDO与内部值一致。结论：在当前41读帧规则下，独立写和独立LDB前后均未显示数据跟随，单靠LDB触发时机的改变没有解决零数据。仍不能区分写没有进入、读语义不同、读操作自身影响或芯片端装载未到达。')
p('串口bridge的SENT只代表PC字节已发送，不是协议成功应答。本轮有效执行证据使用ILA中的实际帧、引脚事件与done/error；完整UART TX/RX逐字节归档尚不完善。')
src('E15 output/s53/isolate_20261031_182445/summary.json及全部pins/result.csv；s53_isolate_reset.log。')

page('十七 当前证据支持的判断与未解问题')
table(['问题','已知证据','当前判断'],[
('SDO是否仍一直全高','s51/s52全表及s53有效抽查可返回非零；下载后又曾全高','具备回读能力，但启动/连接稳定性未闭合'),
('是否只是右移1位','s51增加末位保持；Control全表通过','旧采样问题已修正；不能解释当前有效头加零数据'),
('是否只读了RXATT','s52五类2048项通过','不是；动态幅相是另一空间'),
('是否取错第一帧','RTL WAIT_DUMMY才发布；两帧引脚保存；联合仿真通过','未发现该状态机错误，模型仍有语义局限'),
('是否寄存器都配置正确','初始化曾全表匹配；动态16路和s53多值不匹配','不能笼统宣布配置都正确'),
('是否仅LDB脉宽不足','1 µs实测；独立LDB前后仍零','单纯延长未解决；芯片端质量仍未测'),
('是否共享SDO争用','读非目标F80000，写非目标自身CID；缺少板级三态对照','合理待查项，尚未证实'),
('读数据是否必须复写原值','当前读填0；未做可控填充值对照','不能下结论，下一诊断重点'),
('是否RF已经通过','多档/多通道衰减未出现稳定对应变化','衰减未通过；移相未验收')],[1.45,3.6,2.05],9.5)
p('最值得优先验证的是“动态幅相读请求是否只选择地址，还是会按某种规则影响对应数据”。返回头和地址随目标正确、低12位总零这一现象，使读帧数据填零成为值得对照的因素，但它也完全可能与写未进入或读可见层级有关。现阶段应以受控帧实验区分，不以猜测再修改产品逻辑。')
p('如果需要向芯片厂家求助，应提供：芯片型号/资料版本、CID与MODE条件、写321040、读3A1000、占位380000、实际3A1000、LDB前后均零及初始化可读的对照，明确询问功能2读取的是哪一级、读数据字段是否有写入副作用及允许的后续帧格式。')

page('十八 接手后的逐步执行方案')
h2('先稳定基线')
p('1. 使用归档s53 BIT与同版LTX，只经JTAG下载。确认DONE和两个ILA；保持阵面供电、U9飞线和COM5独占。2. 执行RX J1复位初始化；读取CID3的Control0、RXPS131、RXATT1，期望3C0004、3D8340、3F0404。3. 对RF2连续读两次3A1000→380000，保留两帧原始SDO与内部值。全高、无done、error或两次不一致时停止动态推断，先定位供电/MODE/复位/共享线。')
h2('再对照读请求数据与三帧流水')
p('4. 当前s53无法指定读帧数据，需先新增debug-only可控原始帧或可控读数据入口；禁止直接改正常产品读规则并宣称修复。增加联合仿真验证CID校验、三帧返回归属与操作隔离，再按固定SPI配置构建新诊断版。5. 在初始化抽查正常后，对同一CID3/RF2交替只写321040和321080。分别比较请求数据填0与填原值，目标CID、功能、地址、SCLK和占位保持不变；必要时增加第三帧观察后续请求响应。')
p('6. 每一种填充值先不发LDB读取，再单独LDB后读取；每组至少三轮。保留写前旧值、每帧SDI/SDO、read_value和标志。只有响应随不同写入值重复变化，才将该组合定为动态数字通过。不要用零写零读或同一常量偶然匹配作结论。')
h2('随后隔离共享SDO与芯片端时序')
p('7. 依据厂家确认的非目标无效帧策略，每次只改变非目标SDI，比较返回头、数据和线电平。不能预设CID失配必定三态；需要示波器及驱动隔离证据。8. 若接口语义已确认而仍零，测J1 CLK/CSB/SDI/LDB、U9 DIR/OE及供电；芯片管脚不可达时明确限制，并寻求可接触的测试点或厂家板对照。')
h2('数字通过后才恢复RF验收')
p('9. 固定连续波及频谱设置，先单通道索引00/01/02/1F，逐档等待稳定，记录Marker常见值与波动范围；再按每通道唯一值复测16路。移相使用可测相位的仪器，不用功率变化替代。10. 最后至少三轮独立复位/初始化复测，完成全表及动态写读，再决定是否固化MCS。')

page('十九 最新版文件使用与重建')
p('原工程目录：D:\\beam_control\\beam_control_demo\\beam_contorl_demo\\beam_contorl_V0.3。交付包根目录下README_先读.md与版本产物清单.json是入口；全部引用证据在包内保留原output相对路径结构。')
table(['位置','用途与使用方式'],[
('01_最新版s53/source/rtl','全部当前RTL及rom，不只拷贝改动文件'),
('source/reference','BJN110计算相关依赖，复建必须随源码保留'),
('source/constr','主XDC及实现时钟布线例外'),
('source/scripts 和 sim','构建、下载、抓取、解码、回归与本报告生成脚本'),
('program/*.bit 与 *.ltx','原始s53下载BIT及匹配探针；不要与历史LTX混用'),
('checkpoint/beam_ctrl_top_routed.dcp','原实现后检查点，用于核查当次实现设计'),
('ila_ip/','原s53 ILA IP目录；通常由create_debug_ila.tcl重新生成'),
('reports/ 和 logs/','SPI属性、DRC、时序、利用率、构建和下载证据')],[2.5,4.6],9.5)
h2('重建步骤')
p('使用Vivado 2024.2，在source目录设置环境变量V03_ENABLE_ILA=1、V03_BUILD_FLAVOR=s53、V03_LDB_LOW_CYCLES=50。先运行scripts/run_sim.ps1；依次通过Vivado batch运行scripts/create_project.tcl和scripts/run_build.tcl。脚本检查五项SPI属性不匹配即报错；完成后核对BIT/LTX、时序及DRC再下载。')
p('原始BIT以本包SHA256为准；不同工具状态/重新实现可能产生不同BIT哈希，不要求复建逐字节相同。历史脚本含原机绝对路径、COM5和JTAG目标，移机先检查，不直接运行自动下载。构建脚本依赖目录结构，保留source中的rtl、constr、reference和scripts相对层级。')
h2('BIT与MCS继承规则')
p('五项固定属性必须为VCCO、3.3、SPIx1、1、3。本次只保留BIT，不新生成MCS。后续需固化时，按04目录中的U5配置固化与冷启动记录，由已审核BIT生成U5 16 MiB SPIx1、起始地址0的MCS，并核对掉电冷启动。不可将旧MCS误称为s53。')

page('二十 ILA配置与复核方法')
table(['ILA','探针与宽度','采样深度'],[
('ila_v03_protocol','probe0 rx_byte 8；probe1 valid 1；probe2 rx_index 6；probe3 frame_command 8；probe4 dispatcher_state 4；probe5 response_status 8；probe6 response_byte 8；probe7 response_valid 1；probe8四个状态4；probe9 read_value 24；probe10读状态3','配置4096'),
('ila_v03_array','probe0四路RX SDI 4；probe1 CLK 1；probe2 CSB 1；probe3 LDB 1；probe4 RSTN 1；probe5 RX R 1；probe6 channel_rx_frames低24位；probe7通道/core状态8；probe8 SDO1 1','配置8192')],[1.4,4.7,1.0],9.5)
p('两个ILA均用自由运行sys_clk 50 MHz。脚本可以选择1024等较小上传深度，不等于IP配置被修改。create_debug_ila.tcl末尾输出文字protocol=9为历史提示，实际属性C_NUM_OF_PROBES=11并由顶层实例确认，应以配置和LTX为准。')
h2('有效捕获与解码')
p('写帧用rx_csb_o_OBUF低触发；独立LDB用rx_ldb_o_OBUF低触发。读状态应使用read_busy触发，以便捕获错误事务；仅用read_done触发会在失败时一直等不到事件。s53有效采集用引脚触发位置64、结果触发位置128，深度1024。每次变更触发条件前清除上一项的比较值，避免CSB低与LDB低被同时AND而永不触发。')
p('按CSB下降/上升界定帧，确认CSB低期间24个SCLK上升沿。SDI按目标bit位置、MSB先行重构。SDO采用当前对齐规则去除首个旧样本并补CSB上升前的稳定末位。分别保存请求期间SDO和占位期间SDO，后者才与read_value比较。解码结果必须再分CID、功能、地址和数据，不只判断整个值是否看起来合理。')
p('对s53独立写核实一帧、无LDB下降；对独立LOAD核实无SPI帧、一个LDB下降；对读核实一笔done且无error。引脚路径和内部值一致仅是链内一致性，还应与不同相位采样和模拟波形对照，以免算法共享同一偏差。')
src('01_最新版s53/source/scripts/create_debug_ila.tcl；rtl/beam_ctrl_top.sv；s53_isolate_write_load.tcl；s53_summarize_isolation.py。')

page('二十一 版本产物哈希与归档可信度')
versions=json.loads((OUT/'版本产物清单.json').read_text(encoding='utf-8'))
for v in versions:
 bits=[a for a in v['artifacts'] if a['file'].endswith('.bit')]
 if not bits:continue
 a=bits[0]
 h2(v['version']+'  '+a['file_modified_local'].replace('T',' '))
 p(a['file'])
 z=p('SHA256 '+a['sha256'])
 for r in z.runs:r.font.size=Pt(8.7)
p('上列时间为产物文件的本地修改时间，不能代替每次实际下载时间。各版LTX的完整SHA256也在版本产物清单.json及SHA256SUMS.csv。每版目录中的BIT/LTX成对使用，历史报告保留原样，出现“当前版本”“尚未构建”应按其写作时点解读。')
p('本包对文件做完整性冻结，不增加历史证据：缺失的历史RTL、未采集的芯片管脚波形、未完成的UART原始应答以及未验收的RF移相均保持未完成状态。最新版source_manifest.json包含源文件路径、哈希和修改时间；交付包SHA256SUMS.csv覆盖最终交付文件，用于传输后逐项核验。')

page('二十二 原始证据索引与结论使用说明')
evidence=[
('E01','diag_sdo_raw/SDO_在线复测_20261030.md','最初全高、下载器与飞线背景'),
('E02','s50/SDO_位对齐在线复测_20261030.md','l50右移、s50补采及两项有效值'),
('E03','s50/寄存器回读复测_20261031.md','供电反复、100项通过后全高'),
('E04','root_logs/register_baseline_20261031.csv','新码表独立展开基线'),
('E05','s51/verification_20261031.md 与 full_control_20261031/','末位保护与512项通过'),
('E06','04目录 V03_衰减无效与LDB脉宽核查','脉宽理由、码表与RF限制'),
('E07','s52/direct_sweep/ 与 verification_progress_20261031.md','2048项集中回读'),
('E08','04目录 TR手册读写时序与RTL核对','读流水、CID、仿真与约束限制'),
('E09','s52/chip3_rf1_dynamic_sdo.csv 等','RF1动态零回读'),
('E10','s52/J1_all_channels_20261031_172029/','首轮1/16及逐项帧'),
('E11','s52/J1_vary_data_20261031_172555/','复位后两通道多值均零'),
('E12','s52/init_spotcheck_20261031/','四芯片12项抽查'),
('E13','s52/J1_all_channels_20261031_174022/','第二轮0/16与实际时序图'),
('E14','root_logs/s53_prebuild_sim.log 与 s53_*build/program.log','最新回归、构建、下载'),
('E15','s53/isolate_20261031_182445/','复位后有效三轮独立写和装载')]
table(['编号','包内路径提示','主要用途'],evidence,[.55,4.6,1.95],9)
p('除特别注明04目录外，上表相对路径以03_原始调试证据为根。用户现场读数仅来自对话，未虚构频谱仪自动导出文件。将本报告发给他人时应同时提供ZIP；单独发送Word仍可理解结论，但无法复核所有原始帧。')
p('截至本报告冻结时点：最新板载为s53；有效初始化抽查正常，动态幅相非零写后回读仍零；当前并未定位根因。后续应先完成读帧填充与寄存器可见层级对照，再推进共享SDO和芯片端信号验证，最后进行RF衰减与移相验收。')

path=OUT/'SDO回读与幅相控制调试交接报告.docx'
doc.save(path)
print('DOCX_CREATED',path,flush=True)
