# Touchbar Tool

轻量 Swift/AppKit 菜单栏工具，在指定应用处于前台时显示自定义 Touch Bar 按钮，离开时收起。当前版本 0.2.0 针对 ChatGPT.app（bundle ID `com.openai.codex`）提供五个按钮：

| 顺序 | 按钮 | 默认粘贴文本 |
|---|---|---|
| 1 | 继续 | 继续 |
| 2 | 查问题 | 检查当前问题，说明原因和建议的最小改动。 |
| 3 | 中日翻译 | 请将下面内容做中日互译，表达自然、简短： |
| 4 | DONE | DONE |
| 5 | 合并 | 合并 |

所有按钮只粘贴文字，**不按回车、不发送消息、不执行 Git 合并**。目标判断以应用 bundle ID 为单位，不能识别应用内部的 Codex 模式。菜单栏 `CTB` 提供禁用和退出。没有登录自动启动、后台服务或网络请求。

## 构建与运行

需要带 Touch Bar 的 Mac、Apple Command Line Tools（Swift/Clang）以及 macOS GUI 会话。无第三方构建依赖或付费软件。

```sh
git clone https://github.com/frandlee/touchbar-tool.git
cd touchbar-tool
./scripts/build.sh
./scripts/test.sh
codesign --verify --strict build/TouchbarTool.app
open build/TouchbarTool.app
```

构建输出 `build/TouchbarTool.app`，使用本地 ad-hoc 签名。没有开发者证书或公证发行包。一次只运行一个实例，更新前先从 CTB 菜单退出旧实例。

## 配置

`config.example.json` 是通用模板，默认 `pasteAuthorized=false`。首次构建自动复制为本地 `config.json`，并将其复制到 App 同级的 `build/config.json`；两个本地配置均不提交。

编辑 `config.json` 后，可直接复制到 `build/config.json` 并重启 App，无需重新编译。配置在启动时读取。直接运行可执行文件时，可用环境变量 `CODEX_TOUCHBAR_CONFIG` 指定配置路径。

- `schemaVersion` 必须为 `2`。
- `targetBundleIdentifier` 默认 `com.openai.codex`。其他应用适配尚未验证。
- 五按钮的 ID、标签和顺序固定为示例中的值；各项 `text` 可编辑。
- 文本最多 2000 字符，不允许空白、控制字符或换行（含 Unicode 行/段分隔符）。
- 缺失、重复或未知按钮，错误顺序、字段类型、schema 或损坏 JSON 均拒绝启动。
- 了解并批准 App 的辅助功能访问用途后，才将本地 `pasteAuthorized` 改为 `true`；同时需要系统授权。配置开关本身不会授予权限。

## 权限与安全行为

App 需要 Accessibility/辅助功能授权，用于在按钮点击时检查已聚焦输入框的类型，并向同一前台进程发送 ⌘V。macOS 27 将该设置页命名为 **Device Control and Data Access**；见 [权限名称说明](https://support.symless.com/hc/en-us/articles/35743428145169-Troubleshooting-the-macOS-Device-Control-and-Data-Access-or-Accessibility-permission)。系统身份验证应由使用者本人完成。

程序不主动弹权限申请、不录屏、不监听键盘、不使用 Apple Events 自动化，也不改变系统安全设置。缺少 AX 或事件发送许可时不会粘贴。不要为了兼容性额外授予权限或放宽系统安全限制。

粘贴前检查目标前台 bundle ID、焦点 TextField/TextArea 类型并拒绝 SecureTextField；不读取输入内容。发送前再次检查前台 PID，有 0.6 秒防重复触发。仅生成 ⌘V 的按下/抬起事件。Clipboard 原内容会被配置文本覆盖，程序不读取、保存或恢复原剪贴板。

焦点的瞬间变化、目标应用自定义处理 ⌘V 的行为以及未暴露标准辅助功能类型的输入框无法完全保证。辅助功能权限本身具有广泛能力，应只对信任的构建授予。

本地 ad-hoc 重签可能使旧系统授权失配，即使设置开关仍开启。只刷新本 App 的同一 Accessibility 授权并重启以核实实际状态，不重置其他应用权限。

内部 bundle ID `local.codex-touchbar.prototype`、可执行文件名 `CodexTouchBar` 及 Touch Bar 项标识为兼容既有原型而保留；产品名称为 Touchbar Tool。

## 私有 API 与兼容性

公共 [NSTouchBar](https://developer.apple.com/documentation/appkit/nstouchbar) 仅服务本应用。跨应用展示依赖私有 class methods：

- `presentSystemModalTouchBar:systemTrayItemIdentifier:`
- `dismissSystemModalTouchBar:`

旧 FunctionBar 名称作为后备。调用前核对方法存在性、参数数量、对象类型和 void 返回值，并保护 Objective-C 异常；缺失、不匹配或抛异常时退出。不能防止所有底层崩溃。接口返回 void，调用成功不等于硬件实际显示。

使用保留 Control Strip 的两参数展示路径，不调用隐藏 Control Strip 的接口，不加入系统托盘项或修改系统 Touch Bar 偏好。参考 [MTMR 调用方式](https://github.com/Toxblh/MTMR/blob/master/MTMR/TouchBarController.swift) 和 [EnergyBar API 声明](https://github.com/billziss-gh/EnergyBar/blob/master/src/System/NSTouchBar%2BSystemModal.m)；桥接与权限控制独立实现，没有引入这些项目的实现文件或依赖。

曾在 Apple Silicon Touch Bar Mac、macOS 27.0.1 验证五按钮文字、无自动发送、Control Strip 保留及切换应用自动收起。其他系统版本、硬件和目标应用尚未覆盖；私有 API 没有兼容承诺。

## 诊断与测试

```sh
build/TouchbarTool.app/Contents/MacOS/CodexTouchBar --probe
build/TouchbarTool.app/Contents/MacOS/CodexTouchBar --permissions
open build/TouchbarTool.app --args --diagnostics
```

`--probe` 和 `--permissions` 在创建 NSApplication 前退出，不展示 Touch Bar、不读取目标 UI、不请求权限。命令行进程的 TCC 身份可能与 GUI 不同，以 GUI 实例实际状态为准。

可选诊断窗口显示本 App 的权限、配置、前台 bundle ID 和启用状态。其测试粘贴按钮仅在目标配置是原型自身时有效，不会对外部应用触发；关闭窗口不会退出菜单栏程序。无窗口菜单栏 App 的自动化界面读取可能超时，诊断窗口可帮助观察。

30 项配置测试覆盖固定顺序和默认文字、可编辑文本、长度边界、换行/控制字符、缺失/重复按钮、错误类型及损坏 JSON；测试不对其他应用发送事件。

手动验收：在目标空输入框逐个点击并核对文字和无自动发送；确认 Control Strip 保留；切到 Finder 确认收起；从 CTB 禁用或退出确认恢复。出现问题先禁用/退出并报告系统版本及失败步骤，不提供输入内容或个人数据。

## 发布范围

仓库只包含源代码、脚本、测试和通用配置示例，不含本地构建、个人配置或调试日志。许可证尚未选择。
