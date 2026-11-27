/* Included by ios_ui_chrome.m: UIKit-only game dialogs and transient host cards.
 * Copy borrowed game strings/rows before releasing each view lock. Answers carry
 * both dialog identity and revision so retired controls cannot answer a new step. */
#include "../core/savedlg.h"
#include "../core/commondlg.h"
#include "../ui/overlay_native.h"
#include "../ui/overlay.h"

enum { ND_NONE, ND_SAVE_LIST, ND_SAVE_QUESTION, ND_SAVE_WAIT, ND_MESSAGE, ND_IME, ND_QUIT, ND_LAYOUT, ND_PREP };
#define ND_NO_BACK (-999)
typedef struct {
    int kind, seq, percent, back, focus;
    NSString *title, *body, *initial;
    NSArray *labels;
    NSData *rows;
    ImeDlgView ime;
} NDRequest;
static UIView *nd_dim, *nd_card, *nd_corner;
static UINavigationBar *nd_nav;
static UITextView *nd_body, *nd_text;
static UITextField *nd_field;
static UILabel *nd_count, *nd_remember_label, *nd_corner_label;
static UITableView *nd_table;
static UIStackView *nd_actions;
static UIProgressView *nd_progress, *nd_corner_progress;
static UIActivityIndicatorView *nd_spinner;
static UISwitch *nd_remember;
static UIButton *nd_buttons[3];
static NSData *nd_rows;
static NSString *nd_draft;
static int nd_draft_seq = -1;
static ImeDlgView nd_ime;
static int nd_kind, nd_seq, nd_selected, nd_back, nd_answered, nd_button_count;
static NSUInteger nd_presentation;
static int nd_axis_direction[2];
static CGFloat nd_keyboard_top = CGFLOAT_MAX;
static int nd_active(void) { return nd_kind && !nd_answered; }
static int nd_text_active(void) { return nd_active() && nd_kind == ND_IME; }
static NSString *nd_string(const char *s) { return s ? ([NSString stringWithUTF8String:s] ?: @"") : @""; }
static void nd_layout(void);
static void nd_answer(int kind, int seq, int choice);
static const SaveDlgRow *nd_save_row(NSInteger index) {
    return index >= 0 && index < (NSInteger)(nd_rows.length / sizeof(SaveDlgRow)) ? &((const SaveDlgRow *)nd_rows.bytes)[index] : NULL;
}
static NSString *nd_save_summary(const SaveDlgRow *row) {
    if (!row->exists) return @"Create a new save";
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *part in @[nd_string(row->sub), nd_string(row->detail), nd_string(row->date)]) {
        NSString *clean = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (clean.length && ![parts containsObject:clean]) [parts addObject:clean];
    }
    return [parts componentsJoinedByString:@" · "];
}

/* NSString.length is UTF-16 units, matching SceImeDialog's maxTextLength. */
static BOOL nd_valid_text(NSString *text) {
    if (text.length > nd_ime.maxlen) return NO;
    if (nd_ime.type == 1 || nd_ime.type == 2) {
        for (NSUInteger i = 0; i < text.length; i++) {
            const unichar c = [text characterAtIndex:i];
            if (nd_ime.type == 1 && c >= 128) return NO;
            if (nd_ime.type == 2 && !((c >= '0' && c <= '9') || c == '.' || c == ',' || c == '+' || c == '-')) return NO;
        }
    }
    return YES;
}
static NSString *nd_current_text(void) { return nd_ime.multiline ? nd_text.text : nd_field.text; }
static void nd_count_update(void) {
    nd_count.text = [NSString stringWithFormat:@"%lu / %u", (unsigned long)nd_current_text().length, nd_ime.maxlen];
    const BOOL valid = nd_valid_text(nd_current_text());
    nd_count.textColor = valid ? [UIColor secondaryLabelColor] : [UIColor systemRedColor];
    nd_buttons[0].enabled = valid;
}
static void nd_store_draft(void) {
    if (nd_kind != ND_IME || nd_answered) return;
    [nd_draft release]; nd_draft = [nd_current_text() copy]; nd_draft_seq = nd_seq;
}
static void nd_clear_draft(void) { [nd_draft release]; nd_draft = nil; nd_draft_seq = -1; }

