# 响课 · 开发文档

面向要改代码的人。**使用说明见 [README.md](README.md)**。

## 当前进度

| 能力 | 状态 |
|---|---|
| 读写系统闹钟（私有 API 路线） | ✅ 已验证可行 |
| 模块化 App 骨架 | ✅ 已完成 |
| 载入示例课表 + 一键应用 | ✅ 已完成 |
| 课表编辑界面（增 / 删 / 改 / 提前量） | ✅ 已完成 |
| 课表持久化（重启不丢） | ✅ 已完成 |
| 远程 JSON 导入（URL） | ✅ 已完成 |
| 快捷指令唤起（URL Scheme） | ✅ 已完成（仅解锁时可用） |
| 应用名 / 图标 | ✅ 已完成 |
| 锁屏探针 | ✅ 已完成（实测：数据保护不是障碍） |
| 快捷指令开关闹钟（锁屏可用） | 🔬 手工搭建，待实测 |
| 生成快捷指令文件直接导入 | ⛔ 不可能（需 Apple 签名，见下） |
| 后台自动刷新（BGTaskScheduler） | ⚠️ 实测不可靠（三天未唤醒） |
| App Intent 动作（锁屏 + 时间精确） | ⛔ 受阻，见下 |
| 更优雅的重载方式（替代 SIGKILL） | ⬜ 待做 |

## 模块结构

低耦合设计，各模块只负责一件事，改一处不会牵连别处。

| 文件 | 职责 |
|---|---|
| `CALPrivateAPI.h` | 私有 API 与路径常量集中声明 |
| `CALTimetable.h/.m` | 课表模型 + 持久化（含存储目录探测） |
| `CALAlarmStore.h/.m` | 系统闹钟读写引擎（不关心课表） |
| `CALDaemonReloader.h/.m` | 让 mobiletimerd 重新加载数据（换方案只改这里） |
| `CALScheduleEngine.h/.m` | 纯计算：课表 → 目标时间（无副作用） |
| `CALApplier.h/.m` | 协调层，唯一知道完整流程的模块 |
| `CALHomeViewController.h/.m` | 主界面：状态 + 应用 / 编辑 / 导入 / 清理 / 设置 |
| `CALTimetableViewController.h/.m` | 课表编辑：分段控件切换「每周课表」/「自定义课表」 |
| `CALCourseEditorViewController.h/.m` | 单节课编辑表单（只收集输入并回调） |
| `CALSettingsViewController.h/.m` | 设置：提前提醒 / 载入示例课表 / 存储自检 / 重载诊断 / 锁屏探针 |
| `CALImportViewController.h/.m` | 导入课表：URL 下载 / 从「文件」选本地 JSON |
| `CALProbe.h/.m` | 锁屏探针：判断是否锁屏 + 探测系统文件可访问性 |
| `CALPaddedLabel.h/.m` | 带内边距的 UILabel（通用小组件） |
| `main.m` | 入口与装配（导航栈 + URL Scheme + 后台刷新） |
| `Resources/AppIcon*.png` | App 图标（8 个尺寸，构建时拷进 .app） |
| `Experimental/` | 不参与编译的实验性代码（见「App Intent 方案」） |
| `tools/gen_alarms.py` | 生成快捷指令用的「日期 → 闹钟时间」对照表 |

## 锁屏自动运行：为什么绕这么大一圈

目标：**每天自动设好次日闹钟，且手机锁屏时也能生效。** 三条路逐一试过：

| 路线 | 结果 |
|---|---|
| 快捷指令「打开 URL」→ `xiangke://apply` | ❌ 锁屏时必定失败（iOS 禁止锁屏下打开 App / URL） |
| 后台刷新 `BGTaskScheduler` | ⚠️ 由系统择机。**实测三天一次都没被唤醒** |
| App Intent（动作直接进快捷指令） | ⛔ 元数据生不出来，见下节 |

于是换成**绕开「打开 App」**的思路：

