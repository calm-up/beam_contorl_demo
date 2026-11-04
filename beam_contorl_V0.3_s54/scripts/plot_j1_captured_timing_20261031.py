"""Plot actual ILA samples; write and read are separate acquisitions."""
import csv
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

root = Path(__file__).resolve().parent.parent
source = root / 'output/s52/J1_all_channels_20261031_174022'
output = source / 'timing_chip3_rf2'
meta = json.loads((source / 'chip3_channel1_decoded.json').read_text())
plt.rcParams.update({'font.sans-serif': ['Microsoft YaHei', 'SimHei', 'DejaVu Sans'],
                     'axes.unicode_minus': False, 'font.size': 11})
fig = plt.figure(figsize=(17, 12), facecolor='#f7f9fc')
grid = fig.add_gridspec(3, 1, height_ratios=[3, 3, 1.35], hspace=.55)
fig.suptitle('J1 · 逻辑芯片 3 · RF2（通道编码 1）｜实际 ILA 抓取时序',
             fontsize=20, fontweight='bold', y=.97)
fig.text(.07, .925, 's52 · 2026-10-31 17:40   |   50 MHz 采样 / 20 ns   |   衰减索引 0E，相位 00，写入数据区 380', color='#42526b')
signals = [('rx_csb_o_OBUF[0:0]', 'SYNC / CSB', '#315ea8'),
           ('rx_clk_o_OBUF[0:0]', 'SCLK', '#7a61a8'),
           ('rx_sdi_o_OBUF[3:0]', 'SDI4 → 芯片3', '#168679'),
           ('rx_sdo_i_IBUF[0:0]', 'SDO 共享输入', '#b46616'),
           ('rx_ldb_o_OBUF[0:0]', 'LDB / LDAC_N', '#bb4264')]

def plot_capture(kind, slot, title):
    with (source / f'chip3_channel1_{kind}_pins.csv').open(encoding='utf-8-sig', newline='') as f:
        rows = list(csv.DictReader(f))[1:]
    ax = fig.add_subplot(grid[slot])
    ax.set_facecolor('white')
    times = [(i - 64) * .02 for i in range(len(rows))]
    for rowno, (key, label, color) in enumerate(signals):
        ybase = (4 - rowno) * 1.3
        values = [((int(r[key], 16) >> 3) & 1) if rowno == 2 else int(r[key], 16) for r in rows]
        ax.step(times, [ybase + .6 * v for v in values], where='post', color=color, lw=1.3)
        ax.text(-.6, ybase + .3, label, ha='right', va='center', color=color, fontweight='bold')
    for n, frame in enumerate(meta[kind]):
        left = (frame['start_sample']-64)*.02
        right = (frame['end_sample']-64)*.02
        ax.axvspan(left, right, color='#eef3fb', alpha=.6, zorder=0)
        label = ('使能写入' if n == 0 else '幅相写入') if kind == 'write' else ('读请求' if n == 0 else '占位帧 / 上次请求的响应')
        ax.text((left+right)/2, 6.4, f"{label}   SDI = {frame['sdi'][3]}", ha='center', fontsize=11, fontweight='bold')
        ax.text((left+right)/2, 1.0, f"SDO = {frame['sdo']}" + ('（本次回读）' if kind == 'read' and n == 1 else '（不作为本次读结果）'), ha='center', fontsize=10, color='#97500d')
    ax.set_xlim(-.35, 12.7)
    ax.set_ylim(-.5, 7)
    ax.set_yticks([])
    ax.set_xticks(range(0, 13))
    ax.grid(axis='x', color='#dbe3ef', lw=.7)
    ax.set_xlabel('相对本次抓取首个 SYNC 下降沿的时间 / µs')
    ax.set_title(title, loc='left', fontsize=14, fontweight='bold', pad=18)
    for spine in ['top','right','left']: ax.spines[spine].set_visible(False)
    if kind == 'write':
        # Measure the real capture transitions; do not substitute RTL defaults.
        edges = lambda key, a, b: [i for i in range(1,len(rows)) if int(rows[i-1][key],16)==a and int(rows[i][key],16)==b]
        cs_end = edges(signals[0][0],0,1)[-1]
        ld_start = edges(signals[4][0],1,0)[0]
        ld_end = edges(signals[4][0],0,1)[0]
        for a,b,y,text in [(cs_end,ld_start,2.4,f'SYNC↑ → LDB↓：{(ld_start-cs_end)*20} ns'),
                            (ld_start,ld_end,1.0,f'LDB 低脉宽：{(ld_end-ld_start)*20} ns')]:
            x1,x2=(a-64)*.02,(b-64)*.02
            ax.annotate('',xy=(x1,y),xytext=(x2,y),arrowprops={'arrowstyle':'<->','color':'#a82e50'})
            ax.text((x1+x2)/2,y+.16,text,ha='center',fontsize=9,color='#a82e50')
    else:
        ax.text(11.4, 4.4, '每帧 24 个 SCLK\nSYNC 高后有 2 个\n帧后 SCLK 上升沿', ha='center', fontsize=10, color='#42526b')
    return ax

plot_capture('write', 0, '① 写入抓取：通道使能 → 幅相写入 → LDB 装载')
plot_capture('read', 1, '② 回读抓取：读请求 → 同 CID 占位帧；仅取第二帧 SDO')
ax = fig.add_subplot(grid[2]); ax.axis('off'); ax.set_xlim(0,24); ax.set_ylim(-.6,2.8)
fields = [(0,4,'CID','3','#dfeafb'),(4,1,'读写','1','#e8e0f3'),(5,3,'功能','010 RX','#e8e0f3'),
          (8,4,'通道','1','#d9eee8'),(12,12,'实际数据区','000','#fae1e2')]
for left,width,label,value,color in fields:
    ax.add_patch(Rectangle((left, .8),width,1.2,facecolor=color,edgecolor='white',lw=2))
    ax.text(left+width/2,1.65,label,ha='center',fontsize=10)
    ax.text(left+width/2,1.13,value,ha='center',fontweight='bold',fontsize=12)
ax.text(0,2.4,'③ 第二帧返回值：3A1000 ＝ FPGA read_value；预期：3A1380',fontsize=13,fontweight='bold')
ax.text(0,0,'帧头 / 通道匹配；数据区 000 ≠ 写入 380。SDO 按当前 RTL 的采样规则解码。',fontsize=11,color='#a43241')
fig.text(.07,.025,'说明：①与②来自两次独立 ILA 抓取，不能据图推断写入到回读的实际间隔。波形为 FPGA 侧数字采样，不表示模拟电压或芯片管脚电平。',fontsize=10,color='#536079')
fig.subplots_adjust(left=.15,right=.97,top=.88,bottom=.07)
fig.savefig(output.with_suffix('.png'),dpi=160,facecolor=fig.get_facecolor())
fig.savefig(output.with_suffix('.svg'),facecolor=fig.get_facecolor())
print(output.with_suffix('.png'))
