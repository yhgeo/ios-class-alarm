//
//  CALSettingsViewController.m
//

#import "CALSettingsViewController.h"
#import "CALTimetable.h"
#import "CALDaemonReloader.h"
#import "CALProbe.h"

static NSString * const kCellID = @"CALSettingCell";

typedef NS_ENUM(NSInteger, CALSettingSection) {
    CALSettingSectionAlarm = 0,     // 提前提醒
    CALSettingSectionTimetable,     // 载入示例课表
    CALSettingSectionIntentProbe,   // 锁屏探针
    CALSettingSectionDiagnostics,   // 存储自检
    CALSettingSectionReload,        // 重载诊断
    CALSettingSectionCount,
};

@interface CALSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation CALSettingsViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds
                                                  style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kCellID];
    [self.view addSubview:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

#pragma mark - 数据

- (CALTimetable *)timetable {
    return [CALTimetableStore shared].timetable;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return CALSettingSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // 「锁屏探针」下有两行：跑一次 / 查看记录
    if (section == CALSettingSectionIntentProbe) return 2;
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellID
                                                            forIndexPath:indexPath];

    switch (indexPath.section) {
        case CALSettingSectionAlarm:
            cell.textLabel.text = @"提前提醒";
            cell.detailTextLabel.text =
                [NSString stringWithFormat:@"%ld 分钟", (long)self.timetable.advanceMinutes];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;

        case CALSettingSectionTimetable:
            cell.textLabel.text = @"载入示例课表";
            cell.detailTextLabel.text = @"会覆盖当前课表";
            cell.accessoryType = UITableViewCellAccessoryNone;
            break;

        case CALSettingSectionIntentProbe:
            if (indexPath.row == 0) {
                cell.textLabel.text = @"跑一次探针";
                cell.detailTextLabel.text = @"记录此刻是否锁屏、能否访问系统文件";
                cell.accessoryType = UITableViewCellAccessoryNone;
            } else {
                cell.textLabel.text = @"查看记录";
                cell.detailTextLabel.text = @"历次执行留下的记录";
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            break;

        case CALSettingSectionDiagnostics:
            cell.textLabel.text = @"存储自检";
            cell.detailTextLabel.text = @"课表存在哪、是否可写";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;

        case CALSettingSectionReload:
            cell.textLabel.text = @"重载诊断";
            cell.detailTextLabel.text = @"扫描系统通知名";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            break;

        default:
            break;
    }
    return cell;
}

- (nullable NSString *)tableView:(UITableView *)tableView
         titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case CALSettingSectionAlarm:       return @"闹钟";
        case CALSettingSectionTimetable:   return @"课表";
        case CALSettingSectionIntentProbe: return @"锁屏探针";
        case CALSettingSectionDiagnostics: return @"诊断";
        case CALSettingSectionReload:      return @"重载诊断";
        default: return nil;
    }
}

- (nullable NSString *)tableView:(UITableView *)tableView
         titleForFooterInSection:(NSInteger)section {
    if (section == CALSettingSectionAlarm) {
        return @"闹钟时间 = 当天第一节课开始时间 − 提前量";
    }
    if (section == CALSettingSectionIntentProbe) {
        return @"锁屏时系统禁止「打开 App / 打开 URL」，所以 xiangke://apply 在锁屏必定失败。\n"
                "App 被系统在后台唤醒时（锁屏也可能）会自动记一条，用来验证"
                "「锁屏下能否读写系统文件」—— 系统偏好文件受数据保护限制，"
                "这是整套方案能否在锁屏下工作的关键。";
    }
    if (section == CALSettingSectionDiagnostics) {
        return @"课表保存在磁盘上，重启 App 不会丢。保存失败会在这里显示原因。";
    }
    if (section == CALSettingSectionReload) {
        return @"扫描 mobiletimerd 与时钟 App 的可执行文件，找出系统内部用的通知名 —— "
                "用来把「重启守护进程」换成更温和的通知方式。结果请截图反馈。";
    }
    return nil;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    switch (indexPath.section) {
        case CALSettingSectionAlarm:
            [self promptAdvanceMinutes];
            break;
        case CALSettingSectionTimetable:
            [self confirmLoadSample];
            break;
        case CALSettingSectionIntentProbe:
            if (indexPath.row == 0) {
                [self runProbeManually];
            } else {
                [self showIntentProbe];
            }
            break;
        case CALSettingSectionDiagnostics:
            [self showDiagnostics];
            break;
        case CALSettingSectionReload:
            [self runReloadDiagnostics];
            break;
        default:
            break;
    }
}

#pragma mark - 动作

