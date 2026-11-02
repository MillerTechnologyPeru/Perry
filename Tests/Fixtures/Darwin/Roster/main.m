// Table views: defaults, row, header and footer geometry, cells made only
// for visible rows and reused while scrolling, floating section headers,
// selection, scrolling to rows, reloading, inserting and deleting rows,
// table header and footer views, and a table view controller under a
// navigation bar. Geometry under the bar is checked against the bar, so
// the output does not depend on the device's screen.

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *path(NSIndexPath *indexPath) {
    return indexPath ? [NSString stringWithFormat:@"%ld.%ld", (long)indexPath.section, (long)indexPath.row] : @"nil";
}

static NSInteger cellsMade, reuses;

@interface Cell : UITableViewCell
@end

@implementation Cell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    cellsMade++;
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    reuses++;
}
@end

@interface Source : NSObject <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSMutableArray<NSMutableArray<NSString *> *> *sections;
@property (nonatomic) NSInteger requests, displays, endDisplays, selections;
@property (nonatomic) BOOL titled;
@end

@implementation Source

- (instancetype)initWithCounts:(NSArray<NSNumber *> *)counts {
    self = [super init];
    _sections = [NSMutableArray array];
    for (NSUInteger section = 0; section < counts.count; section++) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSInteger row = 0; row < counts[section].integerValue; row++) {
            [rows addObject:[NSString stringWithFormat:@"%lu.%ld", (unsigned long)section, (long)row]];
        }
        [_sections addObject:rows];
    }
    _titled = YES;
    return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.textLabel.text = self.sections[indexPath.section][indexPath.row];
    self.requests++;
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.titled ? [NSString stringWithFormat:@"Section %ld", (long)section] : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 && indexPath.row == 0 ? 100 : 44;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    self.displays++;
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    self.endDisplays++;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.selections++;
}

@end

static NSString *visible(UITableView *table) {
    NSArray<NSIndexPath *> *paths = table.indexPathsForVisibleRows;
    return [NSString stringWithFormat:@"%lu rows %@ to %@, %lu cells", (unsigned long)paths.count, path(paths.firstObject),
            path(paths.lastObject), (unsigned long)table.visibleCells.count];
}

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) Source *source;
@property (nonatomic, strong) Source *plain;
@property (nonatomic, strong) UITableViewController *list;
@property (nonatomic, strong) UINavigationController *navigation;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(0, 200, 320, 480) style:UITableViewStylePlain];
    self.table = table;
    say([NSString stringWithFormat:@"defaults: style %ld, row %.0f, estimated %.0f, header %.0f %.0f, footer %.0f %.0f, padding %.0f",
         (long)table.style, table.rowHeight, table.estimatedRowHeight, table.sectionHeaderHeight, table.estimatedSectionHeaderHeight,
         table.sectionFooterHeight, table.estimatedSectionFooterHeight, table.sectionHeaderTopPadding]);
    say([NSString stringWithFormat:@"  separator style %ld, inset %@, selection %d multiple %d, editing %d, data source %d, scroll view %d",
         (long)table.separatorStyle, NSStringFromUIEdgeInsets(table.separatorInset), table.allowsSelection,
         table.allowsMultipleSelection, table.editing, table.dataSource != nil, [table isKindOfClass:UIScrollView.class]]);
    UITableViewCell *loose = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"loose"];
    UITableViewCell *value = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    say([NSString stringWithFormat:@"cell: frame %@, content in cell %d, label %d, detail %d %d, accessory %ld, selection %ld, reuse %@ %@",
         NSStringFromCGRect(loose.frame), loose.contentView.superview == loose, loose.textLabel != nil, loose.detailTextLabel != nil,
         value.detailTextLabel != nil, (long)loose.accessoryType, (long)loose.selectionStyle, loose.reuseIdentifier,
         value.reuseIdentifier]);

    table.rowHeight = 44;
    table.estimatedRowHeight = 0;
    table.sectionHeaderHeight = 28;
    table.estimatedSectionHeaderHeight = 0;
    table.sectionFooterHeight = 0;
    table.estimatedSectionFooterHeight = 0;
    table.sectionHeaderTopPadding = 0;
    table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [table registerClass:Cell.class forCellReuseIdentifier:@"cell"];
    self.source = [[Source alloc] initWithCounts:@[@30, @5]];
    table.dataSource = self.source;
    table.delegate = self.source;

    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [[UIViewController alloc] init];
    [self.window makeKeyAndVisible];
    [self.window.rootViewController.view addSubview:table];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:NO block:^(NSTimer *timer) {
        [self tables];
        [self controller];
    }];
}

