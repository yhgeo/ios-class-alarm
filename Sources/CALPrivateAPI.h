//
//  CALPrivateAPI.h
//  本项目用到的私有 API 统一声明处。
//  所有 extern 声明集中在此，避免散落各文件导致重复定义或符号冲突。
//

#ifndef CALPrivateAPI_h
#define CALPrivateAPI_h

#import <Foundation/Foundation.h>

#pragma mark - SecTask（读取本进程 entitlements）

typedef struct CF_BRIDGED_TYPE(id) __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task,
                                                CFStringRef entitlement,
                                                CFErrorRef *error);

#pragma mark - libproc（枚举进程）

extern int proc_listallpids(void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);

#pragma mark - notify（Darwin 通知）

extern uint32_t notify_post(const char *name);

#pragma mark - 系统闹钟数据文件（mobiletimerd 的 preferences）

#define CAL_ALARM_PLIST_PATH @"/var/mobile/Library/Preferences/com.apple.mobiletimerd.plist"
#define CAL_ALARM_BACKUP_PATH @"/var/mobile/Library/Preferences/com.apple.mobiletimerd.plist.calbak"

#pragma mark - 私有框架

#define CAL_MOBILE_TIMER_FRAMEWORK \
    @"/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer"

/// 系统闹钟 XPC 服务名（MTAlarmManager 内部连接的目标）
#define CAL_ALARM_XPC_SERVICE "com.apple.MobileTimer.alarmserver"

/// 本 App 创建的闹钟统一使用该标题前缀，便于识别与清理
#define CAL_ALARM_TITLE_PREFIX @"课表|"

#endif /* CALPrivateAPI_h */
