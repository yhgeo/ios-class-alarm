//
//  CALImportViewController.m
//
//  输入方式（三条，互为备份）：
//    1. 手动输入 / 长按编辑菜单粘贴
//    2. UIPasteControl —— iOS 16 官方粘贴控件，点击即用户授权，不弹窗、必定可读
//    3. 从「文件」App 选本地 JSON（完全不碰剪贴板）
//
//  为什么不用自己读 UIPasteboard：iOS 16 起程序化读取剪贴板会弹权限框，
//  用户一旦拒绝就静默返回空。UIPasteControl 走的是系统授权路径，绕开这个问题。
//

#import "CALImportViewController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#pragma mark - 布局常量

static const CGFloat kMargin  = 16.0;
static const CGFloat kCorner  = 12.0;
static const CGFloat kGap     = 12.0;
static const CGFloat kButtonH = 46.0;
static const CGFloat kEditorH = 120.0;

#pragma mark - URL 归一化

/// 把用户可能粘贴的几种常见地址转成能直接下载的 raw 地址
static NSString *CALNormalizeImportURL(NSString *input) {
    NSString *s = [input stringByTrimmingCharactersInSet:
                   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length == 0) return s;

    // Gist 网页地址 → 补 /raw（NSData 下载会自动跟随 302）
    if ([s hasPrefix:@"https://gist.github.com/"] && ![s containsString:@"/raw"]) {
        return [s stringByAppendingString:@"/raw"];
    }

    // GitHub blob 地址 → raw.githubusercontent.com
    if ([s hasPrefix:@"https://github.com/"] && [s containsString:@"/blob/"]) {
        NSString *rest = [s substringFromIndex:@"https://github.com/".length];
        rest = [rest stringByReplacingOccurrencesOfString:@"/blob/" withString:@"/"];
        return [@"https://raw.githubusercontent.com/" stringByAppendingString:rest];
    }

    return s;
}

#pragma mark -

@interface CALImportViewController () <UITextViewDelegate, UIDocumentPickerDelegate,
                                       UIPasteConfigurationSupporting>
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) UIView *pasteControl;   // 实际是 UIPasteControl
@property (nonatomic, strong) UIButton *fileButton;
@property (nonatomic, strong) UILabel *footnoteLabel;
@end

@implementation CALImportViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"导入课表";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self buildUI];

    self.textView.text = self.initialURLString ?: @"";
    [self updatePlaceholder];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(onCancel)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"导入"
                                         style:UIBarButtonItemStyleDone
                                        target:self
                                        action:@selector(onImport)];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutContent];
}

#pragma mark - UI

