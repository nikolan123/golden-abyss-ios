/* A direct button action presents this native popover; activation does not rely
 * on a context-menu gesture being recognized inside SDL's event pump. */
static BOOL chrome_menu_open;
static BOOL chrome_menu_closing;
static UIViewController *chrome_menu_controller;
static void (^chrome_menu_pending)(void);
void ios_ui_settings_open(int tab);
static void bar_up_close_all(void);

static void chrome_menu_run_pending(void) {
    void (^pending)(void) = chrome_menu_pending;
    chrome_menu_pending = nil;
    if (pending) { pending(); [pending release]; }
}
static void chrome_menu_finish(UIViewController *controller) {
    if (controller != chrome_menu_controller) return;
    chrome_menu_controller = nil; chrome_menu_open = chrome_menu_closing = NO;
    [controller release];
    chrome_menu_run_pending();
}
static void chrome_menu_after_close(void (^action)(void)) {
    [chrome_menu_pending release]; chrome_menu_pending = [action copy];
    if (!chrome_menu_open) dispatch_async(dispatch_get_main_queue(), ^{ chrome_menu_run_pending(); });
}
static UIAction *chrome_menu_action(NSString *title, NSString *symbol, BOOL selected, BOOL destructive, void (^run)(void)) {
    UIAction *action = [UIAction actionWithTitle:title image:symbol ? [UIImage systemImageNamed:symbol] : nil identifier:nil handler:^(UIAction *sender) {
        (void)sender; ios_ui_haptic(0); run();
    }];
    action.state = selected ? UIMenuElementStateOn : UIMenuElementStateOff;
    if (destructive) action.attributes = UIMenuElementAttributesDestructive;
    return action;
}
static UIAction *chrome_menu_settings(NSString *title, NSString *symbol, int page) {
    return chrome_menu_action(title, symbol, NO, NO, ^{
        chrome_menu_after_close(^{ ios_ui_settings_open(page); });
    });
}
static UIMenu *chrome_menu_group(NSString *title, NSString *symbol, NSArray *items) {
    return [UIMenu menuWithTitle:title image:symbol ? [UIImage systemImageNamed:symbol] : nil identifier:nil options:0 children:items];
}
static UIMenu *chrome_quick_menu(void) {
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:chrome_menu_action(overlay_game_paused() ? @"Resume Game" : @"Pause Game", overlay_game_paused() ? @"play.fill" : @"pause.fill", NO, NO, ^{
        overlay_set_paused(!overlay_game_paused());
    })];
    [items addObject:chrome_menu_settings(@"Settings", @"gearshape", -1)];
    if (overlay_frame_rate_offered()) {
        NSMutableArray *rates = [NSMutableArray array];
        for (int i = 0; i < 2; i++) {
            const int rate = i ? 60 : 30;
            [rates addObject:chrome_menu_action(i ? @"60 fps · Experimental" : @"30 fps", nil, overlay_frame_rate_wanted() == rate, NO, ^{ overlay_frame_rate_request(rate); })];
        }
        [items addObject:chrome_menu_group(@"Frame Rate", @"speedometer", rates)];
    }
    NSMutableArray *display = [NSMutableArray array], *stats = [NSMutableArray array], *resolution = [NSMutableArray array];
    NSArray *levels = @[@"Off", @"Frame Rate", @"Detailed"];
    for (int i = 0; i < 3; i++) {
        const int level = i;
        [stats addObject:chrome_menu_action(levels[i], nil, overlay_stats_level() == i, NO, ^{ overlay_set_stats(level); })];
    }
    [display addObject:chrome_menu_group(@"On-Screen Stats", @"chart.bar", stats)];
    for (int i = 1; i <= MIN(3, gfx_gpu_render_scale_max()); i++) {
        const int scale = i;
        [resolution addObject:chrome_menu_action([NSString stringWithFormat:@"%d× Resolution", i], nil, gfx_gpu_render_scale_wanted() == i, NO, ^{ gfx_gpu_render_scale_request(scale); })];
    }
    [display addObject:chrome_menu_group(@"Resolution", @"rectangle.expand.vertical", resolution)];
    [display addObject:chrome_menu_action(@"Metal HUD", @"gauge.with.dots.needle.67percent", settings_int("metal_hud", 1), NO, ^{
        settings_set_int("metal_hud", !settings_int("metal_hud", 1)); settings_save();
        overlay_toast_titled("Metal HUD", "Restart the app to apply this change.", 3);
    })];
    [display addObject:chrome_menu_settings(@"Display Settings", @"slider.horizontal.3", 0)];
    [items addObject:chrome_menu_group(@"Display", @"display", display)];
    NSMutableArray *controls = [NSMutableArray array];
    [controls addObject:chrome_menu_action(@"On-Screen Controls", @"gamecontroller", touchpad_on(), NO, ^{ touchpad_set_on(!touchpad_on()); })];
    const char *look = getenv("RECOMP_TOUCH_LOOK");
    if (look && *look) {
        const BOOL on = settings_int("touch_look", *look != '0');
        [controls addObject:chrome_menu_action(@"Touch Look", @"hand.draw", on, NO, ^{ settings_set_int("touch_look", !on); settings_save(); })];
    }
    [controls addObject:chrome_menu_action(@"Left-Handed", @"hand.point.left", touchpad_mirror(), NO, ^{ touchpad_set_mirror(!touchpad_mirror()); })];
    [controls addObject:chrome_menu_settings(@"Control Settings", @"slider.horizontal.3", 3)];
    [items addObject:chrome_menu_group(@"Controls", @"gamecontroller", controls)];
    [items addObject:chrome_menu_settings(@"Game & Audio", @"speaker.wave.2", 2)];
    [items addObject:chrome_menu_action(@"Quit Game", @"rectangle.portrait.and.arrow.right", NO, YES, ^{
        chrome_menu_after_close(^{ overlay_quit_confirm(); });
    })];
    return chrome_menu_group(@"", nil, items);
}

