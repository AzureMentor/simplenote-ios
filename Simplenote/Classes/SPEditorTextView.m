//
//  SPEditorTextView.m
//  Simplenote
//
//  Created by Tom Witkin on 8/16/13.
//  Copyright (c) 2013 Automattic. All rights reserved.
//

#import "SPEditorTextView.h"
#import "SPTagView.h"
#import "SPInteractiveTextStorage.h"
#import "NSAttributedString+Styling.h"
#import "NSMutableAttributedString+Styling.h"
#import "NSString+Attributed.h"
#import "UIDevice+Extensions.h"
#import "UIImage+Colorization.h"
#import "VSTheme+Extensions.h"
#import "Simplenote-Swift.h"

NSString *const CheckListRegExPattern = @"^(\\s+)?(-[ \t]+\\[[xX\\s]\\])";
NSString *const MarkdownUnchecked = @"- [ ]";
NSString *const MarkdownChecked = @"- [x]";
NSString *const TextAttachmentCharacterCode = @"\U0000fffc"; // Represents the glyph of an NSTextAttachment

// One unicode character plus a space
NSInteger const ChecklistCursorAdjustment = 2;

@interface SPEditorTextView ()<UIGestureRecognizerDelegate>

@property (strong, nonatomic) NSArray *textCommands;
@property (nonatomic) UITextLayoutDirection verticalMoveDirection;
@property (nonatomic) CGRect verticalMoveStartCaretRect;
@property (nonatomic) CGRect verticalMoveLastCaretRect;
@property (nonatomic) NSInteger lastCursorPosition;

@end

@implementation SPEditorTextView

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (instancetype)init {
    
    self = [super init];
    if (self) {
        self.alwaysBounceHorizontal = NO;
        self.alwaysBounceVertical = YES;
        self.scrollEnabled = YES;
        self.verticalMoveStartCaretRect = CGRectZero;
        self.verticalMoveLastCaretRect = CGRectZero;
        
        // add tag view
        
        CGFloat tagViewHeight = [self.theme floatForKey:@"tagViewHeight"];
        _tagView = [[SPTagView alloc] initWithFrame:CGRectMake(0, 0, 0, tagViewHeight)];
        _tagView.isAccessibilityElement = NO;
        
        [self addSubview:_tagView];
        
        UIEdgeInsets contentInset = self.contentInset;
        contentInset.bottom += 2 * tagViewHeight;
        contentInset.top += [self.theme floatForKey:@"noteTopPadding"];
        self.contentInset = contentInset;
        
        [self addObserver:self
               forKeyPath:@"contentSize"
                  options:NSKeyValueObservingOptionNew
                  context:NULL];
        [self addObserver:self
               forKeyPath:@"contentOffset"
                  options:NSKeyValueObservingOptionNew
                  context:NULL];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didEndEditing:)
                                                     name:UITextViewTextDidEndEditingNotification
                                                   object:nil];
        

        UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc]
                                                        initWithTarget:self
                                                        action:@selector(onTextTapped:)];
        tapGestureRecognizer.delegate = self;
        tapGestureRecognizer.cancelsTouchesInView = NO;
        
        [self addGestureRecognizer:tapGestureRecognizer];
        [self setEditing:NO];
    }
    return self;
}

- (VSTheme *)theme {
    return [[VSThemeManager sharedManager] theme];
}

- (NSDictionary *)typingAttributes {
    
    return [self.interactiveTextStorage.tokens objectForKey:SPDefaultTokenName];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    
    if (object == self && ([keyPath isEqualToString:@"contentOffset"] || [keyPath isEqualToString:@"contentSize"]))
        [self positionTagView];
}


- (void)layoutSubviews {
    
    [super layoutSubviews];
    
    CGFloat padding = [self.theme floatForKey:@"noteSidePadding" contextView:self];
    if (@available(iOS 11.0, *)) {
        padding += self.safeAreaInsets.left;
    }
    CGFloat maxWidth = [self.theme floatForKey:@"noteMaxWidth"];
    CGFloat width = self.bounds.size.width;
    
    if (width - 2 * padding > maxWidth && maxWidth > 0)
        padding = (width - maxWidth) / 2.0;
    
    self.textContainer.lineFragmentPadding = padding;
    
    // position tag view at bottom
    [self positionTagView];
}

