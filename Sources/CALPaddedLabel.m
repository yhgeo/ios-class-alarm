//
//  CALPaddedLabel.m
//

#import "CALPaddedLabel.h"

@implementation CALPaddedLabel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _padding = UIEdgeInsetsMake(14, 14, 14, 14);
    }
    return self;
}

- (CGRect)cal_insetRect:(CGRect)rect {
    UIEdgeInsets p = self.padding;
    return CGRectMake(rect.origin.x + p.left,
                      rect.origin.y + p.top,
                      MAX(0.0, rect.size.width - p.left - p.right),
                      MAX(0.0, rect.size.height - p.top - p.bottom));
}

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:[self cal_insetRect:rect]];
}

- (CGRect)textRectForBounds:(CGRect)bounds limitedToNumberOfLines:(NSInteger)numberOfLines {
    CGRect r = [super textRectForBounds:[self cal_insetRect:bounds]
                 limitedToNumberOfLines:numberOfLines];
    UIEdgeInsets p = self.padding;
    r.origin.x    -= p.left;
    r.origin.y    -= p.top;
    r.size.width  += p.left + p.right;
    r.size.height += p.top + p.bottom;
    return r;
}

@end
