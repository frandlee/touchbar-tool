# Touchbar Tool 0.8.2

轻量 Swift/AppKit 菜单栏 Touch Bar 工具。在指定应用处于前台时显示五个按钮，切换应用后收起，并保留 Control Strip。目标默认 bundle ID 为 `com.openai.codex`，只能按应用匹配，不能区分应用内的模式。

## 配置表格

CTB → **编辑配置** 打开应用内表格，每行编辑一个按钮的显示标题和发送文案。可设置允许粘贴、验证后自动回车及回车延迟，点击 **保存并生效** 即时更新。取消关闭窗口不保存；重复打开已显示窗口保留草稿。外部文件已变化时拒绝覆盖，请关闭编辑窗口、重新加载后再编辑。

每个应用可独立增删按钮，保留至少1个、最多20个。内部ID自动生成并保持稳定。标题为1～20个字符，发送文案最多2000字符；都不能仅空白或含换行、控制字符。自动回车延迟为200～1500毫秒，默认400。

底层保存为JSON，日常使用无需手工编辑。`config.example.json`是通用安全示例，粘贴和自动回车默认关闭。个人配置、运行日志和构建目录不进入仓库。

## 构建与运行

需要macOS和Apple Command Line Tools，无第三方构建依赖。使用Swift 5语言模式，链接AppKit/ApplicationServices。

```sh
./scripts/build.sh
./scripts/test.sh
codesign --verify --strict build/TouchbarTool.app
open build/TouchbarTool.app
```

输出为`build/TouchbarTool.app`，版本0.7.0（build 12）。内部可执行文件`CodexTouchBar`，bundle ID `local.codex-touchbar.prototype`，默认使用钥匙串中的唯一有效代码签名证书。构建首次从通用示例生成根目录个人配置，仅在运行配置不存在时复制到`build/config.json`，不会覆盖已有运行配置。

GUI默认读取`build/config.json`；启动时设置`CODEX_TOUCHBAR_CONFIG`可指定其他文件，编辑和重载始终使用该次启动确定的路径。CTB → **重新加载配置** 可加载外部文件修改；失败时保留旧配置。编辑、保存、重载均取消待发送任务，旧任务不会复活。

更新正在运行的App前应先退出并备份个人配置和旧App。重签可能使辅助功能授权失配，即使系统开关仍开启，也应检查新版GUI诊断；需要时经用户批准重新添加同一构建，不重置其他App权限。

## 粘贴与自动回车

启用粘贴后按钮向同一目标PID发送⌘V，会覆盖剪贴板，不读取或恢复原剪贴板。自动回车还要求同一前台PID、普通输入框、辅助功能及事件发送权限、焦点观察、光标范围和刚插入片段验证全部通过。拒绝密码输入框，不读取整个聊天输入框，不保存聊天正文。

连续两次验证通过并达到延迟后才发送一次Return；应用/输入框切换、剪贴板变化、禁用、睡眠、权限丢失或超时会取消。忽略同一输入框的重复焦点通知，切回不会恢复旧任务。无法验证时安全回退为仅粘贴，不盲发Return。最终检查和系统事件仍存在极短竞态，目标快捷键行为及其他应用未全面验证。

按钮只是插入和可选发送配置文案，不直接执行Git或部署API；目标应用可能根据文案执行任务。不要使用“合并”等有后果指令做发送验收。

## 登录启动及诊断

登录启动是可选的当前用户LaunchAgent，仅Aqua会话，RunAtLoad，无KeepAlive。手动退出后不会立即拉起。

```sh
./scripts/login-start.sh status
./scripts/login-start.sh enable
./scripts/login-start.sh disable
```

启用拒绝覆盖已有启动项；停用不终止已运行App。移动App前需停用，再按新路径启用。下一次自然登录自动启动尚未实际观察。

```sh
build/TouchbarTool.app/Contents/MacOS/CodexTouchBar --status
build/TouchbarTool.app/Contents/MacOS/CodexTouchBar --probe
build/TouchbarTool.app/Contents/MacOS/CodexTouchBar --permissions
open build/TouchbarTool.app --args --diagnostics
```

`--status`只读保存的无正文运行状态；`--probe`和`--permissions`不展示Touch Bar、不请求权限、不访问目标UI。CLI与GUI权限身份可能不同，实际授权以GUI实例为准。

## 验证与兼容性