- (void)promptAdvanceMinutes {
    NSInteger current = self.timetable.advanceMinutes;
    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:@"提前提醒"
                                            message:@"闹钟 = 第一节课开始时间 − 提前量（分钟）"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.placeholder = @"30";
        tf.text = [NSString stringWithFormat:@"%ld", (long)current];
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];

    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"保存"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *action) {
        NSInteger v = [ac.textFields.firstObject.text integerValue];
        if (v <= 0) v = 30;
        if (v > 600) v = 600;

        CALTimetableStore *store = [CALTimetableStore shared];
        store.timetable.advanceMinutes = v;
        [weakSelf saveAndReport:store];
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)confirmLoadSample {
    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:@"载入示例课表"
                                            message:@"会覆盖当前课表，确定继续？"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"载入"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *action) {
        [weakSelf loadSampleTimetable];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)loadSampleTimetable {
    CALTimetableStore *store = [CALTimetableStore shared];
    store.timetable.advanceMinutes = 30;
    store.timetable.courses = @[
        [CALCourse courseWithWeekday:1 start:@"08:00" end:@"09:40" name:@"高等数学"],
        [CALCourse courseWithWeekday:1 start:@"10:00" end:@"11:40" name:@"大学英语"],
        [CALCourse courseWithWeekday:2 start:@"09:00" end:@"10:40" name:@"线性代数"],
        [CALCourse courseWithWeekday:3 start:@"08:00" end:@"09:40" name:@"数据结构"],
        [CALCourse courseWithWeekday:4 start:@"10:00" end:@"11:40" name:@"操作系统"],
        [CALCourse courseWithWeekday:5 start:@"08:30" end:@"10:10" name:@"计算机网络"],
    ];

    BOOL ok = [store save];
    [self.tableView reloadData];

    [self alertWithTitle:(ok ? @"已载入示例课表" : @"⚠️ 载入失败")
                 message:(ok ? @"6 节课已写入。回主页点「立即应用」即可设置闹钟。"
                             : [store storageDiagnostics])];
}

- (void)showDiagnostics {
    [self alertWithTitle:@"存储自检"
                 message:[[CALTimetableStore shared] storageDiagnostics]];
}

#pragma mark - 锁屏探针

/// 手动跑一次 —— 用来拿一条「已知解锁状态」的基准记录做对照
- (void)runProbeManually {
    NSString *report = [CALProbe runWithTrigger:@"手动（App 内）"];
    [self alertWithTitle:@"已记录一次" message:report];
}

- (void)showIntentProbe {
    NSString *content = [CALProbe readLog];

    if (content.length == 0) {
        NSMutableString *scanned = [NSMutableString string];
        for (NSString *p in [CALProbe candidatePaths]) {
            [scanned appendFormat:@"· %@\n", p];
        }
        [self alertWithTitle:@"探针记录"
                     message:[NSString stringWithFormat:
            @"还没有记录。\n\n已检查这些位置：\n%@\n"
             "点上一行「跑一次探针」可立即产生一条；\n"
             "App 被系统在后台唤醒时（锁屏也可能）也会自动记一条。",
            scanned]];
        return;
    }

    // 只显示最近的部分，避免弹窗过长
    static const NSUInteger kMaxLen = 3000;
    if (content.length > kMaxLen) {
        content = [NSString stringWithFormat:@"…（仅显示最近 %lu 字符）\n%@",
                   (unsigned long)kMaxLen,
                   [content substringFromIndex:content.length - kMaxLen]];
    }

    [self alertWithTitle:@"探针记录" message:content];
}

#pragma mark - 重载诊断

/// 扫描系统二进制，找出 mobiletimerd / 时钟 App 里出现的通知名候选。
/// 先扫自己的可执行文件做自检 —— 用来区分「扫描逻辑有问题」和「系统文件读不到」。
- (void)runReloadDiagnostics {
    self.navigationItem.prompt = @"扫描中…";

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableString *report = [NSMutableString string];

        // 自检：本 App 可执行文件里必然有 Alarm 相关符号
        NSString *selfPath = [[NSBundle mainBundle] executablePath];
        NSArray<NSString *> *selfHits = [CALDaemonReloader stringsInFile:selfPath
                                                              containing:@"alarm"
                                                                   limit:10];
        [report appendFormat:@"【自检】本 App 可执行文件\n含 alarm 字符串：%lu 条 %@\n\n",
            (unsigned long)selfHits.count,
            selfHits.count > 0 ? @"→ 扫描逻辑正常" : @"⚠️ 扫描逻辑可能有问题"];

        // 逐个试候选路径
        NSArray<NSString *> *candidates = @[
            @"/usr/libexec/mobiletimerd",
            @"/System/Volumes/System/usr/libexec/mobiletimerd",
            @"/Applications/MobileTimer.app/MobileTimer",
            @"/System/Applications/MobileTimer.app/MobileTimer",
        ];

        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *path in candidates) {
            BOOL exists = [fm fileExistsAtPath:path];
            NSDictionary *attr = exists ? [fm attributesOfItemAtPath:path error:nil] : nil;
            unsigned long long size = [attr[NSFileSize] unsignedLongLongValue];

            [report appendFormat:@"%@\n存在：%@", path, exists ? @"是" : @"否"];
            if (exists) [report appendFormat:@"   大小：%llu", size];
            [report appendString:@"\n"];

            if (exists) {
                NSArray<NSString *> *hits = [CALDaemonReloader stringsInFile:path
                                                                  containing:@"alarm"
                                                                       limit:8];
                [report appendFormat:@"含 alarm：%lu 条\n", (unsigned long)hits.count];
                for (NSString *s in hits) {
                    [report appendFormat:@"  %@\n", [self shorten:s max:56]];
                }
            }
            [report appendString:@"\n"];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.navigationItem.prompt = nil;
            [self alertWithTitle:@"重载诊断（截图反馈）" message:report];
        });
    });
}

- (NSString *)shorten:(NSString *)s max:(NSUInteger)max {
    if (s.length <= max) return s;
    return [[s substringToIndex:max] stringByAppendingString:@"…"];
}

#pragma mark - 工具

/// 落盘；失败就把原因摊开
- (void)saveAndReport:(CALTimetableStore *)store {
    if ([store save]) return;
    [self alertWithTitle:@"保存失败" message:[store storageDiagnostics]];
}

- (void)alertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *ac =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好"
                                           style:UIAlertActionStyleDefault
                                         handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