- (void)buildUI {
    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.numberOfLines = 0;
    self.hintLabel.font = [UIFont systemFontOfSize:14];
    self.hintLabel.textColor = [UIColor secondaryLabelColor];
    self.hintLabel.text = @"填入课表 JSON 的 https 地址。可以点下面的「粘贴」按钮，"
                           "也可以长按输入框选粘贴。";
    [self.view addSubview:self.hintLabel];

    self.textView = [[UITextView alloc] init];
    self.textView.delegate = self;
    self.textView.font = [UIFont systemFontOfSize:15];
    self.textView.keyboardType = UIKeyboardTypeURL;
    self.textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textView.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textView.spellCheckingType = UITextSpellCheckingTypeNo;
    self.textView.textContainerInset = UIEdgeInsetsMake(10, 12, 10, 12);
    self.textView.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.textView.layer.cornerRadius = kCorner;
    self.textView.clipsToBounds = YES;
    [self.view addSubview:self.textView];

    self.placeholderLabel = [[UILabel alloc] init];
    self.placeholderLabel.font = self.textView.font;
    self.placeholderLabel.textColor = [UIColor placeholderTextColor];
    self.placeholderLabel.text = @"https://...";
    self.placeholderLabel.userInteractionEnabled = NO;
    [self.textView addSubview:self.placeholderLabel];

    // 系统粘贴控件：用户点击即代表授权，不会弹权限框；
    // 剪贴板为空时它会自动置灰，正好当状态提示用。
    //
    // 关键：UIPasteControl 靠 target 的 pasteConfiguration 判断「能接受什么类型」。
    // UIViewController 的这个属性默认是 nil —— 不显式设置的话，系统认为什么都接不了，
    // 按钮会一直置灰、点了毫无反应。所以这里必须配，并由我们自己实现 pasteItemProviders:。
    if (@available(iOS 16.0, *)) {
        self.pasteConfiguration = [[UIPasteConfiguration alloc]
            initWithTypeIdentifiersForAcceptingClass:[NSString class]];

        UIPasteControlConfiguration *config = [[UIPasteControlConfiguration alloc] init];
        config.displayMode = UIPasteControlDisplayModeIconAndLabel;
        config.baseBackgroundColor = [UIColor secondarySystemBackgroundColor];
        config.baseForegroundColor = [UIColor labelColor];

        UIPasteControl *paste = [[UIPasteControl alloc] initWithConfiguration:config];
        paste.target = self;
        self.pasteControl = paste;
        [self.view addSubview:paste];
    }

    self.fileButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.fileButton setTitle:@"从「文件」选 JSON" forState:UIControlStateNormal];
    [self.fileButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    self.fileButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.fileButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.fileButton.layer.cornerRadius = kCorner;
    [self.fileButton addTarget:self
                        action:@selector(onPickFile)
              forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.fileButton];

    self.footnoteLabel = [[UILabel alloc] init];
    self.footnoteLabel.numberOfLines = 0;
    self.footnoteLabel.font = [UIFont systemFontOfSize:12];
    self.footnoteLabel.textColor = [UIColor tertiaryLabelColor];
    self.footnoteLabel.text =
        @"粘贴按钮点了没反应属正常 —— 巨魔环境下系统禁止 App 直接读剪贴板，\n"
        @"请改用「从「文件」选 JSON」（不经过剪贴板，一定可用）。\n"
        @"也可以长按上面的输入框手动粘贴。\n"
        @"支持 Gist：填 gist 页面地址会自动补 /raw；只接受 https。";
    [self.view addSubview:self.footnoteLabel];
}

- (void)layoutContent {
    UIEdgeInsets inset = self.view.safeAreaInsets;
    CGFloat w  = self.view.bounds.size.width;
    CGFloat x  = kMargin;
    CGFloat cw = w - kMargin * 2;
    CGFloat y  = inset.top + kGap;

    CGSize hintFit = [self.hintLabel sizeThatFits:CGSizeMake(cw, CGFLOAT_MAX)];
    self.hintLabel.frame = CGRectMake(x, y, cw, ceil(hintFit.height));
    y = CGRectGetMaxY(self.hintLabel.frame) + kGap;

    self.textView.frame = CGRectMake(x, y, cw, kEditorH);
    y = CGRectGetMaxY(self.textView.frame) + kGap;

    // 占位文字跟着 textView 的内边距走
    UIEdgeInsets ti = self.textView.textContainerInset;
    self.placeholderLabel.frame = CGRectMake(ti.left + 5, ti.top,
                                             cw - ti.left - ti.right - 5, 20);

    if (self.pasteControl) {
        self.pasteControl.frame = CGRectMake(x, y, cw, kButtonH);
        y = CGRectGetMaxY(self.pasteControl.frame) + kGap;
    }

    self.fileButton.frame = CGRectMake(x, y, cw, kButtonH);
    y = CGRectGetMaxY(self.fileButton.frame) + kGap + 4;

    CGSize footFit = [self.footnoteLabel sizeThatFits:CGSizeMake(cw, CGFLOAT_MAX)];
    self.footnoteLabel.frame = CGRectMake(x, y, cw, ceil(footFit.height));
}

- (void)updatePlaceholder {
    self.placeholderLabel.hidden = (self.textView.text.length > 0);
}

#pragma mark - 动作

- (void)onCancel {
    [self.delegate importControllerDidCancel:self];
}

- (void)onImport {
    NSString *url = CALNormalizeImportURL(self.textView.text);
    if (url.length == 0) {
        [self alertWithTitle:@"还没填地址"
                     message:@"请粘贴或输入课表 JSON 的 https 地址，"
                              "也可以点「从「文件」选 JSON」。"];
        return;
    }
    [self.delegate importController:self didFinishWithURLString:url];
}