**关键事实**：快捷指令的「开关闹钟」动作**不需要打开 App**，所以锁屏时也能执行。

**关键数据**：课表里最早课有 6 种时间（08:20 / 10:15 / 10:30 / 14:00 / 15:55 / 18:30）。
顺带验证过：**不存在单双周规律**（周一的三种时间在单双周里都出现），
所以「按星期设重复闹钟」这条路走不通 —— 必须逐日判定。

**用户口径**：**只给上午的课设闹钟**，即只保留最早两种（08:20 / 10:15），
10:30 及以后开始的课不设闹钟。

**于是把问题拆成两半：**

```
准备（一次）：时钟里预置 2 个闹钟（07:50 / 09:45）
每天（自动）：快捷指令查表 → 打开该用的那个、关掉另一个
```

对照表由 `tools/gen_alarms.py --max-start 10:15` 生成 ——
`--max-start` 就是「只给不晚于该时间开始的课设闹钟」，去掉即恢复全时段。

「查表」用的表由 `tools/gen_alarms.py` 生成，发布在 Gist
（`alarms.json`，格式 `{"2026-10-16":"13:30", ...}`，空串表示当天无课）。
快捷指令「获取 URL 内容」在锁屏下也能跑，所以整条链路不碰 App。

> 之所以要预先算好而不是让快捷指令自己算：快捷指令里没有「取列表最小值」这种
> 运算，用「重复 + 比较」能做但搭起来又长又容易错。预先算好只需一次字典查找。

### 锁屏探针实测结论（2026-10-15）

用户提供三天记录：

- 闹钟数据文件 `com.apple.mobiletimerd.plist` 的保护等级是 **`NSFileProtectionNone`**
  —— **数据保护不是障碍**，锁屏下应该也能读写。
- 记录里**没有任何一条「后台刷新」** —— 后台刷新确实没被唤醒过。
- 「URL 唤起」的记录全部是 `isProtectedDataAvailable = YES`（即解锁状态）——
  锁屏那次根本没被拉起，与「锁屏禁止打开 URL」完全吻合。

### 快捷指令：格式能生成，但导入不了

> **结论先行：这条路走不通，用户只能手工搭。** 生成器保留下来是作为
> **动作连线方式的参考**（UUID / 变量引用 / 条件分组怎么写），
> 以及将来若有 Mac + iCloud，跑一句 `shortcuts sign` 就能产出可导入版本。

`tools/make_shortcut.py` 能产出 `.shortcut` 文件（未签名 XML plist，14 个动作，
对应用户「只留上午两个闹钟」的口径）。格式参考公开逆向资料：
`WFWorkflowActions` 数组，每个动作是 `WFWorkflowActionIdentifier` + `WFWorkflowActionParameters`；
动作间用 `WFTextTokenAttachment`（带 `OutputUUID`）引用输出；
条件分支用 `WFControlFlowMode`（0=如果 / 1=否则 / 2=结束）+ `GroupingIdentifier` 配对。

**动作标识符**（关键，写错了动作就丢）。
中文名那一列是**快捷指令里实际显示的名字** —— 用户反馈「从输入获取字典」搜不到，
原因是 **Apple 的中文用的是「词典」不是「字典」**：

| 中文名 | 标识符 |
|---|---|
| 获取 URL 内容 | `is.workflow.actions.downloadurl` |
| 从输入获取词典 | `is.workflow.actions.detect.dictionary` |
| 日期 | `is.workflow.actions.date` |
| 调整日期 | `is.workflow.actions.adjustdate` |
| 格式化日期 | `is.workflow.actions.format.date` |
| 获取词典值 | `is.workflow.actions.getvalueforkey` |
| 如果 | `is.workflow.actions.conditional` |
| **开关闹钟** | `is.workflow.actions.alarm.toggle`（参数 `WFAlarm` + `WFEnabled`） |

> 「开关闹钟」这个名字已由公开教程交叉验证（iOS 节假日闹钟自动化就是这么叫的）。

