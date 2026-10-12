//
//  CALHomeViewController.m
//  主界面：显示当前状态，提供「应用」「编辑课表」「载入示例」「存储自检」「清理」五个动作。
//  只调用 CALApplier / CALTimetableStore，不直接碰底层。
//

#import "CALHomeViewController.h"
#import "CALApplier.h"
#import "CALAlarmStore.h"
#import "CALTimetable.h"
#import "CALTimetableViewController.h"
#import "CALImportViewController.h"
#import "CALSettingsViewController.h"
#import "CALPaddedLabel.h"

#pragma mark - 布局常量

static const CGFloat kMargin       = 16.0;
static const CGFloat kButtonHeight = 48.0;
static const CGFloat kButtonGap    = 12.0;
static const CGFloat kCorner       = 12.0;

#pragma mark - Home

@interface CALHomeViewController () <CALImportDelegate>
@property (nonatomic, strong) CALPaddedLabel *statusLabel;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) NSArray<UIButton *> *buttons;
@end

@implementation CALHomeViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"响课";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    [self buildUI];
    [self refreshStatus];
    self.logView.text = @"准备就绪。点「立即应用」按课表设置次日闹钟。";

    // 快捷指令通过 xiangke://apply 唤起后，结果从这里回来
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(onApplyFromURL:)
                                                 name:CALDidApplyNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

#pragma mark - UI

- (void)buildUI {
    self.statusLabel = [[CALPaddedLabel alloc] init];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.padding = UIEdgeInsetsMake(14, 14, 14, 14);
    self.statusLabel.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.statusLabel.layer.cornerRadius = kCorner;
    self.statusLabel.clipsToBounds = YES;
    [self.view addSubview:self.statusLabel];

    NSArray<NSString *> *titles = @[@"立即应用（设置次日闹钟）",
                                    @"编辑课表",
                                    @"导入课表（URL）",
                                    @"清理课表闹钟",
                                    @"设置"];
    NSArray<NSString *> *selectors = @[@"onApply", @"onEditTimetable",
                                       @"onImport", @"onClear", @"onSettings"];

    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        [b setTitle:titles[i] forState:UIControlStateNormal];
        [b setTitleColor:(i == 0 ? [UIColor whiteColor] : [UIColor labelColor])
                forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        b.backgroundColor = (i == 0 ? [UIColor systemBlueColor]
                                    : [UIColor secondarySystemBackgroundColor]);
        b.layer.cornerRadius = kCorner;
        [b addTarget:self
              action:NSSelectorFromString(selectors[i])
    forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:b];
        [buttons addObject:b];
    }
    self.buttons = buttons;

    self.logView = [[UITextView alloc] init];
    self.logView.editable = NO;
    self.logView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.logView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.logView.layer.cornerRadius = kCorner;
    self.logView.clipsToBounds = YES;
    self.logView.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);
    [self.view addSubview:self.logView];
}

- (void)layoutContent {
    UIEdgeInsets inset = self.view.safeAreaInsets;
    CGFloat w  = self.view.bounds.size.width;
    CGFloat cw = w - kMargin * 2;

    CGFloat y = inset.top + 12;

    // 状态卡片：高度按内容自适应
    CGSize fit = [self.statusLabel sizeThatFits:CGSizeMake(cw, CGFLOAT_MAX)];
    self.statusLabel.frame = CGRectMake(kMargin, y, cw, ceil(fit.height));
    y = CGRectGetMaxY(self.statusLabel.frame) + 16;

    // 按钮：等宽等高、等间距
    for (UIButton *b in self.buttons) {
        b.frame = CGRectMake(kMargin, y, cw, kButtonHeight);
        y += kButtonHeight + kButtonGap;
    }

    // 日志区填满剩余空间
    CGFloat logTop    = y + 4;
    CGFloat logBottom = self.view.bounds.size.height - inset.bottom - 12;
    self.logView.frame = CGRectMake(kMargin, logTop, cw, MAX(80.0, logBottom - logTop));
}

#pragma mark - 状态

- (void)refreshStatus {
    CALTimetable *tt = [CALTimetableStore shared].timetable;
    NSString *summary = [CALApplier statusSummaryWithTimetable:tt];

    NSMutableString *s = [NSMutableString stringWithString:summary];
    // 注意：课表可以只写在 overrides 里（按日期逐天写），这时 courses 为空但课表并不空
    if (tt.courses.count == 0 && tt.overrides.count == 0) {
        [s appendString:@"\n⚠️ 课表为空 —— 可到「设置」载入示例，或点「导入课表」"];
    }
    [s appendFormat:@"\n提前量：%ld 分钟", (long)tt.advanceMinutes];
    self.statusLabel.text = s;
    [self.view setNeedsLayout];
}

#pragma mark - 动作

- (void)onApply {
    self.logView.text = @"执行中…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        CALTimetable *tt = [CALTimetableStore shared].timetable;
        NSString *log = [CALApplier applyTimetable:tt];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = log;
            [self refreshStatus];
        });
    });
}