- (void)onPickFile {
    // 两个关键点：
    // 1) asCopy:NO（就地打开）—— asCopy:YES 要系统把文件拷进 App 容器，
    //    本 App 带 no-sandbox、没有常规容器路径，会导致选择器里文件全都不可选。
    // 2) 类型放宽到 UTTypeData —— 只写 UTTypeJSON 时，凡是系统没识别成 public.json
    //    的文件（比如从聊天软件存下来的）都会是灰的、点不动。
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[UTTypeJSON, UTTypeText, UTTypeData]
                                asCopy:NO];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
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

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    [self updatePlaceholder];
}

#pragma mark - UIPasteConfigurationSupporting

/// UIPasteControl 被点击后，系统把剪贴板内容以 NSItemProvider 交到这里。
/// 此时用户已经表达过粘贴意图，系统不会再弹权限框。
///
/// 但实测（TrollStore / no-sandbox / iOS 16.6.1）三条常规路径都可能被挡：
///   · 直接读 UIPasteboard → hasStrings 为真但 string 返回空（被静默拒绝）
///   · loadObjectOfClass:  → Cannot load representation of type public.utf8-plain-text
/// 所以这里多铺一条「直接取原始 data」的路：绕开类型转换（coercion）这一步，
/// 拿 NSData 自己解成字符串。
- (void)pasteItemProviders:(NSArray<NSItemProvider *> *)itemProviders {
    NSMutableString *trace = [NSMutableString string];

    // 路径 1：直接读剪贴板
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *text = nil;

    if (pasteboard.hasStrings) {
        text = pasteboard.string;
        if (text.length == 0) text = pasteboard.strings.firstObject;
        [trace appendFormat:@"· 直接读取剪贴板：%@\n", text.length > 0 ? @"成功" : @"拿到空值（被拒）"];
    } else {
        [trace appendString:@"· 直接读取剪贴板：系统报告没有文本\n"];
    }

    if (text.length > 0) {
        [self fillWithText:text];
        return;
    }

    // 挑一个能提供文本的 provider
    NSItemProvider *provider = nil;
    for (NSItemProvider *p in itemProviders) {
        if ([p hasItemConformingToTypeIdentifier:@"public.utf8-plain-text"]) {
            provider = p;
            break;
        }
    }
    if (!provider) {
        for (NSItemProvider *p in itemProviders) {
            if ([p canLoadObjectOfClass:[NSString class]]) {
                provider = p;
                break;
            }
        }
    }

    if (!provider) {
        [trace appendFormat:@"· 系统提供的数据：%lu 项，没有文本类型\n",
                             (unsigned long)itemProviders.count];
        [self alertWithTitle:@"拿不到文本" message:trace];
        return;
    }

    __weak typeof(self) weakSelf = self;

    // 路径 2：直接取原始 data（不要求转换成 NSString，避开 coercion）
    [provider loadDataRepresentationForTypeIdentifier:@"public.utf8-plain-text"
                                    completionHandler:^(NSData *data, NSError *dataError) {
        NSString *fromData = nil;
        if (data.length > 0) {
            fromData = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (fromData.length == 0) {
                fromData = [[NSString alloc] initWithData:data encoding:NSUnicodeStringEncoding];
            }
        }

        if (fromData.length > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf fillWithText:fromData]; });
            return;
        }

        // 路径 3：退回类型转换
        [provider loadObjectOfClass:[NSString class]
                  completionHandler:^(id<NSItemProviderReading> object, NSError *objectError) {
            NSString *fromObject = [object isKindOfClass:[NSString class]] ? (NSString *)object : nil;

            dispatch_async(dispatch_get_main_queue(), ^{
                if (fromObject.length > 0) {
                    [weakSelf fillWithText:fromObject];
                    return;
                }
                [trace appendFormat:@"· 取原始数据：%@\n", dataError.localizedDescription ?: @"空"];
                [trace appendFormat:@"· 类型转换：%@\n", objectError.localizedDescription ?: @"空"];
                [weakSelf alertWithTitle:@"拿不到文本" message:trace];
            });
        }];
    }];
}

/// 把拿到的文本填进输入框
- (void)fillWithText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        [self alertWithTitle:@"拿不到文本" message:@"剪贴板里没有文字内容。"];
        return;
    }
    self.textView.text = trimmed;
    [self updatePlaceholder];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (url) [self.delegate importController:self didPickFileAtURL:url];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // 用户取消，什么都不做
}

@end
