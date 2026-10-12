# 课表闹钟（ClassAlarm）

用课表自动设置次日早晨的闹钟。目标设备：iPhone 13 / iOS 16.6.1 / TrollStore。

## 它解决什么问题

iOS 16 的快捷指令有「添加闹钟」但没有「删除闹钟」，纯快捷指令方案会让闹钟无限累积。
本项目通过 TrollStore 的权限优势，**直接读写系统「时钟」App 的闹钟**，从而能增、能删、能改。

## 当前进度

| 能力 | 状态 |
|---|---|
| 读写系统闹钟（私有 API 路线） | ✅ 已验证可行 |
| 模块化 App 骨架 | ✅ 已完成 |
| 载入示例课表 + 一键应用 | ✅ 已完成 |
| 课表编辑界面（增 / 删 / 改 / 提前量） | ✅ 已完成 |
| 远程 JSON 导入（GitHub Gist） | ⬜ 待做 |
| 快捷指令动作（App Intent） | ⬜ 待做 |

## 模块结构

低耦合设计，各模块只负责一件事，改一处不会牵连别处。

| 文件 | 职责 |
|---|---|
| `CALPrivateAPI.h` | 私有 API 与路径常量集中声明 |
| `CALTimetable.h/.m` | 课表模型 + 持久化 |
| `CALAlarmStore.h/.m` | 系统闹钟读写引擎（不关心课表） |
| `CALDaemonReloader.h/.m` | 让 mobiletimerd 重新加载数据（换方案只改这里） |
| `CALScheduleEngine.h/.m` | 纯计算：课表 → 目标时间（无副作用） |
| `CALApplier.h/.m` | 协调层，唯一知道完整流程的模块 |
| `CALHomeViewController.h/.m` | 主界面：状态 + 应用 / 编辑 / 示例 / 清理 |
| `CALTimetableViewController.h/.m` | 课表列表：按星期分组，增删改 + 提前量 |
| `CALCourseEditorViewController.h/.m` | 单节课编辑表单（只收集输入并回调） |
| `main.m` | 入口与装配（导航栈） |

## 课表数据格式

存于 App 沙箱的 `class-alarm-timetable.json`：

```json
{
  "version": 1,
  "advanceMinutes": 30,
  "courses": [
    { "weekday": 1, "start": "08:00", "end": "09:40", "name": "高等数学" },
    { "weekday": 2, "start": "09:00", "end": "10:40", "name": "线性代数" }
  ],
  "overrides": {
    "2026-10-13": [ { "start": "14:00", "end": "15:40", "name": "临时补课" } ],
    "2026-10-14": []
  }
}
```

- `weekday`：1=周一 … 7=周日
- `advanceMinutes`：闹钟 = 第一节课开始时间 − 该值
- `overrides`：指定日期覆盖常规课表；**空数组表示当天无课**（优先级最高，用于临时调课/放假）

## 工作原理

```
课表 → 算次日第一节课时间 → 写 com.apple.mobiletimerd.plist → 重启 mobiletimerd → 系统生效
```

闹钟标题统一加前缀 `课表|`，因此清理时**只删自己创建的**，不会误伤你手动设的闹钟。

## 构建

本机是 Windows，没有 Xcode，编译走 GitHub Actions 的 macOS runner。
直接用 clang 编译再手工组装 `.app`，不依赖 xcodegen / xcodebuild：

```
SOURCES=$(find Sources -name '*.m')
xcrun --sdk iphoneos clang -arch arm64 -isysroot $SDK \
    -miphoneos-version-min=16.0 -fobjc-arc -ISources \
    -framework UIKit -framework Foundation -framework Security \
    -o AlarmPoC.app/AlarmPoC $SOURCES

ldid -Sentitlements.plist AlarmPoC.app/AlarmPoC
zip -r AlarmPoC.ipa Payload
```

## 踩坑记录

这些是实测踩过的，记下来免得重复：

- **xcodegen 生成的工程是 Xcode 16 格式**（objectVersion 77），runner 上的 Xcode 15.4 读不了 → 改用 clang 直接编译
- **`SecTaskRef` / `SecTaskCreateFromSelf`** 是私有 API，公开头文件未导出，需手动 `typedef` + `extern`
- **`xpc_connection_create_mach_service`** 在 iOS 公开头文件里标记为 unavailable，须用 `dlsym` 取函数指针
- **`errno` 是宏**（展开为 `(*__error())`），直接当 `appendFormat:` 的可变参数会报 `expected ']'`，必须先存进 int 变量
- **`no-sandbox` 下 `NSHomeDirectory()` 返回 `/var/mobile`**，不是 App 沙箱，别用它拼数据路径
- **系统闹钟 XPC 服务名是 `com.apple.MobileTimer.alarmserver`**，不是 `mobiletimerd`
- **改了 plist 后 mobiletimerd 不会自动重读**，必须重启它（用 SIGKILL，避免它退出时把内存状态写回覆盖数据）

## 使用

1. 打开 Actions 页面，等 `Build PoC IPA` 跑完，下载产物 `AlarmPoC-ipa`
2. 用 TrollStore 安装
3. 打开 App → 点「编辑课表」录入课程（右上角 `+` 新增，左滑删除，点行编辑；
   顶部「提前提醒」可改提前量），也可先点「载入示例课表」体验
4. 回主页点「立即应用（设置次日闹钟）」
5. 打开系统「时钟」App 核对