查动作定义最快的方式：`gh api repos/pfgithub/scpl/contents/docs/actions/<动作名>.md`
（里面有每个动作的 `source json`，直接给出 `Key` 与参数类型）。

**三道坎，最后一道过不去：**

1. **闹钟选择器（`WFAlarm`）填不了** —— 它存的是设备上那个闹钟的引用，与设备绑定。
   不过这条本身不致命：导入后逐个点开手动选即可。
2. **必须由 Apple 服务器签名才能导入。** `shortcuts sign --mode anyone` 是 macOS
   自带命令，但**要求登录 iCloud**。CI 日志原话：
   `Error: In order to do this, you must be signed into iCloud.`
3. **离线签名也不行。** `0xilis/shortcut-sign` 能签，但 `-k` 需要 **Apple ID 的
   ECDSA-P256 私钥**、`-a` 需要 auth data，二者都要用 `appleid-key-dumper`
   从**越狱设备**里导出。本项目只有 TrollStore，不是越狱，拿不到。

**实测确认**：用户点导入后，快捷指令 App 提示「格式不正确」—— 就是签名这一关。

**现状**：`.shortcut` 产物已从仓库移除（生成物，已加 .gitignore）。
`index.html`（GitHub Pages，`https://yhgeo.github.io/ios-class-alarm/`）
从「导入页」改成了**手机上照着做的图文搭建指南** —— 改成只留 2 个闹钟后，
手工搭建只剩 9 个动作块 / 11 步操作，可接受。

> ⚠️ 若将来重新启用签名流程：`.gitattributes` 里要有 `*.shortcut -text`。
> 签名是对文件内容算的哈希，换行符转换会让签名失效。

## 工作原理

```
课表 → 算次日第一节课时间 → 写 com.apple.mobiletimerd.plist → 重启 mobiletimerd → 系统生效
```

闹钟标题统一加前缀 `课表|`，因此清理时**只删自己创建的**，不会误伤手动设的闹钟。

## 数据存在哪

课表存在磁盘上，重启 App 不会丢。因为本 App 带 `no-sandbox` entitlement，
`NSDocumentDirectory` 在无沙箱进程里指向 `/var/mobile/Documents`（**不保证可写**），
所以存储目录是**运行时探测**出来的：

1. 已经存在 `class-alarm-timetable.json` 的目录优先（避免换路径后读不到旧数据）
2. 否则按候选顺序挑第一个**真正可写**的（写探针文件 + 读回校验，不只看文件是否存在）
   - `NSDocumentDirectory`
   - `/var/mobile/Library/Preferences`（闹钟 plist 就落在这里，实测可写）
   - `/var/mobile/Documents`
   - 临时目录（兜底，重启会丢）

主页「存储自检」按钮会显示：当前目录、是否可写、文件大小、上次保存结果。
保存失败会直接弹窗报原因，不会静默。

## 构建

本机是 Windows，没有 Xcode，编译走 GitHub Actions 的 macOS runner。
直接用 clang 编译再手工组装 `.app`，不依赖 xcodegen / xcodebuild：

```
SOURCES=$(find Sources -name '*.m')
xcrun --sdk iphoneos clang -arch arm64 -isysroot $SDK \
    -miphoneos-version-min=16.0 -fobjc-arc -ISources \
    -framework UIKit -framework Foundation -framework CoreGraphics \
    -framework UniformTypeIdentifiers -framework Security \
    -o XiangKe.app/XiangKe $SOURCES

cp Sources/Info.plist XiangKe.app/Info.plist
cp Resources/AppIcon*.png XiangKe.app/
ldid -Sentitlements.plist XiangKe.app/XiangKe
zip -r XiangKe.ipa Payload
```

## App Intent 锁屏方案（已搁置）

**目标**：让动作直接出现在「快捷指令」里，从而在**锁屏**下也能定时执行。
`xiangke://apply` 走的是「打开 URL」，而 iOS 锁屏时禁止打开 App / URL —— 这是系统硬限制。

