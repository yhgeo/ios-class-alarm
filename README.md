# iOS 课表闹钟自动化

用课表自动设置次日早晨的闹钟。目标设备：iPhone 13 / iOS 16.6.1 / TrollStore。

## 当前阶段：可行性验证（PoC）

本仓库当前只做一件事：**验证能否通过私有框架 MobileTimer 读写系统「时钟」App 的闹钟**。

这一步是整个方案的前提。iOS 16 的快捷指令没有「删除闹钟」动作，只能不断新增，
闹钟会无限累积。如果能直接调用 MobileTimer，就能绕开这个限制，做出真正干净的方案。

## 为什么要验证

| 项目 | 状态 |
|---|---|
| MobileTimer 私有框架是否存在 | ✅ 已确认，iOS 16 头文件已核对 |
| `MTAlarmManager` / `MTAlarm` 类可用 | ✅ 已确认签名 |
| TrollStore 环境下 XPC 通道是否放行 | ⚠️ **未验证，本 PoC 的目的** |

已核对的 iOS 16 关键签名：

```objc
@interface MTAlarmManager : NSObject
- (id)init;                    // iOS 16 没有 +alarmManager 单例
- (id)addAlarm:(id)alarm;
- (id)removeAlarm:(id)alarm;
- (id)updateAlarm:(id)alarm;
- (id)alarmsSync;
@end

@interface MTAlarm : NSObject
+ (id)alarmWithHour:(unsigned long long)hour minute:(unsigned long long)minute;
@property unsigned long long hour;
@property unsigned long long minute;
@property (copy) NSString *title;   // 注意：不是 label
@property (getter=isEnabled) bool enabled;
@end
```

## 怎么用

1. 打开本仓库的 **Actions** 页面，等 `Build PoC IPA` 跑完（约 3–5 分钟）。
2. 在该次运行底部下载产物 **AlarmPoC-ipa**，解压得到 `AlarmPoC.ipa`。
3. 用 TrollStore 打开并安装 `AlarmPoC.ipa`。
4. 打开 App，点「创建闹钟（+5 分钟）」。
5. 看 App 内的诊断输出，同时打开系统**「时钟」App** 核对。

## 结果怎么读

- **成功**：App 里 `[9] 复读验证` 能看到 `课表PoC` 这个闹钟，系统时钟 App 里也出现。
  → 方案成立，继续开发完整 App。
- **失败**：重点看 `[1]`、`[5]`、`[8]` 三步的报错。
  → 需要调整 entitlements 重试；若始终不通，则切换到「本地通知 + 关键警报」兜底方案。

## 构建方式

本机是 Windows，没有 Xcode，所以编译走 GitHub Actions 的 macOS runner：

```
xcodegen generate      # 由 project.yml 生成 Xcode 工程
xcodebuild -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO
ldid -Sentitlements.plist AlarmPoC.app/AlarmPoC   # 注入私有权限
zip → AlarmPoC.ipa
```

`entitlements.plist` 中注入了 `platform-application`、`com.apple.private.security.no-sandbox`
等权限，让沙箱内的 App 能访问系统级服务。