@interface NativeDialogCenter : NSObject <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UITextViewDelegate>
- (void)back;
- (void)keyboard:(NSNotification *)notification;
- (void)textChanged:(id)sender;
@end
static NativeDialogCenter *nd_center;
@implementation NativeDialogCenter
- (void)back { if (nd_active() && nd_back != ND_NO_BACK) nd_answer(nd_kind, nd_seq, nd_back); }
- (void)keyboard:(NSNotification *)notification {
    if ([notification.name isEqualToString:UIKeyboardWillHideNotification]) nd_keyboard_top = CGFLOAT_MAX;
    else {
        CGRect rect = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        rect = [g_host convertRect:rect fromCoordinateSpace:g_win.screen.coordinateSpace];
        const CGRect overlap = CGRectIntersection(g_host.bounds, rect);
        nd_keyboard_top = CGRectIsNull(overlap) || overlap.size.height < 1 ? CGFLOAT_MAX : CGRectGetMinY(overlap);
    }
    nd_layout();
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {
    (void)table; return nd_rows.length / sizeof(SaveDlgRow);
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; return nd_save_row(section) ? 1 : 0;
}
- (CGFloat)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)path {
    (void)table; (void)path; return UITableViewAutomaticDimension;
}
- (CGFloat)tableView:(UITableView *)table heightForHeaderInSection:(NSInteger)section {
    (void)table; (void)section; return 10;
}
- (CGFloat)tableView:(UITableView *)table heightForFooterInSection:(NSInteger)section {
    (void)table; (void)section; return CGFLOAT_MIN;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"save"];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"save"] autorelease];
    const SaveDlgRow *row = nd_save_row(path.section);
    if (!row) return cell;
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = row->exists ? (nd_string(row->title).length ? nd_string(row->title) : @"Saved Game") : @"New Save";
    content.secondaryText = nd_save_summary(row);
    content.image = [UIImage systemImageNamed:row->exists ? @"doc.text" : @"plus.rectangle.on.folder"];
    content.imageProperties.tintColor = [UIColor systemBlueColor];
    content.textProperties.numberOfLines = 2; content.secondaryTextProperties.numberOfLines = 3;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    content.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    content.secondaryTextProperties.color = [UIColor secondaryLabelColor];
    cell.contentConfiguration = content; cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.accessoryType = path.section == nd_selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = [UIColor systemBlueColor];
    cell.accessibilityTraits = UIAccessibilityTraitButton | (path.section == nd_selected ? UIAccessibilityTraitSelected : 0);
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (!nd_active() || nd_kind != ND_SAVE_LIST || !nd_save_row(path.section)) return;
    nd_selected = (int)path.section;
    [table reloadData]; /* selecting a card does not immediately overwrite or load it */
    nd_buttons[0].enabled = YES;
    ios_ui_haptic(0);
}
- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)replacement {
    if (field.markedTextRange) return YES;
    return nd_valid_text([field.text stringByReplacingCharactersInRange:range withString:replacement]);
}
- (BOOL)textView:(UITextView *)view shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)replacement {
    if (view.markedTextRange) return YES;
    return nd_valid_text([view.text stringByReplacingCharactersInRange:range withString:replacement]);
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { (void)field; nd_answer(nd_kind, nd_seq, 0); return NO; }
- (void)textViewDidChange:(UITextView *)view { (void)view; nd_count_update(); }
- (void)textChanged:(id)sender { (void)sender; nd_count_update(); }
@end

static void nd_hide(void) {
    nd_store_draft();
    [nd_card endEditing:YES]; nd_card.userInteractionEnabled = NO;
    [nd_rows release]; nd_rows = nil;
    nd_kind = ND_NONE; nd_seq = -1; nd_answered = 0;
    const NSUInteger presentation = ++nd_presentation;
    [UIView animateWithDuration:chrome_duration(0.16) delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
        nd_dim.alpha = nd_card.alpha = 0;
    } completion:^(BOOL finished) {
        (void)finished;
        if (presentation == nd_presentation) nd_dim.hidden = nd_card.hidden = YES;
    }];
}
static void nd_answer(int kind, int seq, int choice) {
    if (kind != nd_kind || seq != nd_seq || nd_answered) return;
    if (kind == ND_SAVE_LIST && choice != SAVEDLG_CANCEL) {
        choice = nd_selected;
        if (!nd_save_row(choice)) return;
    }
    if (kind == ND_IME && choice == 0 && (!nd_valid_text(nd_current_text()) || (nd_ime.multiline ? nd_text.markedTextRange : nd_field.markedTextRange))) return;
    nd_answered = 1;
    if (kind == ND_SAVE_LIST) savedlg_answer(seq, choice);
    else if (kind == ND_SAVE_QUESTION) savedlg_answer(seq, choice < 0 ? SAVEDLG_CANCEL : choice == 0 ? SAVEDLG_YES : SAVEDLG_NO);
    else if (kind == ND_MESSAGE) msgdlg_answer(seq, choice);
    else if (kind == ND_IME) imedlg_answer(seq, choice == 0, choice == 0 ? nd_current_text().UTF8String : "");
    else if (kind == ND_QUIT) overlay_native_answer(NATIVE_CARD_QUIT, seq, choice, 0);
    else if (kind == ND_LAYOUT) overlay_native_answer(NATIVE_CARD_LAYOUT, seq, choice < 0 ? 1 : choice + 1, choice < 0 ? 0 : nd_remember.on);
    else if (kind == ND_PREP) overlay_native_answer(NATIVE_CARD_PREP, seq, 0, 0);
    if (kind == ND_IME) nd_clear_draft();
    [nd_card endEditing:YES]; nd_card.userInteractionEnabled = NO;
}
static void nd_make(void) {
    if (nd_dim) return;
    nd_center = [[NativeDialogCenter alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:nd_center selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:nd_center selector:@selector(keyboard:) name:UIKeyboardWillHideNotification object:nil];
    nd_dim = [[UIView alloc] initWithFrame:g_host.bounds];
    nd_dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];
    nd_dim.hidden = YES; nd_dim.alpha = 0;
    [g_host addSubview:nd_dim]; [nd_dim release];
    nd_card = [[UIView alloc] initWithFrame:CGRectZero];
    nd_card.layer.cornerRadius = 28; nd_card.clipsToBounds = YES; nd_card.hidden = YES; nd_card.alpha = 0;
    nd_card.accessibilityViewIsModal = YES;
    blur_fill(nd_card, UIBlurEffectStyleSystemMaterialDark);
    [g_host addSubview:nd_card]; [nd_card release];
    nd_nav = [[UINavigationBar alloc] init]; nd_nav.barStyle = UIBarStyleBlack; nd_nav.tintColor = [UIColor systemBlueColor];
    UINavigationBarAppearance *appearance = [[[UINavigationBarAppearance alloc] init] autorelease];
    [appearance configureWithTransparentBackground];
    nd_nav.standardAppearance = nd_nav.scrollEdgeAppearance = appearance;
    [nd_card addSubview:nd_nav]; [nd_nav release];
    nd_body = [[UITextView alloc] init]; nd_body.editable = NO; nd_body.backgroundColor = [UIColor clearColor];
    nd_body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; nd_body.adjustsFontForContentSizeCategory = YES;
    nd_body.selectable = NO; nd_body.textColor = [UIColor secondaryLabelColor]; nd_body.textContainerInset = UIEdgeInsetsZero;
    [nd_card addSubview:nd_body]; [nd_body release];
    nd_table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    nd_table.dataSource = nd_center; nd_table.delegate = nd_center; nd_table.backgroundColor = [UIColor clearColor];
    nd_table.estimatedRowHeight = 100;
    nd_table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [nd_card addSubview:nd_table]; [nd_table release];
    nd_field = [[UITextField alloc] init]; nd_field.borderStyle = UITextBorderStyleRoundedRect; nd_field.delegate = nd_center;
    nd_field.textColor = [UIColor labelColor]; nd_field.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    nd_field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; nd_field.adjustsFontForContentSizeCategory = YES;
    nd_field.autocorrectionType = UITextAutocorrectionTypeNo; nd_field.returnKeyType = UIReturnKeyDone;
    [nd_field addTarget:nd_center action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
    [nd_card addSubview:nd_field]; [nd_field release];
    nd_text = [[UITextView alloc] init]; nd_text.delegate = nd_center; nd_text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    nd_text.adjustsFontForContentSizeCategory = YES; nd_text.layer.cornerRadius = 12;
    nd_text.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor]; nd_text.textColor = [UIColor labelColor]; nd_text.autocorrectionType = UITextAutocorrectionTypeNo;
    [nd_card addSubview:nd_text]; [nd_text release];
    nd_count = [[UILabel alloc] init]; nd_count.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular]; nd_count.textColor = [UIColor secondaryLabelColor];
    [nd_card addSubview:nd_count]; [nd_count release];
    nd_progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault]; nd_progress.progressTintColor = [UIColor systemBlueColor];
    [nd_card addSubview:nd_progress]; [nd_progress release];
    nd_spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [nd_card addSubview:nd_spinner]; [nd_spinner release];
    nd_remember = [[UISwitch alloc] init]; nd_remember.onTintColor = [UIColor systemBlueColor];
    [nd_card addSubview:nd_remember]; [nd_remember release];
    nd_remember_label = [[UILabel alloc] init]; nd_remember_label.text = @"Remember this choice"; nd_remember_label.font = [UIFont systemFontOfSize:14]; nd_remember_label.textColor = [UIColor labelColor];
    [nd_card addSubview:nd_remember_label]; [nd_remember_label release];
    nd_actions = [[UIStackView alloc] init]; nd_actions.axis = UILayoutConstraintAxisHorizontal; nd_actions.distribution = UIStackViewDistributionFillEqually; nd_actions.spacing = 8;
    [nd_card addSubview:nd_actions]; [nd_actions release];
}
static void nd_layout(void) {
    if (!nd_card || !nd_kind) return;
    CGRect safe = CGRectInset(chrome_safe_rect(), 16, 16);
    if (nd_text_active() && nd_keyboard_top < CGRectGetMaxY(safe))
        safe.size.height = fmax(96, nd_keyboard_top - safe.origin.y - 12);
    const CGFloat width = fmin(nd_kind == ND_SAVE_LIST ? 600 : nd_kind == ND_IME ? 560 : 460, safe.size.width);
    const BOOL vertical = nd_button_count > 2 || (nd_button_count > 1 && UIContentSizeCategoryIsAccessibilityCategory(g_host.traitCollection.preferredContentSizeCategory));
    const CGFloat buttonHeight = fmax(48, [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline].lineHeight + 22);
    const CGFloat actionHeight = nd_button_count ? (vertical ? nd_button_count * buttonHeight + (nd_button_count - 1) * 8 : buttonHeight) : 0;
    const CGFloat footer = actionHeight ? actionHeight + 32 : 20;
    const CGFloat heading = 52;
    const CGFloat text = text_height(nd_body.text, width - 48, nd_body.font);
    const CGFloat intro = nd_kind == ND_SAVE_LIST ? fmin(60, fmax(28, text)) : 0;
    const NSInteger slots = nd_rows.length / sizeof(SaveDlgRow);
    CGFloat content;
    if (nd_kind == ND_SAVE_LIST) content = intro + fmax(84, slots * 108);
    else if (nd_kind == ND_IME) content = nd_ime.multiline ? 160 : 80;
    else content = fmax(40, text) + (nd_kind == ND_LAYOUT ? 52 : 0) + (!nd_progress.hidden || nd_spinner.isAnimating ? 28 : 0);
    const CGFloat height = fmin(safe.size.height, fmax(176, heading + content + footer + 20));
    nd_dim.frame = g_host.bounds;
    nd_card.frame = CGRectMake(CGRectGetMidX(safe) - width/2, CGRectGetMidY(safe) - height/2, width, height);
    nd_nav.frame = CGRectMake(8,4,width-16,44);
    nd_actions.axis = vertical ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    nd_actions.frame = CGRectMake(20,height-actionHeight-16,width-40,actionHeight);
    const CGFloat bottom = height - footer;
    nd_body.textAlignment = nd_kind == ND_SAVE_LIST ? NSTextAlignmentNatural : NSTextAlignmentCenter;
    nd_body.frame = CGRectMake(24,heading,width-48,fmax(20,bottom-heading-(nd_kind == ND_LAYOUT ? 52 : 0)-(!nd_progress.hidden || nd_spinner.isAnimating ? 24 : 0)));
    if (nd_kind == ND_SAVE_LIST) {
        nd_body.frame = CGRectMake(24,heading,width-48,slots ? intro : fmax(40,bottom-heading));
        nd_table.frame = CGRectMake(0,heading+intro,width,fmax(0,bottom-heading-intro));
    }
    nd_progress.frame = CGRectMake(24,bottom-10,width-48,4);
    nd_spinner.frame = CGRectMake(width/2-12,bottom-28,24,24);
    nd_remember.frame = CGRectMake(width-75,bottom-44,51,31);
    nd_remember_label.frame = CGRectMake(24,bottom-44,width-112,31);
    if (nd_text_active()) {
        const BOOL compact = height < 190;
        nd_count.hidden = compact;
        nd_field.frame = CGRectMake(20,heading,width-40,compact ? 34 : 46);
        nd_text.frame = CGRectMake(20,heading,width-40,fmax(32,bottom-heading-(compact ? 0 : 28)));
        nd_count.frame = CGRectMake(24,bottom-22,width-48,18);
    }
}
static void nd_build(NDRequest r) {
    nd_store_draft();
    nd_make(); [nd_card endEditing:YES];
    cfg_picker_dismiss(); bar_up_close_all(); touchpad_cancel_all(); ios_ui_chrome_cancel_controls();
    nd_kind = r.kind; nd_seq = r.seq; nd_answered = 0; nd_back = r.back; nd_ime = r.ime;
    nd_selected = r.focus; nd_button_count = (int)r.labels.count;
    memset(nd_axis_direction,0,sizeof nd_axis_direction);
    [r.rows retain]; [nd_rows release]; nd_rows = r.rows;
    UINavigationItem *item = [[[UINavigationItem alloc] initWithTitle:r.title] autorelease];
    if (r.back != ND_NO_BACK) item.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:nd_center action:@selector(back)] autorelease];
    [nd_nav setItems:@[item] animated:NO];
    for (UIView *v in nd_actions.arrangedSubviews) { [nd_actions removeArrangedSubview:v]; [v removeFromSuperview]; }
    memset(nd_buttons,0,sizeof nd_buttons);
    for (NSUInteger i=0;i<r.labels.count && i<3;i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.configuration = chrome_button_style(r.labels[i], i == 0, r.kind == ND_QUIT && i == 1);
        button.titleLabel.adjustsFontForContentSizeCategory = YES;
        const int index=(int)i, kind=r.kind, seq=r.seq;
        control_on(button,UIControlEventTouchUpInside,^{ nd_answer(kind,seq,index); });
        [nd_actions addArrangedSubview:button]; nd_buttons[i]=button;
    }
    nd_body.text = r.body ?: @"";
    nd_progress.hidden = r.percent < 0;
    nd_progress.progress = fmaxf(0,fminf(1,r.percent/100.0f));
    [nd_spinner stopAnimating];
    nd_table.hidden = r.kind != ND_SAVE_LIST; nd_body.hidden = r.kind == ND_SAVE_LIST || r.kind == ND_IME;
    nd_field.hidden = r.kind != ND_IME || r.ime.multiline; nd_text.hidden = r.kind != ND_IME || !r.ime.multiline;
    nd_count.hidden = r.kind != ND_IME; nd_remember.hidden = nd_remember_label.hidden = r.kind != ND_LAYOUT;
    nd_remember.on = NO;
    if (r.kind == ND_IME) {
        UIKeyboardType type = r.ime.type == 1 ? UIKeyboardTypeASCIICapable : (r.ime.type == 2 || r.ime.type == 3) ? UIKeyboardTypeNumbersAndPunctuation : r.ime.type == 4 ? UIKeyboardTypeURL : r.ime.type == 5 ? UIKeyboardTypeEmailAddress : UIKeyboardTypeDefault;
        nd_field.keyboardType = nd_text.keyboardType = type;
        nd_field.secureTextEntry = nd_text.secureTextEntry = r.ime.password != 0;
        if (nd_draft_seq != r.seq) { nd_clear_draft(); nd_draft = [r.initial copy]; nd_draft_seq = r.seq; }
        nd_field.text = nd_text.text = nd_draft ?: @""; nd_count_update();
        const int seq = r.seq;
        dispatch_async(dispatch_get_main_queue(), ^{ if (nd_kind == ND_IME && nd_seq == seq && !nd_answered) [(nd_ime.multiline ? (UIView *)nd_text : (UIView *)nd_field) becomeFirstResponder]; });
    }
    nd_layout(); [nd_table reloadData];
    const NSInteger count = nd_rows.length/sizeof(SaveDlgRow);
    if (r.kind == ND_SAVE_LIST && count) {
        nd_selected = (int)fmax(0,fmin(nd_selected,count-1));
        NSIndexPath *path = [NSIndexPath indexPathForRow:0 inSection:nd_selected];
        [nd_table selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionMiddle];
    }
    if (r.kind == ND_SAVE_LIST) nd_buttons[0].enabled = count > 0;
    [g_host bringSubviewToFront:nd_dim]; [g_host bringSubviewToFront:nd_card];
    ++nd_presentation; nd_card.userInteractionEnabled = YES;
    nd_dim.hidden = nd_card.hidden = NO;
    [UIView animateWithDuration:chrome_duration(0.22) delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        nd_dim.alpha = nd_card.alpha = 1;
        nd_layout();
    } completion:nil];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nd_nav);
}
static NDRequest nd_request(NativeOverlayState host) {
    NDRequest r = {0}; r.percent=-1; r.back=ND_NO_BACK;
    if (host.kind) {
        r.seq=host.seq;
        if (host.kind == NATIVE_CARD_QUIT) { r.kind=ND_QUIT; r.title=@"Quit game?"; r.body=@"Progress since your last save will be lost."; r.labels=@[@"Keep playing",@"Quit game"]; r.back=0; }
        else if (host.kind == NATIVE_CARD_LAYOUT) { r.kind=ND_LAYOUT; r.title=@"Controller layout"; r.body=@"Standard keeps the handheld touch controls. PS TV uses the game's controller-only layout. This choice applies until you quit."; r.labels=@[@"Standard",@"PS TV"]; r.back=-1; }
        else { r.kind=ND_PREP; r.title=@"Preparing shaders"; r.body=[NSString stringWithFormat:@"Building shaders for this phone.\n%d of %d ready.\nYou can skip and let preparation continue while you play.",host.done,host.total]; r.labels=@[@"Skip"]; r.back=0; r.percent=host.total ? (int)(100.0*host.done/host.total) : 0; }
        return r;
    }
    if (overlay_is_open()) return r; /* full settings owns the screen until Done */
    ImeDlgView ime; int kind=imedlg_view(&ime);
    if (kind) { r.kind=ND_IME; r.seq=ime.seq; r.ime=ime; r.ime.text=NULL; r.title=nd_string(ime.title); r.initial=nd_string(ime.text); r.labels=@[ime.enter_label[0] ? nd_string(ime.enter_label) : @"Done"]; r.back=1; }
    imedlg_release(); if (r.kind) return r;
    MsgDlgView msg; kind=msgdlg_view(&msg); msgdlg_release();
    if (kind) {
        r.kind=ND_MESSAGE; r.seq=msg.seq; r.title=@"Message"; r.body=nd_string(msg.msg); r.percent=msg.percent; r.back=msg.back>=0 ? msg.back : ND_NO_BACK; r.ime.enter_circle=msg.enter_circle;
        NSMutableArray *labels=[NSMutableArray array]; for(int i=0;i<msg.nbuttons && i<3;i++) [labels addObject:nd_string(msg.label[i])]; r.labels=labels;
        return r;
    }
    SaveDlgView save; kind=savedlg_view(&save);
    if (kind) {
        r.kind=kind==SAVEDLG_LIST ? ND_SAVE_LIST : kind==SAVEDLG_YESNO ? ND_SAVE_QUESTION : ND_SAVE_WAIT;
        r.seq=save.seq; r.title=save.disp==1 ? @"Save Game" : save.disp==2 ? @"Load Game" : save.disp==3 ? @"Delete Save" : save.title[0] ? nd_string(save.title) : @"Saved Games";
        r.body=nd_string(save.msg); r.percent=save.percent;
        if (kind==SAVEDLG_LIST) {
            r.focus=save.focus; r.back=SAVEDLG_CANCEL;
            r.rows=nd_kind==r.kind && nd_seq==r.seq ? nd_rows : [NSData dataWithBytes:save.rows length:(NSUInteger)save.nrows*sizeof(SaveDlgRow)];
            r.labels=@[save.disp==1 ? @"Save" : save.disp==3 ? @"Delete" : @"Load"];
            if (!r.body.length) r.body=save.nrows ? @"Choose a save to continue." : @"No saved games yet.";
        }
        if (kind==SAVEDLG_YESNO) { r.labels=@[@"Yes",@"No"]; r.back=SAVEDLG_CANCEL; }
    }
    savedlg_release(); return r;
}
static void nd_tick(void) {
    static double last;
    if (chrome_now()-last < 0.05) { nd_layout(); return; } last=chrome_now();
    NativeOverlayState host; overlay_native_state(&host);
    NDRequest r=nd_request(host);
    if (!r.kind) { if(nd_kind) nd_hide(); if (!overlay_is_open()) nd_clear_draft(); }
    else if (r.kind!=nd_kind || r.seq!=nd_seq) nd_build(r);
    if (r.kind && !nd_answered) {
        if (![nd_body.text isEqualToString:r.body ?: @""]) nd_body.text=r.body ?: @"";
        nd_progress.hidden=r.percent<0; nd_progress.progress=fmaxf(0,fminf(1,r.percent/100.0f));
        const BOOL wait=(r.kind==ND_SAVE_WAIT || r.kind==ND_MESSAGE) && !r.labels.count && r.percent<0;
        if(wait) [nd_spinner startAnimating]; else [nd_spinner stopAnimating];
        nd_layout(); [g_host bringSubviewToFront:nd_dim]; [g_host bringSubviewToFront:nd_card];
    }
    if (host.prep_state==2 && host.total>0 && !r.kind && !overlay_is_open()) {
        if(!nd_corner) {
            nd_corner=[[UIView alloc] init]; nd_corner.backgroundColor=rgba(0,0,0,0.7); nd_corner.layer.cornerRadius=8; nd_corner.userInteractionEnabled=NO;
            nd_corner_label=[[UILabel alloc] init]; nd_corner_label.font=[UIFont systemFontOfSize:11]; nd_corner_label.textColor=[UIColor whiteColor];
            [nd_corner addSubview:nd_corner_label]; [nd_corner_label release];
            nd_corner_progress=[[UIProgressView alloc] init]; nd_corner_progress.progressTintColor=rgba(240,192,96,1);
            [nd_corner addSubview:nd_corner_progress]; [nd_corner_progress release]; [g_host addSubview:nd_corner]; [nd_corner release];
        }
        CGRect safe=chrome_safe_rect(); nd_corner.frame=CGRectMake(CGRectGetMaxX(safe)-210,CGRectGetMaxY(safe)-42,202,34);
        nd_corner_label.frame=CGRectMake(8,4,186,18); nd_corner_label.text=[NSString stringWithFormat:@"Preparing shaders: %d / %d",host.done,host.total];
        nd_corner_progress.frame=CGRectMake(8,26,186,3); nd_corner_progress.progress=(float)host.done/host.total; nd_corner.hidden=NO;
    } else nd_corner.hidden=YES;
}

