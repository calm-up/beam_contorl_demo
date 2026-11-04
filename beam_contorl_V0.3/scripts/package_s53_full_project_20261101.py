from pathlib import Path
import shutil,hashlib,json,csv,zipfile,sys

ROOT=Path(__file__).resolve().parents[1]
FROZEN=Path(r'D:\beam_control\交付归档\SDO调试交接_20261031\01_最新版s53')
DEST=Path(r'D:\beam_control\交付归档\S53_Vivado_Project_20261101')
EXPECTED='83CF37BFFDB07A1673AC4493448A4E142C640C050CEF572EF43371E2CC34F9DD'
def copy(a,b):
 if a.is_dir():shutil.copytree(a,b,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','*.pyc','*.lock'))
 else:b.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(a,b)

if len(sys.argv)>1 and sys.argv[1]=='zip':
 assert (DEST/'reports/project_portability_check.txt').exists()
 assert 'PROJECT_PORTABILITY_PASS' in (DEST/'reports/project_portability_check.txt').read_text()
 files=sorted(p for p in DEST.rglob('*') if p.is_file() and p.name!='SHA256SUMS.csv')
 with (DEST/'SHA256SUMS.csv').open('w',encoding='utf-8-sig',newline='') as h:
  w=csv.writer(h);w.writerow(['relative_path','bytes','sha256'])
  for p in files:w.writerow([p.relative_to(DEST).as_posix(),p.stat().st_size,hashlib.sha256(p.read_bytes()).hexdigest().upper()])
 archive=DEST.with_suffix('.zip')
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for p in sorted(DEST.rglob('*')):
   if p.is_file():z.write(p,DEST.name+'/'+p.relative_to(DEST).as_posix())
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None
  print('ZIP_FILES',len(z.infolist()))
 digest=hashlib.sha256(archive.read_bytes()).hexdigest().upper()
 archive.with_suffix('.sha256.txt').write_text(digest+'  '+archive.name+'\n',encoding='utf-8')
 print('ZIP_MB',round(archive.stat().st_size/1e6,2),'SHA256',digest)
 sys.exit()

DEST.mkdir(parents=True,exist_ok=True)
for folder in ['rtl','constr','reference','sim','scripts']:copy(FROZEN/'source'/folder,DEST/folder)
copy(ROOT/'build/s53',DEST/'build/s53')
copy(FROZEN/'program',DEST/'output/s53')
copy(FROZEN/'reports',DEST/'reports/s53')
copy(FROZEN/'logs',DEST/'logs/s53')
copy(FROZEN/'source_manifest.json',DEST/'s53_frozen_source_manifest.json')
for name in ['V03_U5配置固化与冷启动操作记录_20261029.md','TR手册读写时序与RTL核对_20261031.md']:
 copy(ROOT/'docs'/name,DEST/'docs'/name)
for row in json.loads((FROZEN/'source_manifest.json').read_text(encoding='utf-8')):
 p=DEST/row['path']
 assert p.exists(),row['path']
 assert hashlib.sha256(p.read_bytes()).hexdigest().upper()==row['sha256'],row['path']
assert hashlib.sha256((DEST/'output/s53/beam_control_v03_s53.bit').read_bytes()).hexdigest().upper()==EXPECTED

(DEST/'Open_S53.tcl').write_text('set root [file dirname [file normalize [info script]]]\nopen_project [file join $root build s53 beam_control_v03.xpr]\n',encoding='utf-8')
(DEST/'README_先读.md').write_text('''# S53 完整 Vivado 工程

解压整个文件夹，使用 Vivado 2024.2 打开：
build/s53/beam_control_v03.xpr
也可在 Vivado Tcl Console 执行 source Open_S53.tcl（先切换到包根目录）。
不要只移动XPR：它通过../../rtl、../../constr、../../reference引用同包源码。

## 内容
- rtl/：2026-10-31冻结的s53 RTL及ROM。
- reference/：BJN110算法依赖；constr/：XDC约束。
- build/s53/：原XPR、srcs中的ILA IP、gen、ip_user_files、cache、hw和runs综合实现产物。
- output/s53/：原s53 BIT及匹配LTX。
- reports/s53/、logs/s53/：原构建、时序、SPI属性及下载日志。
- sim/、scripts/：冻结版本仿真与构建/调试工具。
- s53_frozen_source_manifest.json：原冻结文件哈希；SHA256SUMS.csv：本包传输完整性校验。

## 版本与功能边界
器件xc7a200tfbg484-1，top=beam_ctrl_top。
综合泛型ENABLE_DEBUG_ILA=1、LDB_LOW_CYCLES=50；独立42写/43装载已纳入。
本包是s53，不包含11月1日提出的RAW4/44诊断接口或SDI策略改动。
初始化回读曾通过，动态幅相非零写后回读仍未闭环；不是RF已验收发布版本。

## 构建与下载
完整保留目录结构。PowerShell设置：
$env:V03_ENABLE_ILA='1'
$env:V03_BUILD_FLAVOR='s53'
$env:V03_LDB_LOW_CYCLES='50'
按顺序运行scripts/run_sim.ps1，Vivado batch执行scripts/create_project.tcl、scripts/run_build.tcl。
重新create_project会重建同名工程；先备份自己的改动。
保留的runs中原始runme/Tcl日志可能含原机绝对路径，不直接执行旧runme.bat；使用工程内Reset/Launch Runs或上述项目构建脚本重新生成任务。
现场抓取/下载脚本也可能含原机路径、COM5及JTAG序列号，移机后先调整。
BIT必须搭配output/s53下同一版LTX。

固定SPI属性：CFGBVS=VCCO，CONFIG_VOLTAGE=3.3，CONFIG_MODE=SPIx1，SPI_BUSWIDTH=1，CONFIGRATE=3。
未附新MCS；本次打包未连接或改写板卡。未来MCS按docs的U5继承工作流生成。
原BIT SHA256：'''+EXPECTED+'\n',encoding='utf-8')
(DEST/'scripts/validate_s53_project.tcl').write_text('''set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root build s53 beam_control_v03.xpr]
set report [open [file join $root reports project_portability_check.txt] w]
puts $report "Vivado=[version -short]"
puts $report "PART=[get_property PART [current_project]]"
puts $report "TOP=[get_property TOP [get_filesets sources_1]]"
puts $report "GENERIC=[get_property GENERIC [get_filesets sources_1]]"
set missing 0
set outside 0
foreach f [get_files -all] {
 set path [file normalize [get_property NAME $f]]
 if {![file exists $path]} {puts $report "MISSING $path"; incr missing}
 if {[string first [string tolower "$root/"] [string tolower $path]] != 0} {puts $report "OUTSIDE $path"; incr outside}
}
puts $report "MISSING_COUNT=$missing OUTSIDE_COUNT=$outside"
if {$missing == 0 && $outside == 0} {puts $report "PROJECT_PORTABILITY_PASS"}
close $report
close_project
if {$missing != 0 || $outside != 0} {error "Project dependencies failed: missing=$missing outside=$outside"}
puts "PROJECT_PORTABILITY_PASS"
''',encoding='utf-8')
print('S53_STAGED',DEST,flush=True)