- (void)positionTagView {
    
    CGFloat height = _tagView.frame.size.height;
    CGFloat yOrigin = self.contentSize.height - height + self.contentInset.top;
    yOrigin = MAX(yOrigin, self.contentOffset.y + self.bounds.size.height - height);
    
    CGFloat tagPadding = 0;
    if (@available(iOS 11.0, *)) {
        tagPadding = self.safeAreaInsets.left;
    }
    
    CGRect footerViewFrame = CGRectMake(tagPadding,
                                        yOrigin,
                                        self.bounds.size.width - 2 * tagPadding,
                                        height);
    _tagView.frame = footerViewFrame;
}

- (void)setTagView:(SPTagView *)tagView {
    
    if (_tagView) {
        [_tagView removeFromSuperview];
    }
    
    [self addSubview:tagView];
    _tagView = tagView;
    [self setNeedsLayout];
}

- (void)setEditing:(BOOL)editing {
    
    _editing = editing;
    self.editable = editing;
    
    // HACK:
    // God, forgive me. After enabling edit mode, "former" linkified substrings are rendered with a black color.
    // This forces UITextView to render those substrings with the same color as the rest of the TextView.
    self.textColor = self.textColor;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    // Limit a recognized touch to the SPTextView, so that taps on tags still work as expected
    return [touch.view isKindOfClass:[SPTextView class]];
}

- (BOOL)becomeFirstResponder {
    [self setEditing:YES];
    return [super becomeFirstResponder];
}

- (BOOL)resignFirstResponder {
        
    BOOL response = [super resignFirstResponder];
    [self setNeedsLayout];
    return response;
}

- (void)scrollToBottom {
    
    if (self.contentSize.height > self.bounds.size.height - self.contentInset.top - self.contentInset.bottom) {
        
        CGPoint scrollOffset = CGPointMake(0,
                                           self.contentSize.height + self.contentInset.bottom - self.bounds.size.height);
        [self setContentOffset:scrollOffset animated:NO];
    }
}

- (void)scrollToTop {
    CGFloat yOffset = self.bounds.origin.y - self.contentInset.top;
    CGPoint scrollOffset = CGPointMake(0, yOffset);
    [self setContentOffset:scrollOffset animated:NO];
}

#pragma mark Notifications

- (void)didEndEditing:(NSNotification *)notification {
    
    [self setEditing:NO];
}

// Fixes are modified versions of https://gist.github.com/agiletortoise/a24ccbf2d33aafb2abc1

#pragma mark fixes for UITextView bugs in iOS 7

- (UITextPosition *)closestPositionToPoint:(CGPoint)point {
    
    point.y -= self.textContainerInset.top;
    point.x -= self.textContainerInset.left;
    
    NSUInteger glyphIndex = [self.layoutManager glyphIndexForPoint:point inTextContainer:self.textContainer];
    NSUInteger characterIndex = [self.layoutManager characterIndexForGlyphAtIndex:glyphIndex];
    
    if (characterIndex >= self.text.length - 1 && ![self.text hasSuffix:@"\n"])
        characterIndex ++;
    
    UITextPosition *pos = [self positionFromPosition:self.beginningOfDocument offset:characterIndex];
    
    return pos;
}

- (void)scrollRangeToVisible:(NSRange)range
{
    [super scrollRangeToVisible:range];
    
    if (self.layoutManager.extraLineFragmentTextContainer != nil && self.selectedRange.location == range.location)
    {
        CGRect caretRect = [self caretRectForPosition:self.selectedTextRange.start];
        [self scrollRectToVisible:caretRect animated:YES];
    }
}

- (NSUInteger)characterIndexForPoint:(CGPoint)point
{
    if (self.text.length == 0) {
        return 0;
    }
    
    CGRect r1;
    if ([[self.text substringFromIndex:self.text.length-1] isEqualToString:@"\n"]) {
        r1 = [super caretRectForPosition:[super positionFromPosition:self.endOfDocument offset:-1]];
        CGRect sr = [super caretRectForPosition:[super positionFromPosition:self.beginningOfDocument offset:0]];
        r1.origin.x = sr.origin.x;
        r1.origin.y += self.font.lineHeight;
    } else {
        r1 = [super caretRectForPosition:[super positionFromPosition:self.endOfDocument offset:0]];
    }
    
    if ((point.x > r1.origin.x && point.y >= r1.origin.y) || point.y >= r1.origin.y+r1.size.height) {
        return [super offsetFromPosition:self.beginningOfDocument toPosition:self.endOfDocument];
    }
    
    CGFloat fraction;
    NSUInteger index = [self.textStorage.layoutManagers[0] characterIndexForPoint:point inTextContainer:self.textContainer fractionOfDistanceBetweenInsertionPoints:&fraction];
    
    return index;
}

