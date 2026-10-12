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
        @"粘贴按钮是灰的 = 剪贴板里没有文字（先去别处复制地址）。\n"
        @"粘贴和长按都不行的话，用「从「文件」选 JSON」——那条路不碰剪贴板。\n"
        @"支持 GitHub Gist：填 gist 页面地址会自动补 /raw；只接受 https。";
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
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[UTTypeJSON, UTTypePlainText]
                                asCopy:YES];
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
/// 此时已经过用户授权，不会再弹权限框。
- (void)pasteItemProviders:(NSArray<NSItemProvider *> *)itemProviders {
    NSItemProvider *provider = nil;
    for (NSItemProvider *p in itemProviders) {
        if ([p canLoadObjectOfClass:[NSString class]]) {
            provider = p;
            break;
        }
    }

    if (!provider) {
        [self alertWithTitle:@"拿不到文本"
                     message:(itemProviders.count == 0
                                ? @"剪贴板里没有内容。先去别处复制课表地址再回来。"
                                : @"剪贴板里的内容不是文字。")];
        return;
    }

    __weak typeof(self) weakSelf = self;
    [provider loadObjectOfClass:[NSString class]
              completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        NSString *text = [object isKindOfClass:[NSString class]] ? (NSString *)object : nil;
        NSString *trimmed = [text stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (trimmed.length == 0) {
                [weakSelf alertWithTitle:@"拿不到文本"
                                 message:error.localizedDescription ?: @"剪贴板内容为空。"];
                return;
            }
            weakSelf.textView.text = trimmed;
            [weakSelf updatePlaceholder];
        });
    }];
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
