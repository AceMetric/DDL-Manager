#import "QuietUI.h"
// Exercise the real AppKit views with in-memory preview tasks only.
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#include <stdio.h>
#include <stdlib.h>

static NSInteger assertions;
static void CheckUI(BOOL passed, NSString *message) {
    assertions++;
    if (!passed) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static OverviewGrid *FirstGrid(AppDelegate *app) {
    for (NSView *view in app.calendarDocument.subviews) if ([view isKindOfClass:OverviewGrid.class]) return (OverviewGrid *)view;
    return nil;
}
static void Search(AppDelegate *app, NSString *text) {
    app.search.stringValue = text;
    [app controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:app.search]];
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.arguments containsObject:@"--preview"]) return 2;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *app = [AppDelegate new]; NSApp.delegate = app;
        [app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];
        CheckUI(app.preview && app.tasks.count == 13 && app.page == 0 && app.courseWindow != nil, @"preview starts on overview with synthetic tasks");
        [app openCalendar:nil];
        OverviewGrid *initial = FirstGrid(app);
        CheckUI(initial != nil && app.calendarDocument.subviews.count == 26, @"13 calendar sections loaded");
        // Freeze the cache minute for deterministic reuse assertions.
        app.overviewMinute = (NSInteger)floor(NSDate.date.timeIntervalSince1970 / 60);
        [app render];
        CheckUI(FirstGrid(app) == initial, @"unchanged render reuses calendar views");
        app.selectedDay = [Cal() dateByAddingUnit:NSCalendarUnitDay value:1 toDate:app.selectedDay options:0];
        [app renderOverview];
        CheckUI(FirstGrid(app) == initial, @"date selection reuses calendar views");
        CheckUI([Cal() isDate:initial.selection inSameDayAsDate:app.selectedDay], @"reused calendar receives new selection");
        NSPopUpButton *yearPicker = app.yearPicker;
        Search(app, @"英"); NSTimer *first = app.searchTimer;
        Search(app, @"  英语  ");
        CheckUI(!first.valid && app.searchTimer.valid, @"successive searches cancel pending refresh");
        CheckUI([app.query isEqual:@"英语"], @"search trims whitespace");
        NSDate *searchLimit=[NSDate dateWithTimeIntervalSinceNow:2];
        while(app.searchTimer && searchLimit.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        CheckUI(app.searchTimer == nil && app.overviewSnapshot.count == 3, @"debounced search applies latest query");
        CheckUI(app.yearPicker == yearPicker, @"search preserves month controls");
        Search(app, @"");
        CheckUI(app.searchTimer == nil && app.overviewSnapshot.count == 13, @"clear search restores calendar immediately");
        OverviewGrid *beforeMutation = FirstGrid(app);
        app.tasks[0][@"title"] = @"更新后的演示任务";
        [app renderOverview];
        CheckUI(FirstGrid(app) != beforeMutation, @"mutable task edits invalidate calendar cache");
        CheckUI([app.overviewSnapshot containsObject:app.tasks[0]], @"updated content included in snapshot");
        OverviewGrid *beforeResize = FirstGrid(app);
        NSRect frame = app.calendarScroll.frame; frame.size.width -= 100; app.calendarScroll.frame = frame;
        [app renderOverview];
        CheckUI(FirstGrid(app) != beforeResize, @"resize relays out calendar grid");
        OverviewGrid *beforeTick = FirstGrid(app); app.overviewMinute--;
        [app renderOverview];
        CheckUI(FirstGrid(app) != beforeTick, @"minute change refreshes time-sensitive styling");
        app.calendarStatus.selectedSegment = 2; [app renderOverview];
        CheckUI(app.overviewSnapshot.count == 6, @"completed filter invalidates cached content");
        app.calendarStatus.selectedSegment = 0;
        [app openList:nil]; Search(app, @"  英语  "); [app applySearch];
        CheckUI([app visibleTasks].count == 1, @"list and calendar share whitespace search behavior");
        Search(app, @"设计"); [app openCalendar:nil]; [app applySearch];
        CheckUI(app.query.length == 0 && app.overviewSnapshot.count == 13, @"calendar restores its own search independently of task page");
        [app.monthPicker selectItemWithTitle:@"1 月"]; [app jumpCalendar:nil];
        CheckUI([Cal() component:NSCalendarUnitMonth fromDate:app.month] == 1, @"exact month jump rebuilds correct window");
        CheckUI([Cal() isDate:app.overviewBaseMonth equalToDate:app.month toUnitGranularity:NSCalendarUnitMonth], @"cached month matches jump target");
        CheckUI(NSApp.appearance == nil, @"application follows system appearance by default");
        CheckUI(app.root.gradientEnd == nil && !app.sidebar.hidden, @"layered surfaces and persistent sidebar");
        NSDateComponents *september = [NSDateComponents new]; september.year = 2026; september.month = 9; september.day = 1;
        NSDate *testMonth = [Cal() dateFromComponents:september];
        NSDate *adjacentDay = DDLMonthGrid(testMonth, Cal()).firstObject;
        OverviewGrid *adjacentGrid = [OverviewGrid new]; adjacentGrid.frame = NSMakeRect(0, 0, 896, 540); adjacentGrid.month = testMonth; adjacentGrid.selection = testMonth;
        adjacentGrid.tasksByDay = @{[Cal() startOfDayForDate:adjacentDay]: @[app.tasks.firstObject]}; [adjacentGrid reload];
        CalendarDayCell *adjacentCell = nil;
        for (NSView *view in adjacentGrid.subviews) if ([view isKindOfClass:CalendarDayCell.class] && [Cal() isDate:((CalendarDayCell *)view).date inSameDayAsDate:adjacentDay]) adjacentCell = (CalendarDayCell *)view;
        NSInteger adjacentEvents = 0;
        for (NSView *view in adjacentCell.subviews) if ([view isKindOfClass:CalendarTaskButton.class]) adjacentEvents++;
        CheckUI(adjacentCell != nil && !adjacentCell.inMonth && adjacentEvents == 0, @"adjacent-month dates hide schedule entries");
        CheckUI([adjacentCell.fill isEqual:[Panel() blendedColorWithFraction:0.48 ofColor:Line()]], @"adjacent-month dates use deeper background");
        NSButton *today = [NSButton new]; today.tag = 0; [app navigateCalendar:today];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.4]];
        NSDate *selectedDay = app.selectedDay, *month = app.month;
        NSArray *tasksBeforeTheme = [app.tasks copy];
        NSPoint scrollBeforeTheme = app.calendarScroll.contentView.bounds.origin;
        for (NSString *appearance in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            OverviewGrid *oldGrid = FirstGrid(app);
            NSApp.appearance = [NSAppearance appearanceNamed:appearance]; [app refreshAppearance];
            CheckUI(FirstGrid(app) != oldGrid, @"appearance invalidates cached calendar colors");
            CheckUI([app.selectedDay isEqual:selectedDay] && [app.month isEqual:month] && [app.tasks isEqual:tasksBeforeTheme], @"appearance preserves dates and tasks");
            CheckUI(NSEqualPoints(app.calendarScroll.contentView.bounds.origin, scrollBeforeTheme), @"appearance preserves calendar scroll");
            [app.window displayIfNeeded];
            NSBitmapImageRep *bitmap = [app.root bitmapImageRepForCachingDisplayInRect:app.root.bounds]; [app.root cacheDisplayInRect:app.root.bounds toBitmapImageRep:bitmap];
            NSString *path = [NSString stringWithFormat:@"build/qa/calendar-%@.png", [appearance isEqual:NSAppearanceNameAqua] ? @"light" : @"dark"];
            CheckUI([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:NO], @"synthetic appearance preview exported");
        }
        OverviewGrid *hoverGrid = nil;
        for (NSView *view in app.calendarDocument.subviews) {
            if ([view isKindOfClass:OverviewGrid.class] && !NSIsEmptyRect(NSIntersectionRect(view.bounds, view.visibleRect))) { hoverGrid = (OverviewGrid *)view; break; }
        }
        CalendarDayCell *hoverCell = nil;
        for (NSView *view in hoverGrid.subviews) {
            if ([view isKindOfClass:CalendarDayCell.class] && !NSIsEmptyRect(NSIntersectionRect(view.bounds, view.visibleRect))) { hoverCell = (CalendarDayCell *)view; break; }
        }
        CheckUI(hoverCell != nil, @"visible calendar day exists for hover regression");
        CallbackButton *dayHit = nil;
        for (NSView *view in hoverCell.subviews) if ([view isKindOfClass:CallbackButton.class] && NSEqualRects(view.frame, hoverCell.bounds)) dayHit = (CallbackButton *)view;
        CheckUI(dayHit != nil && !dayHit.allowsHoverFill, @"transparent day hit area never paints stale hover fill");
        NSRect visibleDay = NSIntersectionRect(hoverCell.bounds, hoverCell.visibleRect);
        NSPoint pointer = [hoverCell convertPoint:NSMakePoint(NSMidX(visibleDay), NSMidY(visibleDay)) toView:nil];
        NSInteger staleCount = 0;
        for (NSView *view in hoverGrid.subviews) if ([view isKindOfClass:CalendarDayCell.class]) { ((CalendarDayCell *)view).hovered = YES; staleCount++; }
        CheckUI(staleCount > 1, @"regression setup contains multiple stale hovered days");
        [hoverGrid refreshHoverAtWindowPoint:pointer];
        NSInteger activeCount = 0;
        for (NSView *view in hoverGrid.subviews) if ([view isKindOfClass:CalendarDayCell.class] && ((CalendarDayCell *)view).hovered) activeCount++;
        CheckUI(activeCount == 1 && hoverCell.hovered, @"pointer highlights only its visible day");
        NSPoint shifted = app.calendarScroll.contentView.bounds.origin; shifted.y += NSHeight(hoverCell.bounds);
        [app.calendarScroll.contentView scrollToPoint:shifted]; [app.calendarScroll reflectScrolledClipView:app.calendarScroll.contentView];
        [hoverGrid refreshHoverAtWindowPoint:pointer];
        activeCount = 0;
        for (NSView *view in hoverGrid.subviews) if ([view isKindOfClass:CalendarDayCell.class] && ((CalendarDayCell *)view).hovered) activeCount++;
        CheckUI(activeCount <= 1, @"scrolling does not leave a dark calendar column");
        [app openList:nil];
        CheckUI(!app.sidebar.hidden && app.page == 2, @"task page retains sidebar");
        [app.window setContentSize:NSMakeSize(960, 640)]; [app layout];
        CheckUI(NSMaxX(app.search.frame) <= NSWidth(app.root.bounds), @"search fits minimum window");
        NSMutableDictionary *noteTask=[@{@"id":@"notes-fixture",@"title":@"备注显示测试",@"subject":@"模拟课程",@"notes":@"审核保存的备注\n第二行",@"due":[NSDate dateWithTimeIntervalSinceNow:3600],@"completed":@NO} mutableCopy];
        [app.tasks addObject:noteTask];Search(app,@"");[app applySearch];
        Surface *noteRow=[app taskRow:noteTask width:700];BOOL noteVisible=NO;
        for(NSView *view in noteRow.subviews)if([view isKindOfClass:NSTextField.class] && [((NSTextField *)view).stringValue containsString:@"审核保存的备注"])noteVisible=YES;
        CheckUI(!noteVisible && [app taskRowHeight:noteTask base:80]==80 && app.taskDetails.hidden,@"notes are hidden and rows stay compact before selection");
        NSButton *select=NSButton.new;select.identifier=noteTask[@"id"];[app selectTask:select];
        CheckUI(!app.taskDetails.hidden && [app.taskDetailsText.string containsString:noteTask[@"notes"]] && !app.taskDetailsText.editable && app.taskDetailsText.selectable,@"selected task exposes complete copyable notes in inspector");
        TaskSelectionRow *interactive=(TaskSelectionRow *)[app taskRow:noteTask width:700];
        NSView *titleHit=[interactive hitTest:NSMakePoint(80,24)],*checkHit=[interactive hitTest:NSMakePoint(24,36)];
        CheckUI(titleHit==interactive && [checkHit isKindOfClass:NSButton.class] && ((NSButton *)checkHit).action==@selector(toggleTask:),@"row selection hit area does not intercept completion button");
        CheckUI([app.window.firstResponder isKindOfClass:TaskSelectionRow.class],@"selected row receives keyboard focus");
        CheckUI(!NSIntersectsRect(app.scroll.frame,app.taskDetails.frame) && NSMaxX(app.taskDetails.frame)<=NSWidth(app.root.bounds) && NSMaxY(app.taskDetails.frame)<=NSHeight(app.root.bounds),@"task list and inspector fit minimum window without overlap");
        NSArray *ordered=app.selectionTasks;NSUInteger selectedIndex=0;for(NSUInteger i=0;i<ordered.count;i++)if([ordered[i][@"id"] isEqual:noteTask[@"id"]]){selectedIndex=i;break;}
        NSEvent *down=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.window.windowNumber context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:125];
        [(TaskSelectionRow *)app.window.firstResponder keyDown:down];CheckUI([app.selectedTaskID isEqual:ordered[MIN(selectedIndex+1,ordered.count-1)][@"id"]],@"arrow key selects adjacent task by stable identity");[app selectTask:select];
        NSEvent *escape=[NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:app.window.windowNumber context:nil characters:@"\033" charactersIgnoringModifiers:@"\033" isARepeat:NO keyCode:53];
        [(TaskSelectionRow *)app.window.firstResponder keyDown:escape];CheckUI(app.selectedTaskID==nil && app.taskDetails.hidden,@"Escape from selected task row closes inspector");[app selectTask:select];
        NSArray *taskSnapshot=[[NSArray alloc] initWithArray:app.tasks copyItems:YES];TaskDetailsText *sameDetails=app.taskDetailsText;[app render];
        CheckUI(app.taskDetailsText==sameDetails && [[[NSArray alloc] initWithArray:app.tasks copyItems:YES] isEqual:taskSnapshot],@"refresh reuses notes selection and never changes task data");
        NSString *savedSelection=app.selectedTaskID;NSButton *overview=NSButton.new;overview.tag=0;[app navigate:overview];
        CheckUI(app.taskDetails.hidden,@"overview starts without an inspector selection");[app selectTask:select];
        CheckUI([app.taskDetailsText.string containsString:noteTask[@"notes"]],@"overview selection shows notes in side inspector");
        [app openList:nil];CheckUI([app.selectedTaskID isEqual:savedSelection],@"task selection is restored independently per page");
        noteTask[@"notes"]=[@"完整长备注\n" stringByPaddingToLength:6000 withString:@"第二行内容。\n" startingAtIndex:0];[app render];
        CheckUI([app.taskDetailsText.string containsString:noteTask[@"notes"]] && NSHeight(app.taskDetailsText.frame)>NSHeight(app.taskDetailsScroll.bounds),@"edited long notes update immediately and can scroll");
        for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){NSApp.appearance=[NSAppearance appearanceNamed:appearance];[app refreshAppearance];CheckUI([app.selectedTaskID isEqual:noteTask[@"id"]] && [app.taskDetailsText.string containsString:noteTask[@"notes"]],@"appearance preserves selected task and full notes");}
        Search(app,@"not-a-task");[app applySearch];CheckUI(app.selectedTaskID==nil && app.taskDetails.hidden,@"filtering out selected task closes inspector");Search(app,@"");[app applySearch];
        noteTask[@"notes"]=@"";[app selectTask:select];CheckUI([app.taskDetailsText.string containsString:@"暂无备注"],@"empty notes have a short actionable hint");
        for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){NSApp.appearance=[NSAppearance appearanceNamed:appearance];[app refreshAppearance];[app.window displayIfNeeded];NSBitmapImageRep *preview=[app.root bitmapImageRepForCachingDisplayInRect:app.root.bounds];[app.root cacheDisplayInRect:app.root.bounds toBitmapImageRep:preview];CheckUI([[preview representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithFormat:@"build/qa/task-inspector-%@.png",[appearance isEqual:NSAppearanceNameAqua] ? @"light":@"dark"] atomically:NO],@"synthetic task inspector preview exported");}
        [app.taskDetailsText cancelOperation:nil];CheckUI(app.selectedTaskID==nil && app.taskDetails.hidden,@"Escape closes notes inspector");
        [app selectTask:select];noteTask[@"deleted"]=@YES;[app render];CheckUI(app.selectedTaskID==nil && app.taskDetails.hidden,@"deleted task does not leave stale details");noteTask[@"deleted"]=@NO;
        [app openCalendar:nil];app.selectedDay=noteTask[@"due"];[app selectTask:select];
        CheckUI(app.taskDetailsScroll.superview==app.agenda && [app.taskDetailsText.string containsString:@"暂无备注"],@"calendar reuses agenda for selected task details");[app closeTaskDetails:nil];
        [app openCalendar:nil]; CheckUI(NSMinY(app.agenda.frame) >= NSMaxY(app.calendarScroll.frame), @"compact calendar places agenda beneath months");
        [app.window setContentSize:NSMakeSize(1280, 840)]; [app layout];
        CheckUI(NSMinX(app.agenda.frame) > NSMaxX(app.calendarScroll.frame), @"wide calendar places agenda alongside months");
        [app openCourses:nil]; CheckUI(app.page == 4 && !app.courseWindow.view.hidden && app.courseWindow.view.window == app.window, @"courses share the main window");
        [app openList:nil];
        [app.window displayIfNeeded];
        NSBitmapImageRep *listBitmap = [app.root bitmapImageRepForCachingDisplayInRect:app.root.bounds];
        [app.root cacheDisplayInRect:app.root.bounds toBitmapImageRep:listBitmap];
        [[listBitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@"build/qa/tasks-default.png" atomically:NO];
        ActionButton *navigationFocus = nil; for (NSView *view in app.navigationScroll.documentView.subviews) if ([view isKindOfClass:ActionButton.class] && ((ActionButton *)view).action == @selector(selectSidebarCourse:) && [view.identifier isEqual:@""]) navigationFocus = (ActionButton *)view;
        [app.window makeFirstResponder:navigationFocus]; [app refreshAppearance]; CheckUI([app.window.firstResponder isKindOfClass:ActionButton.class] && ((ActionButton *)app.window.firstResponder).action == @selector(selectSidebarCourse:) && [[(NSView *)app.window.firstResponder identifier] isEqual:@""], @"appearance refresh preserves sidebar keyboard focus");
        [app.taskUndo removeAllActions]; [app.taskUndo beginUndoGrouping]; NSButton *check = NSButton.new; check.identifier = app.tasks.firstObject[@"id"]; BOOL completed = [app.tasks.firstObject[@"completed"] boolValue]; [app toggleTask:check]; [app.taskUndo endUndoGrouping];
        CheckUI([app.tasks.firstObject[@"completed"] boolValue] != completed, @"task completion updates through unified rows"); [app undo:nil]; CheckUI([app.tasks.firstObject[@"completed"] boolValue] == completed, @"undo restores completion after navigation changes");
        NSMenuItem *archive = NSMenuItem.new; archive.representedObject = check.identifier; [app archiveTask:archive]; CheckUI([app.tasks.firstObject[@"archived"] boolValue], @"more-menu archive uses represented task identity");
        [app.ticker invalidate]; [app.searchTimer invalidate];
        [app.window orderOut:nil]; [NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
        printf("PASS: %ld AppKit assertions\n", (long)assertions);
    }
    return 0;
}
