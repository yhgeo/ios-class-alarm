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
| 快捷指令唤起（URL Scheme） | ✅ 已完成 |
| 应用名 / 图标 | ✅ 已完成 |
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
| `CALHomeViewController.h/.m` | 主界面：状态 + 应用 / 编辑 / 导入 / 示例 / 自检 / 清理 |
| `CALTimetableViewController.h/.m` | 课表列表：按星期分组，增删改 + 提前量 |
| `CALCourseEditorViewController.h/.m` | 单节课编辑表单（只收集输入并回调） |
| `CALPaddedLabel.h/.m` | 带内边距的 UILabel（通用小组件） |
| `main.m` | 入口与装配（导航栈 + URL Scheme 处理） |
| `Resources/AppIcon*.png` | App 图标（8 个尺寸，构建时拷进 .app） |

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
    -framework UIKit -framework Foundation -framework CoreGraphics -framework Security \
    -o XiangKe.app/XiangKe $SOURCES

cp Sources/Info.plist XiangKe.app/Info.plist
cp Resources/AppIcon*.png XiangKe.app/
ldid -Sentitlements.plist XiangKe.app/XiangKe
zip -r XiangKe.ipa Payload
```

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

**UI**
- **iOS App 图标不能带 alpha 通道**，否则整张图渲染成黑块。源图若是透明底，必须先合成到实色背景再转 RGB
- **图形不要顶到图标边缘**：内容占画布约 74%（四周各留 13%）视觉最稳
- **UILabel 没有内边距**，文字会贴着圆角边缘，需要自己重写 `drawTextInRect:`
- **编辑页不要用固定 `y` 起排**，包进导航栏后顶部会被遮 —— 用 `safeAreaInsets`

**工具链**
- 本仓库的 ObjC 静态检查脚本有个顺序坑：**必须先删字符串再删注释**，
  否则 `@"https://..."` 里的 `//` 会被当注释吃掉，导致括号计数误报