199项检查：59项配置与应用匹配、97项自动发送保护/离屏输入模拟、39项重载及保存保护、4项标题布局。0.7.0构建及严格签名检查通过，表格窗口布局和字段已核实；该版本真实目标发送未重新验收。较早版本自动回车已由用户实机确认，不能视为所有系统和应用兼容保证。

跨应用Touch Bar依赖私有`presentSystemModalTouchBar:systemTrayItemIdentifier:`和`dismissSystemModalTouchBar:`，旧FunctionBar名称为后备。桥接核对签名并保护Objective-C异常；无法保证硬件显示或防止全部底层崩溃。未修改系统Touch Bar偏好，不申请录屏、输入监控或Apple Events权限。

参考：[NSTouchBar官方文档](https://developer.apple.com/documentation/appkit/nstouchbar)、[MTMR接口用法](https://github.com/Toxblh/MTMR/blob/master/MTMR/TouchBarController.swift)、[EnergyBar接口声明](https://github.com/billziss-gh/EnergyBar/blob/master/src/System/NSTouchBar%2BSystemModal.m)。桥接独立实现，未引入这些实现文件或依赖。

仓库尚未指定LICENSE；公开可见不等于授予开源使用许可。


## 多应用配置

编辑窗口顶部可添加已安装应用、选择应用及移除配置；至少保留一个应用。每应用独立保存1～20个按钮、粘贴开关、自动回车和延迟。新增应用允许粘贴、默认不自动回车，使用“按钮1”至“按钮5”占位标题和文案，按需求编辑后保存。切换应用保留有效草稿，取消关闭不保存。

按前台应用bundle ID匹配配置，切换后更新按钮并取消旧发送任务；未配置应用收起。旧schemaVersion=2文件兼容，新应用存于可选applications数组，重复应用或嵌套配置拒绝。多应用匹配和保存回读已验证；不同应用输入框及自动回车仍需逐应用实机验证，无法验证时仅粘贴。


## 0.7.0

配置表格第一列显示“按钮 1～5”，隐藏内部业务ID。内部ID和现有配置兼容，按钮发送行为不变。


## 每应用独立按钮数量

编辑窗口提供“增加按钮”及每行“删除”，表格可滚动。按钮顺序由配置列表决定，删除中间行保留其余按钮ID及文案。保存后取消旧发送任务并重建Touch Bar，避免旧缓存错用位置。旧配置兼容，新增按钮为占位标题和文案，可编辑后保存。


## 0.8.0 完整应用入口

保留菜单栏CTB控制入口，并支持Dock应用图标。普通启动默认打开配置窗口，关闭窗口不退出工具；点击Dock或重新打开App恢复配置窗口。标准菜单支持编辑配置、剪切/复制/粘贴、关闭窗口和退出。

应用图标为银色MacBook铝合金背景、黑色贯穿Touch Bar、彩色小符号，Assets/AppIcon.png和AppIcon.icns由内置imagegen生成，最终提示词见Assets/AppIcon.prompt.txt。构建将.icns打包到Resources并声明CFBundleIconFile。

显示标题直接支持“中⇄日”等Unicode文字，不再根据“中日翻译”标题自动替换图像。发送文案与显示标题独立，行为不变。

新登录启动项使用--background保持后台启动。已有登录项应先disable再enable更新参数，不终止运行App。默认菜单栏＋Dock模式保留原bundle ID及配置路径，升级前退出并保留个人配置。


## 0.8.1 菜单栏图标

菜单栏CTB文字改为带三个按键的单色Touch Bar图标，自动适应浅色/深色，保留工具提示和辅助功能名称，菜单功能及发送行为不变。


## 0.8.2 稳定签名

构建默认复用钥匙串唯一有效代码签名身份，以稳定的designated requirement识别更新后的App。没有身份或存在多个身份时在编译前停止，请设置TOUCHBAR_SIGNING_IDENTITY为所选有效身份名称/哈希。显式TOUCHBAR_SIGNING_IDENTITY=-可生成ad-hoc构建，但更新可能使隐私授权失配；不会静默回退。签名后自动执行严格验证。

从ad-hoc首次切换证书时可能需要重新授权一次；随后保持同一证书身份及bundle ID更新通常可沿用权限。两份不同二进制的证书签名规则一致已验证，未来真实更新后仍应核实GUI权限。Apple Development用于本机开发，不代表应用已公证或可免提示公开分发；此仓库发布源码，未发布证书或私钥。
