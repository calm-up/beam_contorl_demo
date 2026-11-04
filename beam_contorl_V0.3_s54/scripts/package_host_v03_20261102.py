from pathlib import Path
import shutil,hashlib,csv,json,zipfile
from datetime import datetime

root=Path(__file__).resolve().parents[1]
runtime=root/'output/host_v03'
source=Path(r'D:\beam_control\beam_control_host_qt')
dest=root/'output/host_v03_delivery_20261102'
dest.mkdir(parents=True,exist_ok=True)
shutil.copytree(runtime,dest/'工具_host_v03',dirs_exist_ok=True)
for folder in ['src','tests']:
 shutil.copytree(source/folder,dest/'源码_现存版本'/folder,dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.exe','*.o','__pycache__'))
for name in ['CMakeLists.txt','README.md','.gitignore','界面预览.png']:
 if (source/name).exists():shutil.copy2(source/name,dest/'源码_现存版本'/name)
docs=dest/'协议资料';docs.mkdir(exist_ok=True)
for name in ['V03协议_按110对齐实施版.md','V03阶段2协议与安全态冻结_20261028.md']:
 if (root/'docs'/name).exists():shutil.copy2(root/'docs'/name,docs/name)
meta={'packaged_local_date':'2026-11-02','runtime_source':str(runtime),'source_directory':str(source),'exact_runtime_source_mapping_verified':False,'files':[]}
for p in [runtime/'beam_control_host.exe',source/'build/beam_control_host.exe',source/'release/beam_control_host.exe',source/'src/mainwindow.cpp',source/'src/protocol.cpp']:
 if p.exists():meta['files'].append({'path':str(p),'modified_local':datetime.fromtimestamp(p.stat().st_mtime).isoformat(timespec='seconds'),'sha256':hashlib.sha256(p.read_bytes()).hexdigest().upper()})
(dest/'版本来源说明.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
(dest/'README_先读.md').write_text('''# host_v03 上位机工具与现存源码

## 运行
打开 工具_host_v03/beam_control_host.exe。该目录完整复制自用户指定的output/host_v03，含Qt6 DLL、MinGW运行库、platforms和其他插件及翻译文件。不要单独移动EXE。
本次只复制打包，没有启动程序或连接串口、发送硬件命令。

## 源码
源码_现存版本/包含D:/beam_control/beam_control_host_qt中的src、tests、CMakeLists.txt及原README，保持原内容。
重要：工具EXE修改时间为2026-10-29；现存mainwindow.cpp及其build目录EXE为10-23版本，且EXE哈希不同。当前未找到能证明与host_v03工具EXE精确对应的10-29源码快照。因此本包提供工具原件与找到的现存源码，不能声称二者是精确的一次构建配对。不要直接以现存源码覆盖工具目录里的EXE。
原README可能包含历史功能状态，解释当前硬件能力时应核对FPGA协议资料与实际板载版本。

## 编译
要求C++17、CMake>=3.21、Qt6>=6.5（Core/Widgets/SerialPort）。原构建缓存记录为Qt6.8.3 MinGW64、MinGW13.1；Qt与编译器需使用匹配套件。
不包含完整Qt SDK和编译器；工具目录已带运行依赖。
在源码_现存版本目录执行（路径自行替换）：
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH="<Qt套件目录>" -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF
cmake --build build
如要跑测试，将BUILD_TESTING=ON并安装同版Qt Test，然后执行ctest --test-dir build --output-on-failure。
编译后的EXE如需部署，使用同版Qt的windeployqt整理依赖。

## 完整性
SHA256SUMS.csv覆盖包内文件，版本来源说明.json记录来源、时间与关键哈希。协议资料目录附工程现有V0.3协议说明。
''',encoding='utf-8')
files=sorted(p for p in dest.rglob('*') if p.is_file() and p.name!='SHA256SUMS.csv')
with (dest/'SHA256SUMS.csv').open('w',encoding='utf-8-sig',newline='') as f:
 w=csv.writer(f);w.writerow(['relative_path','bytes','sha256'])
 for p in files:w.writerow([p.relative_to(dest).as_posix(),p.stat().st_size,hashlib.sha256(p.read_bytes()).hexdigest().upper()])
for p in runtime.rglob('*'):
 if p.is_file():assert hashlib.sha256(p.read_bytes()).digest()==hashlib.sha256((dest/'工具_host_v03'/p.relative_to(runtime)).read_bytes()).digest()
archive=root/'output/host_v03_源码与工具_20261102.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for p in sorted(dest.rglob('*')):
  if p.is_file():z.write(p,dest.name+'/'+p.relative_to(dest).as_posix())
with zipfile.ZipFile(archive) as z:
 assert z.testzip() is None
 print('FILES',len(z.infolist()))
print('ZIP',archive,'MB',round(archive.stat().st_size/1e6,2))
print('RUNTIME_COPY_HASH_CHECK_PASS ZIP_CRC_PASS')