static int nd_handle_event(const SDL_Event *event) {
    if (!nd_active()) return 0;
    if (nd_kind==ND_LAYOUT && ((event->type==SDL_EVENT_GAMEPAD_BUTTON_DOWN && event->gbutton.button==SDL_GAMEPAD_BUTTON_WEST) ||
        (event->type==SDL_EVENT_KEY_DOWN && !event->key.repeat && event->key.key==SDLK_R))) {
        [nd_remember setOn:!nd_remember.on animated:YES]; return 1;
    }
    int move=0, confirm=0, back=0;
    if(event->type==SDL_EVENT_KEY_DOWN && !event->key.repeat) {
        const SDL_Keycode k=event->key.key;
        /* Hardware arrow keys belong to UIKit's text selection while editing. */
        if (nd_kind!=ND_IME) move=k==SDLK_UP || k==SDLK_LEFT ? -1 : k==SDLK_DOWN || k==SDLK_RIGHT ? 1 : 0;
        confirm=(k==SDLK_RETURN && !(nd_kind==ND_IME && nd_ime.multiline)) || (k==SDLK_SPACE && nd_kind!=ND_IME); back=k==SDLK_ESCAPE;
    } else if(event->type==SDL_EVENT_GAMEPAD_BUTTON_DOWN) {
        const int b=event->gbutton.button;
        move=b==SDL_GAMEPAD_BUTTON_DPAD_UP || b==SDL_GAMEPAD_BUTTON_DPAD_LEFT ? -1 : b==SDL_GAMEPAD_BUTTON_DPAD_DOWN || b==SDL_GAMEPAD_BUTTON_DPAD_RIGHT ? 1 : 0;
        confirm=b==SDL_GAMEPAD_BUTTON_SOUTH; back=b==SDL_GAMEPAD_BUTTON_EAST;
        if((nd_kind==ND_IME || nd_kind==ND_MESSAGE) && nd_ime.enter_circle) { int x=confirm; confirm=back; back=x; }
    } else if(event->type==SDL_EVENT_GAMEPAD_AXIS_MOTION && (event->gaxis.axis==SDL_GAMEPAD_AXIS_LEFTX || event->gaxis.axis==SDL_GAMEPAD_AXIS_LEFTY)) {
        const int axis=event->gaxis.axis==SDL_GAMEPAD_AXIS_LEFTY;
        const int next=event->gaxis.value>16000 ? 1 : event->gaxis.value<-16000 ? -1 : 0;
        if(next && next!=nd_axis_direction[axis]) move=next;
        nd_axis_direction[axis]=next;
    }
    if(move) {
        const int count=nd_kind==ND_SAVE_LIST ? (int)(nd_rows.length/sizeof(SaveDlgRow)) : nd_button_count;
        nd_selected=(int)fmax(0,fmin(count-1,nd_selected+move));
        if(nd_kind==ND_SAVE_LIST && count) {
            [nd_table reloadData];
            [nd_table selectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:nd_selected] animated:YES scrollPosition:UITableViewScrollPositionMiddle];
        } else for(int i=0;i<nd_button_count && i<3;i++) {
            nd_buttons[i].layer.borderWidth = i==nd_selected ? 2 : 0;
            nd_buttons[i].layer.borderColor = [UIColor systemBlueColor].CGColor;
            nd_buttons[i].layer.cornerRadius = 24;
        }
    }
    if(back && nd_back!=ND_NO_BACK) nd_answer(nd_kind,nd_seq,nd_back);
    else if(confirm && (nd_kind==ND_SAVE_LIST ? nd_rows.length>0 : nd_button_count>0)) nd_answer(nd_kind,nd_seq,nd_selected);
    return move || confirm || back;
}