- (void)tables {
    UITableView *table = self.table;
    Source *source = self.source;
    [table layoutIfNeeded];
    say([NSString stringWithFormat:@"laid out: content %@, %@, requests %ld, made %ld, displays %ld",
         NSStringFromCGSize(table.contentSize), visible(table), (long)source.requests, (long)cellsMade, (long)source.displays]);
    say([NSString stringWithFormat:@"  sections %ld, rows %ld %ld, row 0.0 %@, row 1.0 %@, row 1.1 %@",
         (long)table.numberOfSections, (long)[table numberOfRowsInSection:0], (long)[table numberOfRowsInSection:1],
         NSStringFromCGRect([table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]]),
         NSStringFromCGRect([table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]]),
         NSStringFromCGRect([table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:1]])]);
    say([NSString stringWithFormat:@"  section 1 %@, header 1 %@, footer 0 %@",
         NSStringFromCGRect([table rectForSection:1]), NSStringFromCGRect([table rectForHeaderInSection:1]),
         NSStringFromCGRect([table rectForFooterInSection:0])]);
    UITableViewCell *cell = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:3 inSection:0]];
    say([NSString stringWithFormat:@"  cell 0.3: %@ frame %@, content height %.2f, text %@, reuse %@, in table %d, hidden row %d",
         NSStringFromClass(cell.class), NSStringFromCGRect(cell.frame), cell.contentView.frame.size.height, cell.textLabel.text,
         cell.reuseIdentifier, cell.superview == table, [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:20 inSection:0]] != nil]);
    UITableViewHeaderFooterView *header = [table headerViewForSection:0];
    say([NSString stringWithFormat:@"  at points: %@ %@, header %@ %@ frame %@, index of cell %@",
         path([table indexPathForRowAtPoint:CGPointMake(10, 100)]), path([table indexPathForRowAtPoint:CGPointMake(10, 2000)]),
         NSStringFromClass(header.class), header.textLabel.text, NSStringFromCGRect(header.frame), path([table indexPathForCell:cell])]);

    table.contentOffset = CGPointMake(0, 610);
    [table layoutIfNeeded];
    say([NSString stringWithFormat:@"scrolled: %@, requests %ld, made %ld, reuses %ld, displays %ld, ended %ld, header 0 at %.0f",
         visible(table), (long)source.requests, (long)cellsMade, (long)reuses, (long)source.displays, (long)source.endDisplays,
         [table headerViewForSection:0].frame.origin.y]);

    NSIndexPath *fourteen = [NSIndexPath indexPathForRow:14 inSection:0];
    [table selectRowAtIndexPath:fourteen animated:NO scrollPosition:UITableViewScrollPositionNone];
    say([NSString stringWithFormat:@"selected: %@, cell selected %d, delegate told %ld", path(table.indexPathForSelectedRow),
         [table cellForRowAtIndexPath:fourteen].selected, (long)source.selections]);
    [table deselectRowAtIndexPath:fourteen animated:NO];
    say([NSString stringWithFormat:@"deselected: %@, cell selected %d", path(table.indexPathForSelectedRow),
         [table cellForRowAtIndexPath:fourteen].selected]);

    NSIndexPath *twenty = [NSIndexPath indexPathForRow:20 inSection:0];
    [table scrollToRowAtIndexPath:twenty atScrollPosition:UITableViewScrollPositionTop animated:NO];
    CGFloat top = table.contentOffset.y;
    [table scrollToRowAtIndexPath:twenty atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    CGFloat middle = table.contentOffset.y;
    [table scrollToRowAtIndexPath:twenty atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    CGFloat bottom = table.contentOffset.y;
    [table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:4 inSection:1] atScrollPosition:UITableViewScrollPositionTop animated:NO];
    say([NSString stringWithFormat:@"scroll to row: top %.0f, middle %.0f, bottom %.0f, last %.0f", top, middle, bottom,
         table.contentOffset.y]);

    table.contentOffset = CGPointZero;
    [source.sections[0] removeObjectsInRange:NSMakeRange(10, 20)];
    [source.sections[1] removeObjectsInRange:NSMakeRange(2, 3)];
    NSInteger before = source.requests;
    [table reloadData];
    [table layoutIfNeeded];
    say([NSString stringWithFormat:@"reloaded: content %@, rows %ld %ld, %@, requests %ld", NSStringFromCGSize(table.contentSize),
         (long)[table numberOfRowsInSection:0], (long)[table numberOfRowsInSection:1], visible(table), (long)(source.requests - before)]);

    before = source.requests;
    [source.sections[0] insertObject:@"new" atIndex:0];
    [table insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    [table layoutIfNeeded];
    say([NSString stringWithFormat:@"inserted: rows %ld, 0.0 %@, 0.1 %@, requests %ld, content %@", (long)[table numberOfRowsInSection:0],
         [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]].textLabel.text,
         [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]].textLabel.text, (long)(source.requests - before),
         NSStringFromCGSize(table.contentSize)]);
    [source.sections[0] removeObjectAtIndex:0];
    [table deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    [table layoutIfNeeded];
    say([NSString stringWithFormat:@"deleted: rows %ld, 0.0 %@, content %@", (long)[table numberOfRowsInSection:0],
         [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]].textLabel.text, NSStringFromCGSize(table.contentSize)]);
    [table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    source.sections[0][2] = @"changed";
    [table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    [table layoutIfNeeded];
    say([NSString stringWithFormat:@"reloaded row: 0.2 %@", [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]].textLabel.text]);

    table.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 60)];
    table.tableFooterView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 50)];
    [table layoutIfNeeded];
    say([NSString stringWithFormat:@"table header and footer: header %@, footer %@, row 0.0 %@, content %@",
         NSStringFromCGRect(table.tableHeaderView.frame), NSStringFromCGRect(table.tableFooterView.frame),
         NSStringFromCGRect([table rectForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]]),
         NSStringFromCGSize(table.contentSize)]);
}