**结论**：代码层面可行（`openAppWhenRun = false` 时系统在后台拉起进程执行、不进入前台），
但**元数据生不出来**，动作不会出现在快捷指令里。代码保留在
`Experimental/XiangKeIntent.swift`，逻辑完整、无需改动。

### 卡在哪

App Intent 动作要被快捷指令发现，App 包内必须有
`Metadata.appintents/extract.actionsdata`，由 Xcode 的 `appintentsmetadataprocessor`
生成。该处理器需要**编译器产出的常量值 sidecar**（`.swiftconstvalues`），否则报错：

```
No swift const values found. If SWIFT_ENABLE_EMIT_CONST_VALUES = NO,
AppIntents metadata cannot be extracted.
```

而这个 sidecar 在纯命令行构建下生不出来：

1. 触发发射的是**驱动层**开关 `-emit-const-values`。它**不是**前端 flag，
   所以 `swift-frontend -help` 里根本看不到它（只看得到 `-emit-const-values-path`）——
   一开始就找错了方向。驱动收到 `-emit-const-values` 后会自己往前端补
   `-emit-const-values-path`（`swiftc -###` 已证实）。
2. 加上 `-emit-const-values` 后，**swiftc 直接 `Segmentation fault: 11`**。
3. 去掉 `-parse-as-library` 就不崩，但 swiftc 会把**单个源文件当成主文件**，
   于是生成 `_main`，与 ObjC 的 `main` 冲突（`duplicate symbol '_main'`）。
   所以 `-parse-as-library` 不能去。

试过且无效的写法：`-Xfrontend -emit-const-values-path`（参数能过、前端也确实收到，
但什么都不写）、加 `-emit-module`、直接调 `swift-frontend -primary-file`、`-output-file-map`。

另外两个容易踩的坑（都已在 CI 里踩过）：

- 处理器在「什么都没提取到」时**退出码仍是 0**，成功判据只能是「输出目录是否真的出现」。
- `echo "✓ 成功（$label）"` 这种写法在 `set -u` 下会报 `label: unbound variable` ——
  bash 在某些 locale 下把全角括号当成了标识符的一部分。变量后紧跟非 ASCII 字符时
  必须写 `${label}`。

### 若将来重启

让 Xcode 自己跑这套步骤，再取产物：用 `xcodegen`（brew 可装）生成一个最小
`.xcodeproj`（一个 app target，只含这个 Swift 文件，module name 与主工程一致），
`xcodebuild` 出包后把 `Metadata.appintents/` 拷进手工打包的 bundle。

### 替代方案（当前采用）

`BGTaskScheduler` 后台刷新。它同样在锁屏下执行，只是**时刻由系统决定、不精确**。
设置「次日闹钟」只要当天跑过一次就够了，所以实际够用。

| 方式 | 锁屏可用 | 时间精度 |
|---|---|---|
| 快捷指令 `xiangke://apply` | ❌ | 精确 |
| 后台刷新 | ✅ | 系统择机，不精确 |

### 还没回答的问题

**锁屏时能否读写 `/var/mobile/Library/Preferences/com.apple.mobiletimerd.plist`？**
系统偏好文件受数据保护（Data Protection）限制，锁屏时可能直接读写失败 ——
若答案为否，那上面两种「锁屏可用」的方案都只是能跑起来、干不成活。

`CALProbe` 就是为这个问题准备的：**设置 → 锁屏探针**。
「跑一次探针」拿基准记录，「查看记录」看历次结果；后台刷新与 URL 唤起各会留一条。
看 `isProtectedDataAvailable` 与 plist 的可读性即可判断。

## 踩坑记录

这些是实测踩过的，记下来免得重复：