- (CGRect)firstRectForRange:(UITextRange *)range
{
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0) {
        CGRect r1= [self caretRectForPosition:[self positionWithinRange:range farthestInDirection:UITextLayoutDirectionRight]];
        CGRect r2= [self caretRectForPosition:[self positionWithinRange:range farthestInDirection:UITextLayoutDirectionLeft]];
        return CGRectUnion(r1,r2);
    }
    return [super firstRectForRange:range];
}

// From https://gist.github.com/rcabaco/6765778
#pragma mark Keyboard Commands
    
- (NSArray *)keyCommands
{
    if (!self.textCommands) {
        UIKeyCommand *upCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputUpArrow modifierFlags:0 action:@selector(moveUp:)];
        UIKeyCommand *downCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputDownArrow modifierFlags:0 action:@selector(moveDown:)];
        self.textCommands = @[upCommand, downCommand];
    }
    return self.textCommands;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    if (action == @selector(moveUp:) || action == @selector(moveDown:)) {
        return YES;
    }
    return [super canPerformAction:action withSender:sender];
}

#pragma mark -

- (void)moveUp:(id)sender
{
    UITextPosition *p0 = self.selectedTextRange.start;
    if ([self isNewVerticalMovementForPosition:p0 inDirection:UITextLayoutDirectionUp]) {
        self.verticalMoveDirection = UITextLayoutDirectionUp;
        self.verticalMoveStartCaretRect = [self caretRectForPosition:p0];
    }
    
    if (p0) {
        UITextPosition *p1 = [self closestPositionToPosition:p0 inDirection:UITextLayoutDirectionUp];
        if (p1) {
            self.verticalMoveLastCaretRect = [self caretRectForPosition:p1];
            UITextRange *r = [self textRangeFromPosition:p1 toPosition:p1];
            self.selectedTextRange = r;
        }
    }
}

- (void)moveDown:(id)sender
{
    UITextPosition *p0 = self.selectedTextRange.end;
    if ([self isNewVerticalMovementForPosition:p0 inDirection:UITextLayoutDirectionDown]) {
        self.verticalMoveDirection = UITextLayoutDirectionDown;
        self.verticalMoveStartCaretRect = [self caretRectForPosition:p0];
    }
    
    if (p0) {
        UITextPosition *p1 = [self closestPositionToPosition:p0 inDirection:UITextLayoutDirectionDown];
        if (p1) {
            self.verticalMoveLastCaretRect = [self caretRectForPosition:p1];
            UITextRange* r = [self textRangeFromPosition:p1 toPosition:p1];
            self.selectedTextRange = r;
        }
    }
}

- (UITextPosition *)closestPositionToPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction
{
    // Currently only up and down are implemented.
    NSParameterAssert(direction == UITextLayoutDirectionUp || direction == UITextLayoutDirectionDown);
    
    // Translate the vertical direction to a horizontal direction.
    UITextLayoutDirection lookupDirection = (direction == UITextLayoutDirectionUp) ? UITextLayoutDirectionLeft : UITextLayoutDirectionRight;
    
    // Walk one character at a time in `lookupDirection` until the next line is reached.
    UITextPosition *checkPosition = position;
    UITextPosition *closestPosition = position;
    CGRect startingCaretRect = [self caretRectForPosition:position];
    CGRect nextLineCaretRect;
    BOOL isInNextLine = NO;
    while (YES) {
        UITextPosition *nextPosition = [self positionFromPosition:checkPosition inDirection:lookupDirection offset:1];
        if (!nextPosition || [self comparePosition:checkPosition toPosition:nextPosition] == NSOrderedSame) {
            // End of line.
            break;
        }
        
        checkPosition = nextPosition;
        CGRect checkRect = [self caretRectForPosition:checkPosition];
        if (CGRectGetMidY(startingCaretRect) != CGRectGetMidY(checkRect)) {
            // While on the next line stop just above/below the starting position.
            if (lookupDirection == UITextLayoutDirectionLeft && CGRectGetMidX(checkRect) <= CGRectGetMidX(self.verticalMoveStartCaretRect)) {
                closestPosition = checkPosition;
                break;
            }
            if (lookupDirection == UITextLayoutDirectionRight && CGRectGetMidX(checkRect) >= CGRectGetMidX(self.verticalMoveStartCaretRect)) {
                closestPosition = checkPosition;
                break;
            }
            // But don't skip lines.
            if (isInNextLine && CGRectGetMidY(checkRect) != CGRectGetMidY(nextLineCaretRect)) {
                break;
            }
            
            isInNextLine = YES;
            nextLineCaretRect = checkRect;
            closestPosition = checkPosition;
        }
    }
    return closestPosition;
}