- (void)controller {
    self.plain = [[Source alloc] initWithCounts:@[@40]];
    self.plain.titled = NO;
    UITableViewController *list = [[UITableViewController alloc] initWithStyle:UITableViewStylePlain];
    self.list = list;
    say([NSString stringWithFormat:@"controller: view is table %d, clears selection %d, table delegate is controller %d",
         list.view == list.tableView, list.clearsSelectionOnViewWillAppear, list.tableView.delegate == list]);
    [list.tableView registerClass:Cell.class forCellReuseIdentifier:@"cell"];
    list.tableView.dataSource = self.plain;
    list.tableView.delegate = self.plain;
    list.tableView.rowHeight = 44;
    list.tableView.estimatedRowHeight = 0;
    self.navigation = [[UINavigationController alloc] initWithRootViewController:list];
    self.window.rootViewController = self.navigation;
    [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:NO block:^(NSTimer *timer) {
        UITableView *table = list.tableView;
        UINavigationBar *bar = self.navigation.navigationBar;
        UIEdgeInsets adjusted = table.adjustedContentInset;
        UITableViewCell *first = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        say([NSString stringWithFormat:@"under bar: adjusted top at bar %d, bottom is window's %d, offset at top %d, first row at bar %d",
             adjusted.top == CGRectGetMaxY(bar.frame), adjusted.bottom == self.window.safeAreaInsets.bottom,
             table.contentOffset.y == -adjusted.top, [first convertPoint:CGPointZero toView:nil].y == CGRectGetMaxY(bar.frame)]);
        say([NSString stringWithFormat:@"  content height %.0f, width is table's %d, visible from %@, cell width is table's %d",
             table.contentSize.height, table.contentSize.width == table.bounds.size.width,
             path(table.indexPathsForVisibleRows.firstObject), first.frame.size.width == table.bounds.size.width]);
        say(@"done");
        exit(0);
    }];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, nil);
    }
}