**编译 / 链接**
- **xcodegen 生成的工程是 Xcode 16 格式**（objectVersion 77），runner 上的 Xcode 15.4 读不了 → 改用 clang 直接编译
- **`CGRectGetMaxY` 这类 CG 函数是 extern 符号**（`CGRectMake` 是 `static inline`，不需要链接），
  手写 clang 命令行必须显式加 `-framework CoreGraphics`，否则链接期报 `Undefined symbols: _CGRectGetMaxY`
- **`errno` 是宏**（展开为 `(*__error())`），直接当 `appendFormat:` 的可变参数会报 `expected ']'`，必须先存进 int 变量
- **block 内修改外层局部变量必须加 `__block`**

**私有 API / 权限**
- **`SecTaskRef` / `SecTaskCreateFromSelf`** 是私有 API，公开头文件未导出，需手动 `typedef` + `extern`
- **`xpc_connection_create_mach_service`** 在 iOS 公开头文件里标记为 unavailable，须用 `dlsym` 取函数指针
- **系统闹钟 XPC 服务名是 `com.apple.MobileTimer.alarmserver`**，不是 `mobiletimerd`
- **改了 plist 后 mobiletimerd 不会自动重读**，必须重启它（用 SIGKILL，避免它退出时把内存状态写回覆盖数据）

**文件系统**
- **`no-sandbox` 下 `NSHomeDirectory()` 返回 `/var/mobile`**，不是 App 沙箱，别用它拼数据路径
- **`no-sandbox` 下 `NSDocumentDirectory` 指向 `/var/mobile/Documents`，不保证可写**；
  写文件后一定要**回读校验**，`writeToFile:` 返回 YES 也不代表真的落盘了

**剪贴板（iOS 16）**
- iOS 16 起，**程序化读取 `UIPasteboard` 会弹权限框**；用户一旦拒绝，之后**静默返回空**，
  且不再提示 —— 表现为「剪贴板是空的」，很容易误判成剪贴板真的没内容
- **但在 TrollStore 环境下这条路整体走不通**（实测 `hasStrings` 为真、取值恒为空）：
  - 直接读 `UIPasteboard.string` → 空值
  - `UIPasteControl`（配好 `pasteConfiguration` 后按钮可点、回调正常触发）→
    内部 `loadObjectOfClass:` 报 `Cannot load representation of type public.utf8-plain-text`
  - `loadDataRepresentationForTypeIdentifier:` 直接取原始 data → 同样拿不到
  - 佐证：TrollStore 上的剪贴板同步项目 `daxia25881/Clip-` 也必须依赖 **CopyLog**
    把剪贴板落成文件才能读到
- **结论：不要依赖剪贴板**。要么让用户长按输入框手动粘贴，要么改用文件导入
- `UIPasteControl` 若要用，**target 的 `pasteConfiguration` 必须非 nil**，
  否则控件一直置灰、点击无反应

**文件选择器（UIDocumentPickerViewController）**
- **`asCopy:YES` 在 `no-sandbox` 下会让选择器里文件全部不可选** ——
  它需要系统把文件拷进 App 容器，而本 App 没有常规容器路径。
  改用 `asCopy:NO`（就地打开），读取时配 `startAccessingSecurityScopedResource`
- **类型限制不要写太窄**：只写 `UTTypeJSON` 时，系统未识别成 `public.json` 的文件
  （如从聊天软件存下来的）会灰显、点不动。放宽到 `UTTypeData` 更稳

**UI**
- **iOS App 图标不能带 alpha 通道**，否则整张图渲染成黑块。源图若是透明底，必须先合成到实色背景再转 RGB
- **图形不要顶到图标边缘**：内容占画布约 74%（四周各留 13%）视觉最稳
- **UILabel 没有内边距**，文字会贴着圆角边缘，需要自己重写 `drawTextInRect:`
- **编辑页不要用固定 `y` 起排**，包进导航栏后顶部会被遮 —— 用 `safeAreaInsets`

**工具链**
- 本仓库的 ObjC 静态检查脚本有个顺序坑：**必须先删字符串再删注释**，
  否则 `@"https://..."` 里的 `//` 会被当注释吃掉，导致括号计数误报
