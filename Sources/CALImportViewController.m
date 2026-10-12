//
//  CALImportViewController.m
//

#import "CALImportViewController.h"

#pragma mark - 布局常量

static const CGFloat kMargin   = 16.0;
static const CGFloat kCorner   = 12.0;
static const CGFloat kGap      = 12.0;
static const CGFloat kButtonH  = 46.0;
static const CGFloat kEditorH  = 132.0;

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

@interface CALImportViewController () <UITextViewDelegate>
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic, strong) UIButton *pasteButton;
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
    self.hintLabel.text = @"填入课表 JSON 的 https 地址。可以直接粘贴，或点下面的按钮从剪贴板取。";
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

    self.pasteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pasteButton setTitle:@"从剪贴板粘贴" forState:UIControlStateNormal];
    [self.pasteButton setTitleColor:[UIColor labelColor] forState:UIControlStateNormal];
    self.pasteButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.pasteButton.backgroundColor = [UIColor secondarySystemBackgroundColor];
    self.pasteButton.layer.cornerRadius = kCorner;
    [self.pasteButton addTarget:self
                         action:@selector(onPasteFromClipboard)
               forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.pasteButton];

    self.footnoteLabel = [[UILabel alloc] init];
    self.footnoteLabel.numberOfLines = 0;
    self.footnoteLabel.font = [UIFont systemFontOfSize:12];
    self.footnoteLabel.textColor = [UIColor tertiaryLabelColor];
    self.footnoteLabel.text =
        @"支持 GitHub Gist：填 gist 页面地址即可，会自动补 /raw。\n"
        @"只接受 https —— iOS 默认禁止明文 http 请求。\n"
        @"导入会整体替换当前课表。";
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

    self.pasteButton.frame = CGRectMake(x, y, cw, kButtonH);
    y = CGRectGetMaxY(self.pasteButton.frame) + kGap + 4;

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
        UIAlertController *ac =
            [UIAlertController alertControllerWithTitle:@"还没填地址"
                                                message:@"请粘贴或输入课表 JSON 的 https 地址。"
                                         preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"好"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }
    [self.delegate importController:self didFinishWithURLString:url];
}

- (void)onPasteFromClipboard {
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSString *text = pasteboard.string;

    if (text.length == 0) {
        UIAlertController *ac =
            [UIAlertController alertControllerWithTitle:@"剪贴板是空的"
                                                message:@"先复制课表 JSON 的地址，再回来点这个按钮。"
                                         preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"好"
                                               style:UIAlertActionStyleDefault
                                             handler:nil]];
        [self presentViewController:ac animated:YES completion:nil];
        return;
    }

    self.textView.text = [text stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self updatePlaceholder];
}

#pragma mark - UITextViewDelegate

- (void)textViewDidChange:(UITextView *)textView {
    [self updatePlaceholder];
}

@end