- (BOOL)isNewVerticalMovementForPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction
{
    CGRect caretRect = [self caretRectForPosition:position];
    BOOL noPreviousStartPosition = CGRectEqualToRect(self.verticalMoveStartCaretRect, CGRectZero);
    BOOL caretMovedSinceLastPosition = !CGRectEqualToRect(caretRect, self.verticalMoveLastCaretRect);
    BOOL directionChanged = self.verticalMoveDirection != direction;
    
    BOOL newMovement = noPreviousStartPosition || caretMovedSinceLastPosition || directionChanged;
    return newMovement;
}

#pragma mark checklists
- (void)processChecklists {
    if (self.attributedText.length == 0) {
        return;
    }
    
    [self.textStorage addChecklistAttachmentsForColor:[self.theme colorForKey:@"noteBodyFontPreviewColor"]];
}

// Processes content of note editor, and replaces special string attachments with their plain
// text counterparts. Currently supports markdown checklists.
- (NSString *)getPlainTextContent {
    NSMutableAttributedString *adjustedString = [[NSMutableAttributedString alloc] initWithAttributedString:self.attributedText];
    // Replace checkbox images with their markdown syntax equivalent
    [adjustedString enumerateAttribute:NSAttachmentAttributeName inRange:[adjustedString.string rangeOfString:adjustedString.string] options:0 usingBlock:^(id  _Nullable value, NSRange range, BOOL * _Nonnull stop) {
        if ([value isKindOfClass:[SPTextAttachment class]]) {
            SPTextAttachment *attachment = (SPTextAttachment *)value;
            NSString *checkboxMarkdown = attachment.isChecked ? MarkdownChecked : MarkdownUnchecked;
            [adjustedString replaceCharactersInRange:range withString:checkboxMarkdown];
        }
    }];
    
    return adjustedString.string;
}

- (void)insertOrRemoveChecklist {
    NSRange lineRange = [self.text lineRangeForRange:self.selectedRange];
    NSUInteger cursorPosition = self.selectedRange.location;
    NSUInteger selectionLength = self.selectedRange.length;
    
    // Check if cursor is at a checkbox, if so we won't adjust cursor position
    BOOL cursorIsAtCheckbox = NO;
    if (self.text.length >= self.selectedRange.location + 1) {
        NSString *characterAtCursor = [self.text substringWithRange:NSMakeRange(self.selectedRange.location, 1)];
        cursorIsAtCheckbox = [characterAtCursor isEqualToString:TextAttachmentCharacterCode];
    }
    
    NSString *lineString = [self.text substringWithRange:lineRange];
    BOOL didInsertCheckbox = NO;
    NSString *resultString = @"";
    
    int addedCheckboxCount = 0;
    if ([lineString containsString:TextAttachmentCharacterCode] && [lineString length] >= ChecklistCursorAdjustment) {
        // Remove the checkboxes in the selection
        NSString *codeAndSpace = [TextAttachmentCharacterCode stringByAppendingString:@" "];
        resultString = [lineString stringByReplacingOccurrencesOfString:codeAndSpace withString:@""];
    } else {
        // Add checkboxes to the selection
        NSString *checkboxString = [MarkdownUnchecked stringByAppendingString:@" "];
        NSArray *stringLines = [lineString componentsSeparatedByString:@"\n"];
        for (int i=0; i < [stringLines count]; i++) {
            NSString *line = stringLines[i];
            // Skip the last line if it is empty
            if (i != 0 && i == [stringLines count] - 1 && [line length] == 0) {
                continue;
            }
            
            NSString *prefixedWhitespace = [self getLeadingWhiteSpaceForString:line];
            line = [line substringFromIndex:[prefixedWhitespace length]];
            resultString = [[resultString
                             stringByAppendingString:prefixedWhitespace]
                             stringByAppendingString:[checkboxString
                             stringByAppendingString:line]];
            // Skip adding newline to the last line
            if (i != [stringLines count] - 1) {
                resultString = [resultString stringByAppendingString:@"\n"];
            }
            addedCheckboxCount++;
        }

        didInsertCheckbox = YES;
    }
    
    NSTextStorage *storage = self.textStorage;
    [storage beginEditing];
    [storage replaceCharactersInRange:lineRange withString:resultString];
    [storage endEditing];
    
    // Update the cursor position
    NSUInteger cursorAdjustment = 0;
    if (!cursorIsAtCheckbox) {
        if (selectionLength > 0 && didInsertCheckbox) {
            // Places cursor at end of insertion when text was selected
            cursorAdjustment = selectionLength + (ChecklistCursorAdjustment * addedCheckboxCount);
        } else {
            cursorAdjustment = didInsertCheckbox ? ChecklistCursorAdjustment : -ChecklistCursorAdjustment;
        }
    }
    [self setSelectedRange:NSMakeRange(cursorPosition + cursorAdjustment, 0)];
    
    [self processChecklists];
    [self.delegate textViewDidChange:self];
    
    // Set the capitalization type to 'Words' temporarily so that we get a capital word next to the bullet.
    self.autocapitalizationType = UITextAutocapitalizationTypeWords;
    [self reloadInputViews];
}