@interface ChromeQuickController : UITableViewController <UIPopoverPresentationControllerDelegate> {
    UIMenu *entries;
}
- (instancetype)initWithMenu:(UIMenu *)menu;
- (void)close;
@end
@implementation ChromeQuickController
- (instancetype)initWithMenu:(UIMenu *)menu {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { entries = [menu retain]; self.title = menu.title.length ? menu.title : @"Quick Controls"; }
    return self;
}
- (void)dealloc { [entries release]; [super dealloc]; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 48;
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)] autorelease];
}
- (void)close { bar_up_close_all(); }
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller {
    (void)controller; return UIModalPresentationNone;
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentation { chrome_menu_finish(presentation.presentedViewController); }
- (void)popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController *)popover { chrome_menu_finish(popover.presentedViewController); }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; (void)section; return entries.children.count;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"quick"];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"quick"] autorelease];
    UIMenuElement *entry = entries.children[path.row];
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.text = entry.title; content.image = entry.image;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.textProperties.numberOfLines = 0;
    const BOOL group = [entry isKindOfClass:[UIMenu class]];
    const BOOL destructive = !group && (((UIAction *)entry).attributes & UIMenuElementAttributesDestructive);
    content.textProperties.color = destructive ? [UIColor systemRedColor] : [UIColor labelColor];
    content.imageProperties.tintColor = destructive ? [UIColor systemRedColor] : [UIColor secondaryLabelColor];
    cell.contentConfiguration = content;
    cell.accessoryType = group ? UITableViewCellAccessoryDisclosureIndicator : ((UIAction *)entry).state == UIMenuElementStateOn ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = [UIColor systemBlueColor];
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (!chrome_menu_open || chrome_menu_closing || self.navigationController != chrome_menu_controller) return;
    UIMenuElement *entry = entries.children[path.row];
    if ([entry isKindOfClass:[UIMenu class]]) {
        ChromeQuickController *child = [[[ChromeQuickController alloc] initWithMenu:(UIMenu *)entry] autorelease];
        [self.navigationController pushViewController:child animated:!UIAccessibilityIsReduceMotionEnabled()];
    } else {
        [g_menu_gear sendAction:(UIAction *)entry];
        bar_up_close_all();
    }
}
@end
static void bar_up_close_all(void) {
    if (!chrome_menu_controller || chrome_menu_closing) return;
    chrome_menu_closing = YES;
    __block UIViewController *closing = chrome_menu_controller;
    [closing dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:^{ chrome_menu_finish(closing); }];
}
static int bar_visible(void) { return chrome_menu_open; }
int ios_ui_chrome_blocks_touch(void) { return g_installed && chrome_menu_open; }
void ios_ui_bar_open(void) {
    if (!g_installed) return;
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ ios_ui_bar_open(); }); return; }
    if (chrome_menu_open || overlay_is_open() || (overlay_pad_hidden() & 8) || g_win.rootViewController.presentedViewController) return;
    overlay_intro_dismiss(); touchpad_cancel_all(); ios_ui_chrome_cancel_controls();
    ChromeQuickController *list = [[[ChromeQuickController alloc] initWithMenu:chrome_quick_menu()] autorelease];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
    nav.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    nav.view.tintColor = [UIColor systemBlueColor];
    nav.modalPresentationStyle = UIModalPresentationPopover;
    nav.preferredContentSize = CGSizeMake(340, fmin(440,chrome_safe_rect().size.height-24));
    UIPopoverPresentationController *popover = nav.popoverPresentationController;
    popover.sourceView = g_menu_gear; popover.sourceRect = g_menu_gear.bounds;
    popover.delegate = list;
    chrome_menu_controller = nav; chrome_menu_open = YES; chrome_menu_closing = NO;
    [g_win.rootViewController presentViewController:nav animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
    nav.presentationController.delegate = list;
    ios_ui_haptic(0);
}
static void chrome_menu_install(void) {
    g_menu_gear.menu = nil;
    g_menu_gear.showsMenuAsPrimaryAction = NO;
    control_on(g_menu_gear, UIControlEventTouchUpInside, ^{ ios_ui_bar_open(); });
}
