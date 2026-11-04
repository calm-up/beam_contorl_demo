from pathlib import Path
import shutil, json, hashlib, csv, re
from datetime import datetime

ROOT=Path(__file__).resolve().parents[1]
DEST=Path(r'D:\beam_control\交付归档\SDO调试交接_20261031')
DEST.mkdir(parents=True,exist_ok=True)
VERSIONS=['diag_sdo_raw','diag_sdo_fix','l50','s50','s51','s52','s53']

def copy(src,dst):
    if src.is_dir():
        shutil.copytree(src,dst,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    elif src.exists():
        dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)

for folder in ['rtl','constr','scripts','sim','reference']:
    copy(ROOT/folder,DEST/'01_最新版s53'/'source'/folder)
copy(ROOT/'README.md',DEST/'01_最新版s53'/'source/README_原工程.md')
copy(ROOT/'docs',DEST/'04_原始说明与计划')
chip_data=Path(r'D:\beam_control\软件\软件\芯片资料')
for name in ['10405W_12_18_HP_SPI裸片详测码表_20261028.xlsx','CCAR10405L数据手册V2.1_20261027_博海.pdf','TandR_SPI_datasheet_CCARX01.pdf']:
    copy(chip_data/name,DEST/'05_芯片资料'/name)
versions=[]
for v in VERSIONS:
    copy(ROOT/'output'/v,DEST/'03_原始调试证据'/v)
    copy(ROOT/'reports'/v,DEST/'02_历史版本'/v/'reports')
    synth=ROOT/'build'/v/'beam_control_v03.runs/synth_1/beam_ctrl_top.tcl'
    copy(synth,DEST/'02_历史版本'/v/'synthesis_inputs.tcl')
    copy(ROOT/'build'/v/'beam_control_v03.runs/synth_1/runme.log',DEST/'02_历史版本'/v/'synthesis_run.log')
    copy(ROOT/'build'/v/'beam_control_v03.runs/impl_1/runme.log',DEST/'02_历史版本'/v/'implementation_run.log')
    t=synth.read_text(errors='replace') if synth.exists() else ''
    generic=[line for line in t.splitlines() if line.startswith('set_property generic')]
    sources=re.findall(r'\S+/rtl/[^\s]+',t)
    artifacts=[]
    for f in sorted((ROOT/'output'/v).glob('*')):
        if f.suffix.lower() in ('.bit','.ltx'):
            copy(f,DEST/'02_历史版本'/v/f.name)
            if v=='s53': copy(f,DEST/'01_最新版s53'/'program'/f.name)
            artifacts.append({'file':f.name,'sha256':hashlib.sha256(f.read_bytes()).hexdigest().upper(),'bytes':f.stat().st_size,'file_modified_local':datetime.fromtimestamp(f.stat().st_mtime).isoformat(timespec='seconds')})
    versions.append({'version':v,'generic':generic,'artifacts':artifacts,'source_paths_in_synthesis_log':sources,'historical_rtl_snapshot_available':v=='s53'})

for f in (ROOT/'output').iterdir():
    if f.is_file() and (f.suffix.lower() in ['.log','.jou','.csv','.json','.md']):
        copy(f,DEST/'03_原始调试证据'/'root_logs'/f.name)
copy(ROOT/'output/codebook_20261030',DEST/'03_原始调试证据'/'codebook_20261030')
copy(ROOT/'output/l50',DEST/'03_原始调试证据'/'l50')
for file in ['beam_ctrl_top_routed.dcp','beam_ctrl_top.tcl']:
    copy(ROOT/'build/s53/beam_control_v03.runs/impl_1'/file,DEST/'01_最新版s53'/'checkpoint'/file)
copy(ROOT/'reports/s53',DEST/'01_最新版s53'/'reports')
for name in ['s53_create.log','s53_build.log','s53_program.log','s53_prebuild_sim.log','s53_isolate_reset.log']:
    copy(ROOT/'output'/name,DEST/'01_最新版s53'/'logs'/name)
copy(ROOT/'build/s53/beam_control_v03.srcs/sources_1/ip',DEST/'01_最新版s53'/'ila_ip')

latest=[]
for folder in ['rtl','constr','reference','scripts','sim']:
    for p in sorted((ROOT/folder).rglob('*')):
        if p.is_file() and '__pycache__' not in p.parts:
            latest.append({'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest().upper(),'modified_local':datetime.fromtimestamp(p.stat().st_mtime).isoformat(timespec='seconds')})
(DEST/'01_最新版s53'/'source_manifest.json').write_text(json.dumps(latest,ensure_ascii=False,indent=2),encoding='utf-8')
(DEST/'版本产物清单.json').write_text(json.dumps(versions,ensure_ascii=False,indent=2),encoding='utf-8')

readme='''# SDO 调试交接归档

先读《SDO回读与幅相控制调试交接报告.docx》。本包冻结截至2026-10-31 18:24的板级结果；归档操作不改变板上配置。

## 最新可用调试版本
01_最新版s53/program/beam_control_v03_s53.bit 必须搭配同目录 beam_control_v03_debug.ltx。
source/ 含最新版RTL、ROM、约束、依赖参考源码、构建和调试脚本、仿真。checkpoint/ 含当次实现的routed DCP。
source_manifest.json冻结本次源码哈希；当前RTL最后修改早于s53综合开始。历史构建引用共享rtl目录，未找到逐版本独立RTL快照；不能把当前RTL当作s50/s51/s52源码，也不提供伪造的逐行diff。
02_历史版本/保留各版BIT、LTX、综合输入及报告；03_原始调试证据/保留逐次ILA CSV、解码JSON、统计与日志；04_原始说明与计划/保留历史说明（其中“当前版本”“尚未构建”字样以报告时点为准）。

## 复建s53
在01_最新版s53/source目录用PowerShell设置：
$env:V03_ENABLE_ILA='1'
$env:V03_BUILD_FLAVOR='s53'
$env:V03_LDB_LOW_CYCLES='50'
依次用Vivado2024.2执行 scripts/create_project.tcl、scripts/run_build.tcl。
复建可产生功能相同的新产物，工具运行差异可导致BIT哈希不同；原始下载BIT以归档哈希为准。

SPI固定属性：CFGBVS=VCCO，CONFIG_VOLTAGE=3.3，CONFIG_MODE=SPIx1，SPI_BUSWIDTH=1，CONFIGRATE=3。
本包未新生成MCS，未写U5/U22。后续MCS须从审核通过的BIT生成，按16MiB SPIx1、地址0执行继承工作流。

## 已知脚本限制
历史抓取脚本含原机绝对路径和COM5、JTAG序列号，移机先修改路径/端口，不直接运行自动下载脚本。
串口bridge的SENT仅证明PC写出，不是芯片或FPGA成功应答。s53首轮在SDO全高时采集的分离实验作废，证据保留；182445目录才是复位后有效三轮。
校验SHA256SUMS.csv以检查文件传输完整性。仅包含交付文件；渲染预览不属于交付包。
'''
(DEST/'README_先读.md').write_text(readme,encoding='utf-8')
print('PACKAGE_STAGED',DEST,flush=True)
