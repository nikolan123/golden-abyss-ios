/* Long option lists use a real navigation sheet rather than an action sheet. */
@interface CfgChoiceController : UITableViewController {
    CfgRow *choice;
    int ownerPage;
}
- (instancetype)initWithRow:(CfgRow *)row;
- (void)close;
@end
@implementation CfgChoiceController
- (instancetype)initWithRow:(CfgRow *)row {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) { choice = [row retain]; ownerPage = g_cfg_page; self.title = row->title; }
    return self;
}
- (void)dealloc { [choice release]; [super dealloc]; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension; self.tableView.estimatedRowHeight = 52;
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(close)] autorelease];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (choice->sel >= 0 && choice->sel < (int)choice->seg.count)
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:choice->sel inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
}
- (void)close {
    UINavigationController *nav = self.navigationController;
    [nav dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:^{ cfg_picker_finished(nav); }];
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    (void)table; (void)section; return choice->seg.count;
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    (void)table; (void)section; return choice->detail;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"choice"];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"choice"] autorelease];
    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.text = choice->seg[path.row]; content.textProperties.numberOfLines = 0;
    content.textProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.contentConfiguration = content;
    cell.accessoryType = path.row == choice->sel ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = [UIColor systemBlueColor];
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    if (g_cfg_picker == self.navigationController && overlay_native_settings_wanted() && g_cfg_page == ownerPage && [g_cfg_rows containsObject:choice]) {
        choice->sel = (int)path.row;
        if (choice->pick) choice->pick(choice->sel);
        [g_cfg_tbl reloadData]; ios_ui_haptic(0);
    }
    [self close];
}
@end
static void cfg_choose(CfgRow *row) {
    if (g_cfg_picker || g_win.rootViewController.presentedViewController || !overlay_native_settings_wanted()) return;
    CfgChoiceController *list = [[[CfgChoiceController alloc] initWithRow:row] autorelease];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:list];
    nav.view.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; nav.view.tintColor = [UIColor systemBlueColor];
    nav.modalPresentationStyle = UIModalPresentationPageSheet;
    nav.preferredContentSize = CGSizeMake(500,420);
    UISheetPresentationController *sheet = nav.sheetPresentationController;
    sheet.detents = @[[UISheetPresentationControllerDetent largeDetent]];
    sheet.prefersGrabberVisible = YES;
    sheet.prefersEdgeAttachedInCompactHeight = YES;
    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = YES;
    g_cfg_picker = nav;
    [g_win.rootViewController presentViewController:nav animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
    nav.presentationController.delegate = (id<UIAdaptivePresentationControllerDelegate>)g_cfg_center;
}