- (void)onEditTimetable {
    CALTimetableViewController *vc = [[CALTimetableViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)onSettings {
    CALSettingsViewController *vc = [[CALSettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 导入课表

- (void)onImport {
    CALImportViewController *vc = [[CALImportViewController alloc] init];
    vc.delegate = self;
    vc.initialURLString = [[NSUserDefaults standardUserDefaults] stringForKey:@"CALImportURL"];

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    [self presentViewController:nav animated:YES completion:nil];
}

#pragma mark - CALImportDelegate

- (void)importController:(CALImportViewController *)controller
    didFinishWithURLString:(NSString *)urlString {
    [self dismissViewControllerAnimated:YES completion:^{
        [self importFromURLString:urlString];
    }];
}

- (void)importControllerDidCancel:(CALImportViewController *)controller {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)importController:(CALImportViewController *)controller
         didPickFileAtURL:(NSURL *)fileURL {
    [self dismissViewControllerAnimated:YES completion:^{
        [self importFromFileURL:fileURL];
    }];
}

- (void)importFromURLString:(NSString *)urlString {
    NSURL *url = urlString.length ? [NSURL URLWithString:urlString] : nil;
    if (!url) {
        self.logView.text = @"⚠️ URL 无效。";
        return;
    }
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) {
        self.logView.text = @"⚠️ 只支持 https —— iOS 默认禁止明文 http 请求。";
        return;
    }

    [[NSUserDefaults standardUserDefaults] setObject:urlString forKey:@"CALImportURL"];
    self.logView.text = [NSString stringWithFormat:@"下载中…\n%@", urlString];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *netError = nil;
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&netError];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (data.length == 0) {
                self.logView.text = [NSString stringWithFormat:@"⚠️ 下载失败：%@",
                                     netError.localizedDescription ?: @"没有拿到数据"];
                return;
            }
            [self applyImportedData:data];
        });
    });
}

- (void)importFromFileURL:(NSURL *)fileURL {
    self.logView.text = [NSString stringWithFormat:@"读取文件…\n%@",
                         fileURL.lastPathComponent ?: @"(未知文件)"];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        // asCopy:YES 时其实不需要，但对 open-in-place 的文件是必需的，加上更稳
        BOOL scoped = [fileURL startAccessingSecurityScopedResource];
        NSError *readError = nil;
        NSData *data = [NSData dataWithContentsOfURL:fileURL options:0 error:&readError];
        if (scoped) [fileURL stopAccessingSecurityScopedResource];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (data.length == 0) {
                self.logView.text = [NSString stringWithFormat:@"⚠️ 读取文件失败：%@",
                                     readError.localizedDescription ?: @"文件是空的"];
                return;
            }
            [self applyImportedData:data];
        });
    });
}

/// 解析并保存导入的数据 —— URL 导入与文件导入共用
- (void)applyImportedData:(NSData *)data {
    // 常见的坑：填的是网页地址，拿回来是一坨 HTML
    NSUInteger probeLen = MIN((NSUInteger)128, data.length);
    NSString *head = [[NSString alloc]
        initWithData:[data subdataWithRange:NSMakeRange(0, probeLen)]
            encoding:NSUTF8StringEncoding];
    if (head.length > 0 &&
        ([head containsString:@"<!DOCTYPE"] || [head containsString:@"<!doctype"] ||
         [head containsString:@"<html"]      || [head containsString:@"<HTML"])) {
        self.logView.text =
            @"⚠️ 内容不是 JSON，而是一个网页。\n\n"
             "多半是地址填成了网页地址，请改用 raw 地址：\n"
             "· GitHub Gist：点右上角 Raw 后复制地址栏（填 gist 页面地址会自动补 /raw）\n"
             "· GitHub 仓库：用 raw.githubusercontent.com 开头的地址";
        return;
    }

    CALTimetableStore *store = [CALTimetableStore shared];
    NSError *importError = nil;
    if (![store importFromJSONData:data error:&importError]) {
        self.logView.text = [NSString stringWithFormat:
            @"⚠️ 解析或保存失败：%@\n\n请检查 JSON 格式（字段说明见 README）。",
            importError.localizedDescription ?: @"未知错误"];
        return;
    }

    CALTimetable *tt = store.timetable;
    self.logView.text = [NSString stringWithFormat:
        @"✅ 导入成功\n常规课表 %lu 节 · 按日期 %lu 天 · 提前量 %ld 分钟\n\n%@",
        (unsigned long)tt.courses.count, (unsigned long)tt.overrides.count,
        (long)tt.advanceMinutes, [store storageDiagnostics]];
    [self refreshStatus];
}

#pragma mark - URL 唤起

- (void)onApplyFromURL:(NSNotification *)note {
    NSString *log = note.userInfo[@"log"];
    if ([log isKindOfClass:[NSString class]] && log.length > 0) {
        self.logView.text = [NSString stringWithFormat:@"（由 xiangke://apply 触发）\n%@", log];
    }
    [self refreshStatus];
}

- (void)onClear {
    self.logView.text = @"清理中…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSInteger n = [CALApplier clearManagedAlarms];
        NSString *msg = [NSString stringWithFormat:@"已清理 %ld 个课表闹钟。\n", (long)n];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = msg;
            [self refreshStatus];
        });
    });
}

@end