/* Touch/cursor marks are CAShapeLayers in UIKit's pass-through host. */
void ios_ui_chrome_marks(const void *data, int count, const float rear[4]) {
    static UIView *host;
    static CAShapeLayer *pictures[65];
    if(!g_installed || ![NSThread isMainThread]) return;
    if(!host) { host=[[UIView alloc] initWithFrame:g_host.bounds]; host.userInteractionEnabled=NO; host.opaque=NO; [g_host insertSubview:host atIndex:1]; [host release]; }
    host.frame=g_host.bounds; host.hidden=overlay_is_open() || nd_active();
    const OverlayMark *marks=data;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for(int i=0;i<65;i++) {
        const BOOL rect=i==64;
        const BOOL show=rect ? rear && rear[2]>0 : i<count && i<64;
        if(!show) { pictures[i].hidden=YES; continue; }
        if(!pictures[i]) { pictures[i]=[CAShapeLayer layer]; [host.layer addSublayer:pictures[i]]; }
        UIBezierPath *path; UIColor *color;
        if(rect) { path=[UIBezierPath bezierPathWithRect:CGRectMake(rear[0],rear[1],rear[2],rear[3])]; color=rgba(255,170,60,0.6); }
        else {
            const OverlayMark m=marks[i]; const CGFloat radius=m.cursor ? 14 : 10;
            path=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(m.x-radius,m.y-radius,2*radius,2*radius)];
            if(m.cursor) { [path moveToPoint:CGPointMake(m.x-radius-4,m.y)]; [path addLineToPoint:CGPointMake(m.x+radius+4,m.y)]; [path moveToPoint:CGPointMake(m.x,m.y-radius-4)]; [path addLineToPoint:CGPointMake(m.x,m.y+radius+4)]; }
            color=m.rear ? rgba(255,170,60,0.9) : rgba(80,200,255,0.9);
            pictures[i].fillColor=m.pressed ? rgba(0,0,0,0.47).CGColor : [UIColor clearColor].CGColor;
        }
        pictures[i].path=path.CGPath; pictures[i].strokeColor=color.CGColor; pictures[i].lineWidth=2; pictures[i].hidden=NO;
        if(rect) pictures[i].fillColor=[UIColor clearColor].CGColor;
    }
    [CATransaction commit];
}