// Returns a NSString of any whitespace characters found at the start of a string
- (NSString *)getLeadingWhiteSpaceForString: (NSString *)string
{
    NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:@"^\\s*" options:0 error:NULL];
    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    
    return [string substringWithRange:match.range];
}

- (void)onTextTapped:(UITapGestureRecognizer *)recognizer
{
    if (@available(iOS 11.0, *)) {
        // Location of the tap in text-container coordinates
        NSLayoutManager *layoutManager = self.layoutManager;
        CGPoint location = [recognizer locationInView:self];
        location.x -= self.textContainerInset.left;
        location.y -= self.textContainerInset.top;
    
        // Find the character that's been tapped on
        NSUInteger characterIndex;
        characterIndex = [layoutManager characterIndexForPoint:location
                                               inTextContainer:self.textContainer
                      fractionOfDistanceBetweenInsertionPoints:NULL];
        if (characterIndex < self.textStorage.length) {
            NSRange range;
            if ([self.attributedText attribute:NSAttachmentAttributeName atIndex:characterIndex effectiveRange:&range]) {
                id value = [self.attributedText attribute:NSAttachmentAttributeName atIndex:characterIndex effectiveRange:&range];
                // A checkbox was tapped!
                SPTextAttachment *attachment = (SPTextAttachment *)value;
                BOOL wasChecked = attachment.isChecked;
                [attachment setIsChecked:!wasChecked];

                if (self.selectedRange.location == self.text.length) {
                    // If the current selection is the end of the note, the keyboard has never shown,
                    // so set the selected location to the checkbox. Must happen before `textViewDidChange`.
                    self.selectedRange = NSMakeRange(characterIndex, self.selectedRange.length);
                }
                [self.delegate textViewDidChange:self];
                [self.layoutManager invalidateDisplayForCharacterRange:range];
                recognizer.cancelsTouchesInView = YES;
                
                return;
            }
        }
    }
    
    // Move the cursor to the tapped position
    [self becomeFirstResponder];
    CGPoint point = [recognizer locationInView:self];
    UITextPosition *position = [self closestPositionToPoint:point];
    UITextRange *range = [self textRangeFromPosition:position toPosition:position];
    [self setSelectedTextRange:range];
    recognizer.cancelsTouchesInView = NO;
    
    // Using a UIGestureRecognizer kills the select/all menu controller from showing if you tap
    // on the same cursor location twice, so we're controlling the menu manually.
    NSInteger startOffset = [self offsetFromPosition:self.beginningOfDocument toPosition:position];
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    if (self.lastCursorPosition == startOffset) {
        CGRect caretFrame = [self caretRectForPosition:position];
        [menuController setTargetRect:caretFrame inView:self];
        [menuController setMenuVisible:YES animated:YES];
    } else if ([menuController isMenuVisible]) {
        [menuController setMenuVisible:NO animated:YES];
    }
    
    self.lastCursorPosition = startOffset;
}

@end
