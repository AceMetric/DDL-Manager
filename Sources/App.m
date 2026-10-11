#import <Cocoa/Cocoa.h>
#import <UserNotifications/UserNotifications.h>
#import "DDLCore.h"
#import "DDLImport.h"
#import "ThemeIcon.h"
#import "SSLocalData.h"
#import "SSCourseWindow.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "DDLUI.h"
#import "SSUpdateController.h"
#import "SSExitCoordinator.h"
#import "SSRecognition.h"
#import "AMUI-Swift.h"

static NSImage *ThemeIcon(void) {
    unsigned accent = 0x2262B0;
    return [NSImage imageWithSize:NSMakeSize(512, 512) flipped:NO drawingHandler:^BOOL(NSRect bounds) {
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *transform = [NSAffineTransform transform]; [transform scaleBy:NSWidth(bounds) / 1024.0]; [transform concat];
        DDLDrawThemeIcon(accent);
        [NSGraphicsContext restoreGraphicsState];
        return YES;
    }];
}
static NSCalendar *Cal(void) { NSCalendar *c = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; c.firstWeekday = 2; return c; }

#import "SSReminders.inc"

@interface DayButton : NSButton
@property NSDate *date;
@property BOOL inMonth;
@property BOOL chosen;
@property BOOL today;
@property BOOL compact;
@property NSArray<NSDictionary *> *tasks;
@end
@implementation DayButton
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *bg = self.chosen ? Tint() : (self.highlighted ? Tint() : Card());
    [bg setFill]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 2, 2) xRadius:8 yRadius:8] fill];
    CGFloat numberX = self.compact ? (self.bounds.size.width - 24) / 2 : 8;
    if (self.today) {
        [[[NSGradient alloc] initWithStartingColor:Emphasis() endingColor:Tint()] drawInBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(numberX, 4, 24, 24) xRadius:12 yRadius:12] angle:-70];
    }
    DrawText(DDLFormatDate(self.date, @"d"), NSMakeRect(numberX, 7, 24, 19), 12, self.today || self.chosen ? NSFontWeightSemibold : NSFontWeightRegular, self.today ? Accent() : (self.inMonth ? Ink() : Muted()), NSTextAlignmentCenter);
    if (self.compact && self.tasks.count) {
        [Accent() setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect((self.bounds.size.width - 3) / 2, self.bounds.size.height - 6, 3, 3)] fill];
    } else if (!self.compact && self.tasks.count) {
        NSDictionary *first = self.tasks.firstObject;
        NSColor *color = [first[@"completed"] boolValue] ? Muted() : Accent();
        DrawText(first[@"title"], NSMakeRect(8, 33, self.bounds.size.width - 14, 16), 10, NSFontWeightRegular, color, NSTextAlignmentLeft);
        if (self.tasks.count > 1) DrawText([NSString stringWithFormat:@"+%lu", self.tasks.count - 1], NSMakeRect(self.bounds.size.width - 33, 8, 26, 16), 9, NSFontWeightMedium, Accent(), NSTextAlignmentRight);
    }
}
@end

@interface MonthView : Surface
@property NSDate *month;
@property NSDate *selection;
@property NSArray<NSDictionary *> *tasks;
@property BOOL compact;
@property(copy) void (^onSelect)(NSDate *date);
@property(copy) void (^onMonthChange)(NSDate *date);
- (void)reload;
@end
@implementation MonthView
- (void)reload {
    Clear(self); CGFloat w = self.bounds.size.width;
    Put(self, Text(DDLFormatDate(self.month, @"yyyy 年 M 月"), self.compact ? 12 : 17, NSFontWeightSemibold, Ink()), 14, 13, w - 139, 25);
    ActionButton *today = Button(@"今天", self, @selector(goToday:), 3); today.font = [NSFont systemFontOfSize:10]; Put(self, today, w - 123, 10, 43, 28);
    ActionButton *prev = Button(@"‹", self, @selector(changeMonth:), 3); prev.tag = -1; prev.font = [NSFont systemFontOfSize:22]; prev.accessibilityLabel = @"上个月";
    ActionButton *next = Button(@"›", self, @selector(changeMonth:), 3); next.tag = 1; next.font = [NSFont systemFontOfSize:22]; next.accessibilityLabel = @"下个月";
    Put(self, prev, w - 77, 9, 32, 30); Put(self, next, w - 40, 9, 32, 30);
    NSArray *weekdays = @[@"一", @"二", @"三", @"四", @"五", @"六", @"日"];
    CGFloat cellW = (w - 16) / 7, top = self.compact ? 66 : 76, cellH = (self.bounds.size.height - top - 8) / 6;
    for (NSInteger i = 0; i < 7; i++) {
        NSTextField *label = Text(weekdays[i], 10, NSFontWeightMedium, Muted()); label.alignment = NSTextAlignmentCenter;
        Put(self, label, 8 + i * cellW, top - 24, cellW, 18);
    }
    NSCalendar *calendar = Cal(); NSDate *start;
    NSDictionary *tasksByDay = DDLTasksByDay(self.tasks, calendar);
    [calendar rangeOfUnit:NSCalendarUnitMonth startDate:&start interval:NULL forDate:self.month];
    NSInteger offset = ([calendar component:NSCalendarUnitWeekday fromDate:start] + 5) % 7;
    for (NSInteger i = 0; i < 42; i++) {
        NSDate *date = [calendar dateByAddingUnit:NSCalendarUnitDay value:i - offset toDate:start options:0];
        DayButton *b = [[DayButton alloc] initWithFrame:NSZeroRect]; b.date = date; b.bordered = NO; b.title = DDLFormatDate(date, @"M月d日");
        b.inMonth = [calendar component:NSCalendarUnitMonth fromDate:date] == [calendar component:NSCalendarUnitMonth fromDate:self.month];
        b.chosen = [calendar isDate:date inSameDayAsDate:self.selection]; b.today = [calendar isDateInToday:date]; b.compact = self.compact;
        b.tasks = tasksByDay[[calendar startOfDayForDate:date]] ?: @[];
        b.target = self; b.action = @selector(selectDay:);
        b.toolTip = [NSString stringWithFormat:@"%@ · %lu 项", DDLFormatDate(date, @"yyyy年M月d日 EEEE"), b.tasks.count]; b.accessibilityLabel = b.toolTip;
        Put(self, b, 8 + (i % 7) * cellW, top + (i / 7) * cellH, cellW, cellH);
    }
}
- (void)changeMonth:(NSButton *)sender { self.month = [Cal() dateByAddingUnit:NSCalendarUnitMonth value:sender.tag toDate:self.month options:0]; [self reload]; if (self.onMonthChange) self.onMonthChange(self.month); }
- (void)goToday:(id)sender { self.month = NSDate.date; self.selection = NSDate.date; [self reload]; if (self.onSelect) self.onSelect(self.selection); }
- (void)selectDay:(DayButton *)sender { self.selection = sender.date; self.month = sender.date; [self reload]; if (self.onSelect) self.onSelect(sender.date); }
@end

// Selectable rows keep completion/edit buttons independent from selection.
@interface TaskSelectionRow : Surface
@property(copy) void (^onSelect)(void);
@property(copy) void (^onClose)(void);
@property(copy) void (^onMove)(NSInteger direction);
@end
@implementation TaskSelectionRow
- (BOOL)acceptsFirstResponder { return YES; }
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit=[super hitTest:point];
    return [hit isKindOfClass:NSTextField.class] && ![(NSTextField *)hit isSelectable] ? self:hit;
}
- (void)mouseDown:(NSEvent *)event { if(self.onSelect)self.onSelect(); }
- (void)keyDown:(NSEvent *)event {
    if(event.keyCode==53){if(self.onClose)self.onClose();}
    else if(event.keyCode==125 || event.keyCode==126){if(self.onMove)self.onMove(event.keyCode==125 ? 1:-1);}
    else if(event.keyCode==36 || event.keyCode==49){if(self.onSelect)self.onSelect();}
    else [super keyDown:event];
}
@end
@interface TaskDetailsText : PastelNotesView
@property(copy) void (^onClose)(void);
@end
@implementation TaskDetailsText
- (void)cancelOperation:(id)sender {if(self.onClose)self.onClose();}
@end

@class AppDelegate;

@interface CallbackButton : ActionButton
@property(copy) void (^onClick)(void);
@end
@implementation CallbackButton
- (instancetype)initWithFrame:(NSRect)frame { if ((self = [super initWithFrame:frame])) { self.target = self; self.action = @selector(invoke:); } return self; }
- (void)invoke:(id)sender { if (self.onClick) self.onClick(); }
@end

static NSColor *EventColor(NSDictionary *task) {
    if ([task[@"completed"] boolValue]) return Adaptive(0x568369, 0xA6D5B6);
    return [task[@"due"] timeIntervalSinceNow] < 0 ? Adaptive(0xB86154, 0xEFACA0) : Accent();
}
static NSColor *EventFill(NSDictionary *task) {
    if ([task[@"completed"] boolValue]) return Adaptive(0xEAF2EB, 0x2C4336);
    return [task[@"due"] timeIntervalSinceNow] < 0 ? Adaptive(0xF9EBE6, 0x49332E) : Tint();
}

@interface CalendarTaskButton : NSButton
@property NSDictionary *task;
@property(copy) void (^onClick)(void);
@end
@implementation CalendarTaskButton
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)frame { if ((self = [super initWithFrame:frame])) { self.bordered = NO; self.target = self; self.action = @selector(invoke:); } return self; }
- (void)invoke:(id)sender { if (self.onClick) self.onClick(); }
- (void)drawRect:(NSRect)rect {
    BOOL done = [self.task[@"completed"] boolValue]; NSColor *ink = EventColor(self.task);
    [[[NSGradient alloc] initWithStartingColor:EventFill(self.task) endingColor:Card()] drawInBezierPath:[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0, 1) xRadius:5 yRadius:5] angle:-70];
    CGFloat textY = (self.bounds.size.height - 16) / 2;
    DrawText(done ? @"✓" : ([self.task[@"due"] timeIntervalSinceNow] < 0 ? @"!" : @"○"), NSMakeRect(5, textY, 15, 16), 11, NSFontWeightSemibold, ink, NSTextAlignmentCenter);
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new]; style.lineBreakMode = NSLineBreakByTruncatingTail;
    NSMutableDictionary *attributes = [@{NSFontAttributeName:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium], NSForegroundColorAttributeName:ink, NSParagraphStyleAttributeName:style} mutableCopy];
    if (done) attributes[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
    [self.task[@"title"] drawInRect:NSMakeRect(23, textY, self.bounds.size.width - 28, 16) withAttributes:attributes];
    if (self.highlighted) { [ink setStroke]; [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 2) xRadius:4 yRadius:4] stroke]; }
}
@end

@interface CalendarDayCell : Surface
@property NSDate *date;
@property BOOL inMonth;
@property BOOL weekend;
@property BOOL hovered;
@property NSTrackingArea *hoverArea;
- (void)syncHoverAtWindowPoint:(NSPoint)point;
@end
@implementation CalendarDayCell
- (void)updateTrackingAreas {
    if (self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect) owner:self userInfo:nil];
    [self addTrackingArea:self.hoverArea]; [super updateTrackingAreas];
}
- (void)syncHoverAtWindowPoint:(NSPoint)point {
    BOOL inside = self.window && NSPointInRect([self convertPoint:point fromView:nil], NSIntersectionRect(self.bounds, self.visibleRect));
    if (self.hovered == inside) return;
    self.hovered = inside; self.needsDisplay = YES;
}
- (void)mouseEntered:(NSEvent *)event { [self syncHoverAtWindowPoint:event.locationInWindow]; }
- (void)mouseExited:(NSEvent *)event { [self syncHoverAtWindowPoint:event.locationInWindow]; }
- (void)drawRect:(NSRect)dirtyRect {
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.5, 0.5) xRadius:self.radius yRadius:self.radius];
    NSColor *start = self.hovered ? [self.fill blendedColorWithFraction:0.14 ofColor:Emphasis()] : self.fill;
    NSColor *end = self.hovered ? [self.gradientEnd blendedColorWithFraction:0.14 ofColor:Emphasis()] : self.gradientEnd;
    [[[NSGradient alloc] initWithStartingColor:start endingColor:end] drawInBezierPath:path angle:-70];
    [self.stroke setStroke]; [path stroke];
}
@end

static void ConfigureCalendarCell(CalendarDayCell *cell, BOOL selected) {
    if (selected) { cell.fill = Emphasis(); cell.gradientEnd = Tint(); cell.stroke = Accent(); }
    else if (!cell.inMonth) { cell.fill = [Panel() blendedColorWithFraction:0.48 ofColor:Line()]; cell.gradientEnd = [Panel() blendedColorWithFraction:0.24 ofColor:Line()]; cell.stroke = Line(); }
    else if (cell.weekend) { cell.fill = [Card() blendedColorWithFraction:0.22 ofColor:Panel()]; cell.gradientEnd = Panel(); cell.stroke = Line(); }
    else { cell.fill = Card(); cell.gradientEnd = Canvas(); cell.stroke = Line(); }
    cell.needsDisplay = YES;
}

@interface OverviewGrid : Surface
@property NSDate *month;
@property NSDate *selection;
@property NSDictionary<NSDate *, NSArray<NSDictionary *> *> *tasksByDay;
- (void)updateSelection:(NSDate *)selection;
- (void)refreshHoverAtWindowPoint:(NSPoint)point;
@property(copy) void (^onSelect)(NSDate *date, NSString *taskID);
- (void)reload;
@end
@implementation OverviewGrid
- (void)refreshHoverAtWindowPoint:(NSPoint)point {
    for (NSView *view in self.subviews) if ([view isKindOfClass:CalendarDayCell.class]) [(CalendarDayCell *)view syncHoverAtWindowPoint:point];
}
- (void)updateSelection:(NSDate *)selection {
    NSCalendar *calendar = Cal();
    if ([calendar isDate:self.selection inSameDayAsDate:selection]) return;
    self.selection = selection;
    for (NSView *view in self.subviews) {
        if (![view isKindOfClass:CalendarDayCell.class]) continue;
        CalendarDayCell *cell = (CalendarDayCell *)view;
        BOOL selected = [calendar isDate:cell.date inSameDayAsDate:selection];
        ConfigureCalendarCell(cell, selected);
    }
}
- (void)reload {
    Clear(self);
    NSCalendar *calendar = Cal();
    NSArray<NSDate *> *dates = DDLMonthGrid(self.month, calendar);
    NSInteger rows = dates.count / 7;
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat cellW = (width - 16) / 7, cellH = (height - 42) / rows;
    NSArray *weekdays = @[@"周一", @"周二", @"周三", @"周四", @"周五", @"周六", @"周日"];
    for (NSInteger i = 0; i < 7; i++) {
        NSTextField *weekday = Text(weekdays[i], 11, NSFontWeightMedium, Muted());
        Put(self, weekday, 21 + i * cellW, 12, cellW - 22, 18);
    }
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < (NSInteger)dates.count; i++) {
        NSDate *date = dates[i];
        BOOL inMonth = [calendar isDate:date equalToDate:self.month toUnitGranularity:NSCalendarUnitMonth];
        BOOL selected = [calendar isDate:date inSameDayAsDate:self.selection];
        BOOL today = [calendar isDateInToday:date];
        NSArray *tasks = inMonth ? (self.tasksByDay[[calendar startOfDayForDate:date]] ?: @[]) : @[];
        CalendarDayCell *cell = [CalendarDayCell new]; cell.date = date; cell.inMonth = inMonth; cell.weekend = (i % 7) >= 5; cell.radius = 9;
        ConfigureCalendarCell(cell, selected);
        Put(self, cell, 8 + (i % 7) * cellW + 2, 36 + (i / 7) * cellH + 2, cellW - 4, cellH - 4);
        CallbackButton *hit = [[CallbackButton alloc] initWithFrame:cell.bounds]; hit.title = @""; hit.tone = 3; hit.allowsHoverFill = NO; hit.accessibilityLabel = [NSString stringWithFormat:@"%@，%lu 项任务", DDLFormatDate(date, @"yyyy年M月d日 EEEE"), tasks.count]; hit.onClick = ^{ if (weakSelf.onSelect) weakSelf.onSelect(date, nil); }; [cell addSubview:hit];
        CallbackButton *number = [[CallbackButton alloc] initWithFrame:NSZeroRect]; number.title = DDLFormatDate(date, @"d"); number.tone = today ? 1 : 3; number.allowsHoverFill = NO; number.font = [NSFont systemFontOfSize:12]; number.onClick = hit.onClick; number.accessibilityLabel = hit.accessibilityLabel;
        Put(cell, number, 6, 4, 40, 27); if (!inMonth) number.alphaValue = 0.45;
        if (tasks.count) {
            NSInteger done = 0; for (NSDictionary *t in tasks) if ([t[@"completed"] boolValue]) done++;
            NSTextField *count = Text([NSString stringWithFormat:@"%ld/%lu", (long)done, tasks.count], 9, NSFontWeightMedium, Muted()); count.alignment = NSTextAlignmentRight; count.toolTip = @"已完成 / 当天任务数";
            Put(cell, count, cellW - 48, 11, 32, 15);
        }
        CGFloat eventHeight = cellH < 90 ? 20 : 23, step = eventHeight + 2;
        NSInteger capacity = MAX(1, (NSInteger)((cellH - 38) / step));
        NSInteger shown = MIN((NSInteger)tasks.count, (NSInteger)tasks.count > capacity ? MAX(1, (NSInteger)((cellH - 56) / step)) : capacity);
        for (NSInteger j = 0; j < shown; j++) {
            NSDictionary *task = tasks[j]; CalendarTaskButton *event = [[CalendarTaskButton alloc] initWithFrame:NSZeroRect]; event.task = task; event.title = task[@"title"];
            NSString *state = [task[@"completed"] boolValue] ? @"已完成" : ([task[@"due"] timeIntervalSinceNow] < 0 ? @"已逾期" : @"待完成");
            event.accessibilityLabel = [NSString stringWithFormat:@"%@：%@，%@", state, task[@"title"], DDLFormatDate(task[@"due"], @"M月d日 HH:mm")];
            event.toolTip = [NSString stringWithFormat:@"%@ · %@\n[%@] %@\n点击查看详情", state, task[@"title"], task[@"subject"], DDLFormatDate(task[@"due"], @"yyyy-MM-dd HH:mm")];
            event.onClick = ^{ if (weakSelf.onSelect) weakSelf.onSelect(date, task[@"id"]); };
            Put(cell, event, 6, 32 + j * step, cellW - 16, eventHeight);
        }
        if ((NSInteger)tasks.count > shown) {
            CallbackButton *more = [[CallbackButton alloc] initWithFrame:NSZeroRect]; more.title = [NSString stringWithFormat:@"另 %lu 项 · 查看全部", tasks.count - shown]; more.font = [NSFont systemFontOfSize:9]; more.tone = 3; more.allowsHoverFill = NO; more.onClick = hit.onClick; more.accessibilityLabel = [NSString stringWithFormat:@"%@，查看全部 %lu 项任务", DDLFormatDate(date, @"M月d日"), tasks.count];
            Put(cell, more, 5, 32 + shown * step, cellW - 14, 16);
        }
    }
}
@end

@interface EditorController : NSWindowController <NSTextFieldDelegate>
@property(weak) AppDelegate *appDelegate;
@property NSDictionary *task;
@property NSDictionary *candidate;
@property NSScrollView *sourceScroll;
@property NSPopover *datePopover;
@property NSButton *saveButton;
@property NSButton *nextReviewButton;
@property NSArray<NSString *> *reviewQueue;
@property NSTextField *reviewProgress;
@property NSTextField *titleField;
@property NSTextField *subjectField;
@property NSTextField *deadlineField;
@property NSTextView *notesField;
@property NSTextField *validation;
@property NSTextField *importStatus;
@property NSTextField *deadlineLabel;
@property MonthView *calendar;
@property PastelTextField *timePicker;
@property NSPopUpButton *priority;
@property NSPopUpButton *reminderPreset;
@property NSTextField *reminderField;
@property NSTextField *reminderValidation;
@property NSDate *selectedDate;
@property NSArray *initialValues;
- (BOOL)hasUnsavedChanges;
- (BOOL)saveForExit;
- (instancetype)initWithTask:(NSDictionary *)task owner:(AppDelegate *)owner;
- (void)importClipboard:(id)sender;
- (void)updateReviewProgress;
- (void)saveAndReviewNext:(id)sender;
- (void)deferReview:(id)sender;
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSSearchFieldDelegate, UNUserNotificationCenterDelegate>
@property NSWindow *window;
@property Surface *root;
@property Surface *sidebar;
@property NSScrollView *navigationScroll;
@property BOOL coursesCollapsed;
@property NSString *selectedTaskID;
@property Surface *taskDetails;
@property NSScrollView *taskDetailsScroll;
@property TaskDetailsText *taskDetailsText;
@property NSString *displayedTaskID;
@property NSDictionary *detailsSnapshot;
@property NSString *detailsAppearance;
@property NSSize detailsSize;
@property Surface *header;
@property Surface *document;
@property NSScrollView *scroll;
@property NSSearchField *search;
@property NSSegmentedControl *calendarStatus;
@property NSScrollView *calendarScroll;
@property Surface *calendarDocument;
@property NSDate *calendarBaseMonth;
@property BOOL calendarNeedsCenter;
@property CGFloat calendarSectionHeight;
@property NSPopUpButton *yearPicker;
@property NSPopUpButton *monthPicker;
@property NSTextField *calendarMonthTitle;
@property NSTextField *calendarProgressText;
@property Surface *agenda;
@property NSScrollView *agendaScroll;
@property Surface *agendaDocument;
@property NSString *focusedTaskID;
@property NSPopUpButton *sortMenu;
@property NSPopUpButton *taskFilter;
@property NSInteger page;
@property NSMutableDictionary *pageStates;
@property NSMutableArray<NSMutableDictionary *> *tasks;
@property NSUndoManager *taskUndo;
@property NSStatusItem *statusItem;
@property EditorController *editor;
@property SSCourseController *courseWindow;
@property SSUpdateController *updates;
@property SSExitCoordinator *exitCoordinator;
@property AMSettingsController *settingsController;
@property NSWindow *settingsWindow;
@property NSArray<NSDictionary *> *automaticBatch;
- (BOOL)replaceTasks:(NSArray *)tasks action:(NSString *)action error:(NSError **)error;
- (NSString *)saveReviewItems:(NSArray *)items automatic:(BOOL)automatic;
@property NSInteger filter;
@property BOOL calendarMode;
@property NSDate *month;
@property NSDate *selectedDay;
@property NSString *query;
@property NSString *notice;
@property NSString *notificationStatus;
@property NSString *notificationError;
@property NSInteger authorization;
@property NSInteger scheduledCount;
@property NSInteger notificationGeneration;
@property AMReminderScheduler *reminderScheduler;
@property BOOL preview;
@property BOOL loading;
@property BOOL taskStoreBlocked;
@property BOOL renderBusy;
@property BOOL taskScrollRendering;
@property NSInteger taskScrollBucket;
@property NSTimer *ticker;
@property NSTimer *searchTimer;
@property NSArray<NSDictionary *> *overviewSnapshot;
@property NSDate *overviewBaseMonth;
@property NSString *overviewTimeZone;
@property NSSize overviewSize;
@property NSInteger overviewMinute;
- (void)render;
- (BOOL)commitTask:(NSDictionary *)task originalID:(NSString *)identifier;
- (void)closeEditor;
- (void)editTask:(id)sender;
- (void)deleteTask:(id)sender;
- (void)restoreTask:(id)sender;
- (void)purgeTask:(id)sender;
- (void)addTask:(id)sender;
- (void)importClipboard:(id)sender;
- (void)openCourses:(id)sender;
- (void)navigate:(id)sender;
- (void)refreshAppearance;
- (void)renderDashboard;
- (void)reviewGitHubCandidate:(NSDictionary *)candidate;
- (void)continueReviewQueue:(NSArray<NSString *> *)queue after:(NSString *)identifier;
- (void)showWindow;
- (void)refreshReminders;
- (void)refreshPermission;
- (void)updateCalendarHeaderState;
- (void)scrollCalendarToMonth:(NSDate *)targetMonth animated:(BOOL)animated;
@end

@implementation EditorController
- (instancetype)initWithTask:(NSDictionary *)task owner:(AppDelegate *)owner {
    DDLFormPanel *panel = [[DDLFormPanel alloc] initWithContentRect:NSMakeRect(0, 0, 680, 580) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:panel])) {
        self.appDelegate = owner; self.task = task; self.candidate = task[@"_reviewCandidate"];
        panel.title = self.candidate ? ([task[@"_existing"] boolValue] ? @"审核更新" : @"审核作业") : (task ? @"编辑任务" : @"新建任务"); panel.releasedWhenClosed = NO;
        Surface *root = Box(Canvas(), 0); root.frame = NSMakeRect(0, 0, 680, 580); panel.contentView = root;
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 680, 504)]; scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = YES; scroll.drawsBackground = NO;
        Surface *body = Box(Canvas(), 0); scroll.documentView = body; [root addSubview:scroll]; CGFloat y = 24;
        Put(body, Text(panel.title, 23, NSFontWeightSemibold, Ink()), 24, y, 632, 32); y += 48;
        if (self.candidate) { self.reviewProgress = Text(@"", 12, NSFontWeightRegular, Muted()); Put(body, self.reviewProgress, 416, 30, 240, 24); }
        self.importStatus = Text(@"", 12, NSFontWeightRegular, Muted());
        if (!task) {
            ActionButton *paste = Button(@"粘贴并识别", self, @selector(importClipboard:), 2); Put(body, paste, 24, y, 152, 36);
            ActionButton *image = Button(@"选择截图…", self, @selector(chooseScreenshot:), 2); Put(body, image, 184, y, 152, 36); y += 44;
        }
        Put(body, self.importStatus, 24, y, 632, 24); if (!task) y += 32; else self.importStatus.hidden = YES;
        Put(body, Text(@"任务信息", 15, NSFontWeightSemibold, Ink()), 24, y, 632, 24); y += 32;
        Put(body, Text(@"任务名称", 12, NSFontWeightMedium, Muted()), 24, y, 632, 20); y += 24;
        self.titleField = [[PastelTextField alloc] initWithFrame:NSZeroRect]; self.titleField.stringValue = task[@"title"] ?: @""; self.titleField.placeholderString = @"例如：完成物理第四次作业"; Put(body, self.titleField, 24, y, 632, 36); y += 48;
        Put(body, Text(@"课程 / 分类", 12, NSFontWeightMedium, Muted()), 24, y, 400, 20); Put(body, Text(@"优先级", 12, NSFontWeightMedium, Muted()), 448, y, 208, 20); y += 24;
        self.subjectField = [[PastelTextField alloc] initWithFrame:NSZeroRect]; self.subjectField.stringValue = task[@"subject"] ?: @""; self.subjectField.placeholderString = @"选填"; Put(body, self.subjectField, 24, y, 408, 36);
        self.priority = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.priority addItemsWithTitles:@[@"普通", @"重要", @"紧急"]]; [self.priority selectItemAtIndex:[task[@"priority"] integerValue]]; Put(body, self.priority, 448, y, 208, 36); y += 56;
        if (self.candidate) {
            Put(body, Text(@"老师原文", 15, NSFontWeightSemibold, Ink()), 24, y, 632, 24); y += 32;
            NSString *location = [NSString stringWithFormat:@"%@ · %@:%@", self.candidate[@"repository"], self.candidate[@"path"], self.candidate[@"line"]];
            NSTextField *label = Text(location, 12, NSFontWeightRegular, Muted()); label.toolTip = location; Put(body, label, 24, y, 632, 24); y += 32;
            self.sourceScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24, y, 632, 104)]; self.sourceScroll.hasVerticalScroller = YES; self.sourceScroll.autohidesScrollers = YES;
            NSTextView *source = [[PastelNotesView alloc] initWithFrame:NSMakeRect(0, 0, 612, 104)]; source.editable = NO; source.richText = NO; source.autoresizingMask = NSViewWidthSizable; source.textContainer.widthTracksTextView = YES; source.font = [NSFont systemFontOfSize:13]; source.textColor = Ink(); source.backgroundColor = Card(); source.textContainerInset = NSMakeSize(10, 10); source.string = self.candidate[@"snippet"] ?: @""; ThemeEditor(source); self.sourceScroll.documentView = source; [body addSubview:self.sourceScroll]; y += 120;
            NSString *hint = self.candidate[@"deadlineText"] ? [NSString stringWithFormat:@"老师写的是“%@”，请依据布置时间确认具体日期。", self.candidate[@"deadlineText"]] : ([self.candidate[@"needsTime"] boolValue] ? @"老师未写明时间，请补全具体截止时间。" : ([self.candidate[@"needsDate"] boolValue] ? @"日期不完整，请确认年份、日期和时间。" : @"请核对老师原文中的日期和时间。"));
            NSTextField *help = Text(hint, 12, NSFontWeightRegular, Muted()); help.toolTip = hint; Put(body, help, 24, y, 632, 24); y += 40;
            if ([self.candidate[@"warnings"] count]) {
                NSString *warning = [self.candidate[@"warnings"] componentsJoinedByString:@"；"];
                NSTextField *label = Text(warning, 12, NSFontWeightRegular, NSColor.systemOrangeColor); label.toolTip = warning; Put(body, label, 24, y, 632, 28); y += 36;
            }
            if (self.candidate[@"suggestedDue"] && self.candidate[@"dateBasis"]) {
                NSString *commit = self.candidate[@"dateBasis"][@"commit"];
                NSString *basis = [NSString stringWithFormat:@"建议 %@ · 截止语句提交于 %@（%@）", [self formatTeacherDate:self.candidate[@"suggestedDue"]], [self formatTeacherDate:self.candidate[@"dateBasis"][@"date"]], [commit substringToIndex:MIN((NSUInteger)7, commit.length)]];
                NSTextField *label = Text(basis, 12, NSFontWeightRegular, Muted()); label.toolTip = basis; Put(body, label, 24, y, 632, 28); y += 36;
            }
        }
        Put(body, Text(@"截止时间", 15, NSFontWeightSemibold, Ink()), 24, y, 632, 24); y += 32;
        self.deadlineLabel = Text(@"作业 DDL", 12, NSFontWeightMedium, Muted()); Put(body, self.deadlineLabel, 24, y, 632, 20); y += 24;
        self.selectedDate = task[@"due"] ?: DDLParseDate(@"明天 23:59", NSDate.date, Cal());
        self.deadlineField = [[PastelTextField alloc] initWithFrame:NSZeroRect]; self.deadlineField.delegate = self; self.deadlineField.stringValue = self.candidate && !task[@"due"] ? (self.candidate[@"dateOnly"] ?: @"") : [self formatTeacherDate:self.selectedDate]; self.deadlineField.placeholderString = @"明天 20:00 / 2026-10-11 21:00"; Put(body, self.deadlineField, 24, y, 496, 36);
        ActionButton *calendarButton = Button(@"选日期", self, @selector(showDatePicker:), 2); calendarButton.symbol = @"calendar"; Put(body, calendarButton, 536, y, 120, 36); y += 48;
        self.calendar = MonthView.new; self.calendar.fill = Card(); self.calendar.stroke = Line(); self.calendar.radius = 10; self.calendar.compact = YES; self.calendar.month = self.selectedDate; self.calendar.selection = self.selectedDate; self.calendar.tasks = @[]; self.calendar.frame = NSMakeRect(0, 0, 312, 288); [self.calendar reload];
        __weak typeof(self) weakSelf = self; panel.onConfirm = ^{ if (weakSelf.candidate) [weakSelf saveAndReviewNext:nil]; else [weakSelf save:nil]; }; panel.onCancel = ^{ [weakSelf cancel:nil]; }; self.calendar.onSelect = ^(NSDate *date) { [weakSelf chooseDate:date]; [weakSelf.datePopover close]; };
        self.timePicker = [[PastelTextField alloc] initWithFrame:NSZeroRect]; self.timePicker.delegate = self; self.timePicker.stringValue = [self timeString:self.selectedDate]; self.timePicker.accessibilityLabel = @"具体时间，24 小时制"; Put(body, self.timePicker, 24, y, 96, 36);
        NSPopUpButton *quickTime = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [quickTime addItemsWithTitles:@[@"常用时间", @"09:00", @"12:00", @"18:00", @"20:00", @"22:00", @"23:59"]]; quickTime.target = self; quickTime.action = @selector(quickTime:); Put(body, quickTime, 136, y, 144, 36);
        for (NSInteger i = 0; i < 3; i++) { ActionButton *day = Button(@[@"今天", @"明天", @"一周后"][i], self, @selector(quickDay:), 2); Put(body, day, 296 + i * 120, y, 112, 36); } y += 56;
        Put(body, Text(@"提醒", 15, NSFontWeightSemibold, Ink()), 24, y, 632, 24); y += 32;
        self.reminderField = [[PastelTextField alloc] initWithFrame:NSZeroRect]; self.reminderField.delegate = self; self.reminderField.placeholderString = @"例如：1天、1小时、到期"; self.reminderField.stringValue = DDLFormatReminderOffsets(task ? DDLReminderOffsetsForTask(task) : DDLDefaultReminderOffsets()); Put(body, self.reminderField, 24, y, 352, 36);
        self.reminderPreset = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.reminderPreset addItemsWithTitles:@[@"常用提醒…", @"7天、3天、1天、1小时、到期", @"提前7天", @"提前3天", @"提前1天", @"提前1小时", @"仅到期", @"不提醒"]]; self.reminderPreset.target = self; self.reminderPreset.action = @selector(reminderPresetChanged:); Put(body, self.reminderPreset, 392, y, 264, 36); y += 44;
        self.reminderValidation = Text(@"", 12, NSFontWeightRegular, Muted()); Put(body, self.reminderValidation, 24, y, 632, 24); y += 40;
        Put(body, Text(@"备注（选填）", 15, NSFontWeightSemibold, Ink()), 24, y, 632, 24); y += 32;
        Surface *notesSurface = Box(Card(), 8); notesSurface.stroke = Line(); Put(body, notesSurface, 24, y, 632, 112);
        NSScrollView *notesScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(4, 4, 624, 104)]; notesScroll.hasVerticalScroller = YES; notesScroll.autohidesScrollers = YES; notesScroll.drawsBackground = NO;
        self.notesField = [[PastelNotesView alloc] initWithFrame:NSMakeRect(0, 0, 604, 104)]; self.notesField.font = [NSFont systemFontOfSize:13]; self.notesField.textColor = Ink(); self.notesField.drawsBackground = NO; self.notesField.textContainerInset = NSMakeSize(8, 8); self.notesField.richText = NO; self.notesField.allowsUndo = YES; self.notesField.string = task[@"notes"] ?: @""; self.notesField.autoresizingMask = NSViewWidthSizable; self.notesField.textContainer.widthTracksTextView = YES; ThemeEditor(self.notesField); notesScroll.documentView = self.notesField; [notesSurface addSubview:notesScroll]; y += 136;
        body.frame = NSMakeRect(0, 0, 680, y);
        self.validation = Text(@"", 12, NSFontWeightRegular, Muted()); Put(root, self.validation, 24, 516, 400, 44); self.validation.maximumNumberOfLines = 2; self.validation.lineBreakMode = NSLineBreakByWordWrapping;
        ActionButton *cancel = Button(@"取消", self, @selector(cancel:), 3); cancel.keyEquivalent = @"\033"; cancel.keyEquivalentModifierMask = 0; Put(root, cancel, 448, 524, 88, 36);
        self.saveButton = Button(self.candidate ? @"确认并保存" : (task ? @"保存修改" : @"添加任务"), self, @selector(save:), 1); self.saveButton.keyEquivalent = @"\r"; self.saveButton.keyEquivalentModifierMask = 0; Put(root, self.saveButton, 544, 524, 112, 36);
        if (self.candidate) {
            self.validation.frame = NSMakeRect(24, 516, 184, 44); cancel.frame = NSMakeRect(216, 524, 64, 36);
            NSButton *later = Button(@"稍后审核", self, @selector(deferReview:), 2); later.toolTip = @"本轮跳过，仍保留在待审核列表"; Put(root, later, 288, 524, 88, 36);
            self.saveButton.title = @"保存并关闭"; self.saveButton.frame = NSMakeRect(384, 524, 104, 36); self.saveButton.keyEquivalentModifierMask = NSEventModifierFlagCommand; ((ActionButton *)self.saveButton).tone = 2;
            self.nextReviewButton = Button(@"保存并下一项", self, @selector(saveAndReviewNext:), 1); self.nextReviewButton.keyEquivalent = @"\r"; self.nextReviewButton.keyEquivalentModifierMask = 0; Put(root, self.nextReviewButton, 496, 524, 160, 36);
        }
        [self validateReminders]; [self validateDate];
        self.titleField.nextKeyView = self.subjectField; self.subjectField.nextKeyView = self.priority; self.priority.nextKeyView = self.deadlineField;
        self.titleField.accessibilityLabel = @"任务名称"; self.subjectField.accessibilityLabel = @"课程或分类"; self.deadlineField.accessibilityLabel = @"作业截止时间"; self.reminderField.accessibilityLabel = @"提醒时间"; self.notesField.accessibilityLabel = @"我的备注"; panel.initialFirstResponder = self.titleField; panel.defaultButtonCell = self.nextReviewButton ? self.nextReviewButton.cell : self.saveButton.cell; panel.autorecalculatesKeyViewLoop = YES;
        self.initialValues = [self formValues];
    } return self;
}
- (NSArray *)formValues {
    return [[NSArray alloc] initWithArray:@[self.titleField.stringValue ?: @"", self.subjectField.stringValue ?: @"", self.deadlineField.stringValue ?: @"", self.timePicker.stringValue ?: @"", self.notesField.string ?: @"", self.reminderField.stringValue ?: @"", @(self.priority.indexOfSelectedItem)] copyItems:YES];
}
- (BOOL)hasUnsavedChanges { [self.window makeFirstResponder:nil]; return ![self.initialValues isEqual:[self formValues]]; }
- (BOOL)saveForExit { [self save:nil]; return self.appDelegate.editor != self; }
- (void)updateReviewProgress { self.reviewProgress.stringValue = [NSString stringWithFormat:@"本轮剩余 %lu 项", (unsigned long)self.reviewQueue.count]; }
- (void)saveAndReviewNext:(id)sender {
    NSArray *queue = self.reviewQueue; NSString *identifier = self.candidate[@"id"]; AppDelegate *owner = self.appDelegate;
    [self save:nil]; if (owner.editor == self) return;
    [owner continueReviewQueue:queue after:identifier];
}
- (void)deferReview:(id)sender {
    if (self.hasUnsavedChanges) {
        NSAlert *alert = NSAlert.new; alert.messageText = @"暂缓审核这项作业？"; alert.informativeText = @"当前未保存的修改将放弃，作业仍保留在待审核列表。";
        [alert addButtonWithTitle:@"返回继续"]; [alert addButtonWithTitle:@"放弃修改并稍后审核"];
        if ([alert runModal] != NSAlertSecondButtonReturn) return;
    }
    NSArray *queue = self.reviewQueue; NSString *identifier = self.candidate[@"id"]; AppDelegate *owner = self.appDelegate;
    [owner closeEditor]; [owner continueReviewQueue:queue after:identifier];
}
- (NSCalendar *)teacherCalendar { NSCalendar *calendar = Cal(); calendar.timeZone = [NSTimeZone timeZoneWithName:self.candidate[@"timeZone"] ?: NSTimeZone.localTimeZone.name] ?: NSTimeZone.localTimeZone; return calendar; }
- (NSString *)formatTeacherDate:(NSDate *)date { NSDateFormatter *formatter = NSDateFormatter.new; formatter.dateFormat = @"yyyy-MM-dd HH:mm"; formatter.timeZone = self.teacherCalendar.timeZone; return [formatter stringFromDate:date]; }
- (NSString *)timeString:(NSDate *)date { NSDateFormatter *formatter = NSDateFormatter.new; formatter.dateFormat = @"HH:mm"; formatter.timeZone = self.teacherCalendar.timeZone; return [formatter stringFromDate:date]; }
- (void)showDatePicker:(NSButton *)sender { self.datePopover = NSPopover.new; NSViewController *controller = NSViewController.new; controller.view = self.calendar; self.datePopover.contentViewController = controller; self.datePopover.behavior = NSPopoverBehaviorTransient; [self.datePopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMaxY]; }
- (BOOL)validateAssignmentDate {
    if (!self.candidate) return YES;
    NSString *text = [self.deadlineField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSDate *date = [text rangeOfString:@"^20\\d{2}[-/]\\d{1,2}[-/]\\d{1,2}\\s+(?:[01]?\\d|2[0-3]):[0-5]\\d$" options:NSRegularExpressionSearch].location == NSNotFound ? nil : DDLParseDate(text, NSDate.date, self.teacherCalendar);
    if (!date) { self.validation.stringValue = @"请核对原文，填写完整的截止日期和时间。"; self.validation.textColor = NSColor.systemRedColor; return NO; }
    return YES;
}
- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == self.timePicker) { [self timeChanged:self.timePicker]; return; }
    if (notification.object == self.reminderField) { [self validateReminders]; return; }
    NSDate *date = DDLParseDate(self.deadlineField.stringValue, NSDate.date, self.teacherCalendar);
    if (date) { self.selectedDate = date; self.calendar.selection = date; self.calendar.month = date; [self.calendar reload]; self.timePicker.stringValue = [self timeString:date]; }
    [self validateDate];
}
- (void)validateReminders {
    NSArray<NSNumber *> *offsets = DDLParseReminderOffsets(self.reminderField.stringValue);
    if (!offsets) { self.reminderValidation.stringValue = @"格式有误"; self.reminderValidation.textColor = NSColor.systemRedColor; return; }
    self.reminderValidation.stringValue = offsets.count ? [NSString stringWithFormat:@"共 %lu 次提醒", offsets.count] : @"已关闭提醒";
    self.reminderValidation.textColor = offsets.count ? Accent() : Muted();
}
- (void)reminderPresetChanged:(NSPopUpButton *)sender {
    NSArray *values = @[@"", @"7天、3天、1天、1小时、到期", @"7天", @"3天", @"1天", @"1小时", @"到期", @"不提醒"];
    if (sender.indexOfSelectedItem > 0) self.reminderField.stringValue = values[sender.indexOfSelectedItem];
    [self validateReminders]; [sender selectItemAtIndex:0];
}
- (void)validateDate {
    NSDate *date = DDLParseDate(self.deadlineField.stringValue, NSDate.date, self.teacherCalendar);
    if (!date) { self.validation.stringValue = @"请输入有效日期，例如：明天 20:00、下周五、2026-10-01 23:59"; self.validation.textColor = NSColor.systemRedColor; }
    else if (date.timeIntervalSinceNow <= 0) { self.validation.stringValue = @"这个时间已经过去，保存后会标记为逾期；不会补发过去的提醒。"; self.validation.textColor = NSColor.systemOrangeColor; }
    else { self.validation.stringValue = [NSString stringWithFormat:@"%@ · %@", DDLFormatDate(date, @"M月d日 EEEE HH:mm"), DDLRemaining(date, NSDate.date, NO)]; self.validation.textColor = Accent(); }
}
- (void)updateDate:(NSDate *)date {
    if (!date) return; self.selectedDate = date; self.deadlineField.stringValue = [self formatTeacherDate:date]; self.calendar.selection = date; self.calendar.month = date; self.timePicker.stringValue = [self timeString:date]; [self.calendar reload]; [self validateDate];
}
- (void)chooseDate:(NSDate *)date {
    NSDateComponents *time = [self.teacherCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:self.selectedDate];
    [self updateDate:[self.teacherCalendar dateBySettingHour:time.hour minute:time.minute second:0 ofDate:date options:0]];
}
- (NSDate *)parsedTime {
    NSString *value = [self.timePicker.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^([01]?[0-9]|2[0-3]):[0-5][0-9]$" options:0 error:nil];
    if (![pattern numberOfMatchesInString:value options:0 range:NSMakeRange(0, value.length)]) return nil;
    NSArray *parts = [value componentsSeparatedByString:@":"];
    NSDate *base = DDLParseDate(self.deadlineField.stringValue, NSDate.date, self.teacherCalendar);
    return base ? [self.teacherCalendar dateBySettingHour:[parts[0] integerValue] minute:[parts[1] integerValue] second:0 ofDate:base options:0] : nil;
}
- (void)timeChanged:(id)sender {
    NSDate *date = [self parsedTime];
    if (!date) { self.validation.stringValue = @"时间格式：00:00–23:59"; self.validation.textColor = NSColor.systemRedColor; return; }
    // Keep the active field editor and caret intact while typing.
    self.selectedDate = date; self.deadlineField.stringValue = [self formatTeacherDate:date];
    self.calendar.selection = date; self.calendar.month = date; [self.calendar reload]; [self validateDate];
}
- (void)stepTime:(NSButton *)sender {
    NSDate *date = [self parsedTime];
    if (!date) { [self timeChanged:self.timePicker]; return; }
    [self updateDate:[self.teacherCalendar dateByAddingUnit:NSCalendarUnitMinute value:sender.tag toDate:date options:0]];
}
- (void)quickTime:(NSPopUpButton *)sender {
    if (sender.indexOfSelectedItem == 0) return;
    NSDate *base = DDLParseDate(self.deadlineField.stringValue, NSDate.date, self.teacherCalendar);
    if (!base) { [self validateDate]; return; }
    NSArray *parts = [sender.titleOfSelectedItem componentsSeparatedByString:@":"];
    [self updateDate:[self.teacherCalendar dateBySettingHour:[parts[0] integerValue] minute:[parts[1] integerValue] second:0 ofDate:base options:0]];
    [sender selectItemAtIndex:0];
}
- (void)quickDay:(NSButton *)sender {
    NSDate *day = DDLParseDate(sender.title, NSDate.date, Cal());
    [self chooseDate:day];
}
- (void)applyImportedText:(NSString *)text source:(NSString *)source {
    NSDictionary<NSString *, id> *fields = DDLFieldsFromAnnouncement(text, NSDate.date, Cal());
    if (!fields.count) { self.importStatus.stringValue = @"没有识别到文字，请换一张清晰截图。"; self.importStatus.textColor = NSColor.systemRedColor; return; }
    self.titleField.stringValue = fields[@"title"] ?: @"";
    self.subjectField.stringValue = fields[@"subject"] ?: @"";
    NSDate *due = fields[@"due"];
    self.deadlineLabel.stringValue = @"作业 DDL";
    if (due) [self updateDate:due];
    else { self.deadlineField.stringValue = @""; [self validateDate]; }
    self.importStatus.stringValue = due ? [NSString stringWithFormat:@"已识别%@ · 截止时间已填写：%@", source, DDLFormatDate(due, @"M月d日 HH:mm")] : [NSString stringWithFormat:@"已识别%@，但没有找到明确日期；请手动填写截止时间。", source];
    self.importStatus.textColor = due ? Accent() : NSColor.systemOrangeColor;
    [self.window makeFirstResponder:due ? self.titleField : self.deadlineField];
}
- (void)recognizeImage:(NSImage *)image {
    NSData *imageData = image.TIFFRepresentation;
    if (!imageData.length) { self.importStatus.stringValue = @"图片读取失败，请换一张截图。"; self.importStatus.textColor = NSColor.systemRedColor; return; }
    self.importStatus.stringValue = @"正在识别截图中的文字…"; self.importStatus.textColor = Accent();
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSImage *copy = [[NSImage alloc] initWithData:imageData];
            NSError *error = nil;
            NSString *text = DDLOCRTextFromImage(copy, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                EditorController *editor = weakSelf;
                if (!editor || !editor.window.visible) return;
                if (!text.length) { editor.importStatus.stringValue = error ? @"截图识别失败，请尝试更清晰的图片。" : @"截图中没有识别到文字。"; editor.importStatus.textColor = NSColor.systemRedColor; return; }
                [editor applyImportedText:text source:@"截图"];
            });
        }
    });
}
- (void)importClipboard:(id)sender {
    NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
    NSImage *image = [[NSImage alloc] initWithPasteboard:pasteboard];
    if (image) { [self recognizeImage:image]; return; }
    NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
    if (text.length) { [self applyImportedText:text source:@"文字"]; return; }
    self.importStatus.stringValue = @"剪贴板里没有文字或图片。请先在微信中复制消息或截图。";
    self.importStatus.textColor = NSColor.systemRedColor;
}
- (void)chooseScreenshot:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"选择老师通知的截图";
    panel.canChooseDirectories = NO; panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = @[UTTypePNG, UTTypeJPEG, UTTypeHEIC, UTTypeTIFF];
    __weak typeof(self) weakSelf = self;
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !weakSelf) return;
        NSImage *image = [[NSImage alloc] initWithContentsOfURL:panel.URL];
        if (image) [weakSelf recognizeImage:image];
        else { weakSelf.importStatus.stringValue = @"图片读取失败，请选择 PNG、JPEG、HEIC 或 TIFF。"; weakSelf.importStatus.textColor = NSColor.systemRedColor; }
    }];
}
- (void)cancel:(id)sender { [self.appDelegate closeEditor]; }
- (void)focusInput:(NSView *)field { [field scrollRectToVisible:field.bounds]; [self.window makeFirstResponder:field]; }
- (void)save:(id)sender {
    NSString *title = [self.titleField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!title.length) { self.validation.stringValue = @"先写一个任务名称。"; self.validation.textColor = NSColor.systemRedColor; [self focusInput:self.titleField]; return; }
    if (![self validateAssignmentDate]) { [self focusInput:self.deadlineField]; return; }
    NSDate *date = DDLParseDate(self.deadlineField.stringValue, NSDate.date, self.teacherCalendar);
    if (!date) { [self validateDate]; [self focusInput:self.deadlineField]; return; }
    if (![self parsedTime]) { [self timeChanged:self.timePicker]; [self focusInput:self.timePicker]; return; }
    NSArray<NSNumber *> *reminderOffsets = DDLParseReminderOffsets(self.reminderField.stringValue);
    if (!reminderOffsets) { [self validateReminders]; [self focusInput:self.reminderField]; return; }
    NSMutableDictionary *task = self.task ? [self.task mutableCopy] : [@{@"id":NSUUID.UUID.UUIDString, @"completed":@NO, @"archived":@NO} mutableCopy];
    NSString *subject = [self.subjectField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSInteger legacyMode = reminderOffsets.count == 0 ? 4 : ([reminderOffsets isEqual:@[@0]] ? 0 : ([reminderOffsets isEqual:@[@60, @0]] ? 1 : ([reminderOffsets isEqual:@[@1440, @60, @0]] ? 2 : ([reminderOffsets isEqual:@[@4320, @1440, @60, @0]] ? 3 : 2))));
    task[@"title"] = title; task[@"subject"] = subject.length ? subject : @"其他"; task[@"due"] = date; task[@"notes"] = self.notesField.string;if(![self.task[@"notes"] isEqual:task[@"notes"]]){task[@"notesOrigin"]=@"user";task[@"notesUserEdited"]=@YES;} task[@"priority"] = @(self.priority.indexOfSelectedItem); task[@"reminder"] = @(legacyMode); task[@"reminderOffsets"] = reminderOffsets;
    [task removeObjectForKey:@"_reviewCandidate"]; [task removeObjectForKey:@"_existing"];
    if (self.candidate[@"dateBasis"]) task[@"sourceDateBasis"] = self.candidate[@"dateBasis"];
    if (self.candidate) {
        NSDictionary *draft=@{@"title":title,@"subject":task[@"subject"],@"notes":task[@"notes"],@"assignmentDue":date,@"reminderOffsets":reminderOffsets,@"dateConfirmed":@YES};
        NSString *failure=[self.appDelegate saveReviewItems:@[@{@"record":self.candidate,@"draft":draft}] automatic:NO];
        if (failure.length) {self.validation.stringValue=failure;self.validation.textColor=NSColor.systemRedColor;return;}
        [self.appDelegate closeEditor];
    } else if ([self.appDelegate commitTask:task originalID:self.task[@"id"]]) [self.appDelegate closeEditor];
}
@end

static NSView *AMFindButton(NSView *root, SEL action, NSInteger tag, NSString *identifier) {
    for(NSView *view in root.subviews){if([view isKindOfClass:NSButton.class] && ((NSButton *)view).action==action && (identifier ? [view.identifier isEqual:identifier]:view.tag==tag))return view;NSView *nested=AMFindButton(view,action,tag,identifier);if(nested)return nested;}return nil;
}

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.preview = [NSProcessInfo.processInfo.arguments containsObject:@"--preview"];
    // Leave appearance unset so macOS controls light/dark mode.
    self.page = 0; self.pageStates = NSMutableDictionary.dictionary;
    NSApp.applicationIconImage = ThemeIcon();
    if (!self.preview) {
        NSArray *running = [NSRunningApplication runningApplicationsWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
        for (NSRunningApplication *other in running) if (other.processIdentifier != NSProcessInfo.processInfo.processIdentifier) {
            NSAlert *alert = [NSAlert new]; alert.messageText = @"另一个 AM's Homework Helper 正在运行"; alert.informativeText = @"请先退出旧版本或预览窗口，再打开本版，避免两个版本同时保存任务。"; [alert addButtonWithTitle:@"知道了"]; [NSApp activateIgnoringOtherApps:YES]; [alert runModal]; [NSApp terminate:nil]; return;
        }
    }
    self.filter = 0; self.calendarMode = NO; self.query = @""; self.month = NSDate.date; self.selectedDay = NSDate.date; self.notice = @"";
    self.taskUndo = [NSUndoManager new]; self.taskUndo.levelsOfUndo = 30;
    self.notificationStatus = self.preview ? @"演示模式 · 提醒未发送" : @"正在检查通知权限…";
    self.authorization = -1;
    self.tasks = [NSMutableArray array];
    if (self.preview) [self loadPreview];
    else {
        NSError *error=nil;NSArray *stored=SSLoadTasks(&error);
        self.taskStoreBlocked=stored==nil;
        if(stored)[self.tasks addObjectsFromArray:DDLNormalizeTasks(stored)];
        else self.notice=error.localizedDescription;
        SSDiagnostic(@"load",stored ? @"success":@"failed",0);
    }
    self.updates = [[SSUpdateController alloc] initWithPreview:self.preview];
    [self installMenu];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1280, 840) styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView) backing:NSBackingStoreBuffered defer:NO];
    self.window.title = self.preview ? @"AM's Homework Helper · 界面预览" : @"AM's Homework Helper"; self.window.titleVisibility = NSWindowTitleHidden; self.window.titlebarAppearsTransparent = YES;
    self.window.minSize = NSMakeSize(960, 640); self.window.releasedWhenClosed = NO; self.window.delegate = self; self.window.movableByWindowBackground = YES;
    if (self.preview && [NSProcessInfo.processInfo.arguments containsObject:@"--compact"]) [self.window setContentSize:NSMakeSize(960, 640)];
    self.window.backgroundColor = Canvas();
    self.root = GradientBox(Canvas(), Panel(), 0); self.root.frame = NSMakeRect(0, 0, 1280, 840); self.window.contentView = self.root;
    self.taskDetails = Box(Card(), 10); self.taskDetails.stroke = Line(); self.taskDetails.hidden=YES; [self.root addSubview:self.taskDetails];
    self.sidebar = GradientBox(Panel(), Canvas(), 0); [self.root addSubview:self.sidebar];
    self.header = GradientBox(Canvas(), Panel(), 0); [self.root addSubview:self.header];
    self.search = [[NSSearchField alloc] initWithFrame:NSZeroRect]; self.search.placeholderString = @"搜索任务、学科、备注"; self.search.delegate = self; self.search.sendsSearchStringImmediately = YES; self.search.font = [NSFont systemFontOfSize:12]; [self.root addSubview:self.search];
    self.calendarStatus = Segments(@[@"全部", @"待完成", @"已完成"], self, @selector(changeCalendarStatus:)); [self.root addSubview:self.calendarStatus];
    self.sortMenu = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.sortMenu addItemsWithTitles:@[@"按截止时间", @"按优先级"]]; self.sortMenu.target = self; self.sortMenu.action = @selector(sortChanged:); [self.root addSubview:self.sortMenu];
    self.scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; self.scroll.hasVerticalScroller = YES; self.scroll.autohidesScrollers = YES; self.scroll.drawsBackground = NO;
    self.document = GradientBox(Canvas(), Panel(), 0); self.scroll.documentView = self.document; [self.root addSubview:self.scroll];
    self.scroll.contentView.postsBoundsChangedNotifications=YES;[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(taskScrolled:) name:NSViewBoundsDidChangeNotification object:self.scroll.contentView];
    self.calendarScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; self.calendarScroll.hasVerticalScroller = YES; self.calendarScroll.autohidesScrollers = NO; self.calendarScroll.drawsBackground = NO; self.calendarScroll.borderType = NSNoBorder;
    self.calendarDocument = GradientBox(Panel(), Canvas(), 0); self.calendarScroll.documentView = self.calendarDocument; [self.root addSubview:self.calendarScroll]; self.calendarBaseMonth = self.month; self.calendarNeedsCenter = YES;
    self.calendarScroll.contentView.postsBoundsChangedNotifications = YES; [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(calendarScrolled:) name:NSViewBoundsDidChangeNotification object:self.calendarScroll.contentView];
    self.agenda = GradientBox(Panel(), Canvas(), 14); [self.root addSubview:self.agenda];
    self.agendaScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; self.agendaScroll.hasVerticalScroller = YES; self.agendaScroll.autohidesScrollers = YES; self.agendaScroll.drawsBackground = NO;
    self.agendaDocument = Box(NSColor.clearColor, 0); self.agendaScroll.documentView = self.agendaDocument;
    self.taskFilter = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.taskFilter addItemsWithTitles:@[@"待完成", @"今天", @"未来 7 天", @"已完成", @"归档", @"最近删除"]];
    self.taskFilter.target = self; self.taskFilter.action = @selector(changeFilter:); [self.root addSubview:self.taskFilter];
    __weak typeof(self) weakSelf = self;
    self.root.onResize = ^{ [weakSelf layout]; };
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"checklist" accessibilityDescription:@"AM's Homework Helper"];
    self.statusItem.button.imagePosition = NSImageLeft; self.statusItem.button.target = self; self.statusItem.button.action = @selector(statusClick:); [self.statusItem.button sendActionOn:NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp];
    [self layout]; [self.window center]; [self showWindow];
    if (!self.preview) { UNUserNotificationCenter.currentNotificationCenter.delegate = self; [self refreshPermission]; [self refreshReminders]; }
    self.ticker = [NSTimer timerWithTimeInterval:60 target:self selector:@selector(tick:) userInfo:nil repeats:YES]; [NSRunLoop.mainRunLoop addTimer:self.ticker forMode:NSRunLoopCommonModes];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(woke:) name:NSWorkspaceDidWakeNotification object:nil];
    self.courseWindow = [self makeCourseController];
    self.courseWindow.tasksProvider = ^NSArray * { return [weakSelf snapshot]; };
    self.courseWindow.saveReviewItems = ^NSString *(NSArray *items, BOOL automatic) { return [weakSelf saveReviewItems:items automatic:automatic]; };
    self.courseWindow.reviewCandidate = ^(NSDictionary *candidate) { [weakSelf reviewGitHubCandidate:candidate]; };
    self.courseWindow.restoreTaskNotes=^(NSString *identifier){NSButton *button=NSButton.new;button.identifier=identifier;[weakSelf restoreTaskNotes:button];};
    self.courseWindow.editTask = ^(NSString *identifier) { NSMenuItem *item = NSMenuItem.new; item.representedObject = identifier; [weakSelf editTask:item]; };
    self.courseWindow.stateChanged = ^{ [weakSelf renderSidebar]; if(weakSelf.page==4)[weakSelf renderHeader]; if (weakSelf.page == 0) [weakSelf renderTaskContent]; };
    self.exitCoordinator = SSExitCoordinator.new;
    self.exitCoordinator.operationBusy = ^BOOL { return weakSelf.courseWindow.operationBusy; };
    self.exitCoordinator.pauseOperations = ^(BOOL paused) { weakSelf.courseWindow.operationsPaused = paused; };
    self.exitCoordinator.cancelLogin = ^{ [weakSelf.courseWindow cancelPendingLogin]; };
    self.exitCoordinator.resolveEdits = ^BOOL(BOOL updating) { return [weakSelf resolveEditsForExit:updating]; };
    self.exitCoordinator.persist = ^BOOL {
        if (weakSelf.preview) return YES;
        NSError *error = nil; BOOL ok = [weakSelf.courseWindow persistForExit:&error]; // Task edits are already persisted transactionally; never overwrite an unreadable store on exit.
        if (!ok) { weakSelf.notice = @"本机数据保存失败，已暂缓退出与更新。"; [weakSelf render]; }
        return ok;
    };
    self.courseWindow.onboardingNavigation=^(BOOL review){NSButton *route=NSButton.new;route.tag=review ? 3:4;[weakSelf navigate:route];};
    self.courseWindow.operationStateChanged = ^{ [weakSelf.exitCoordinator operationStateChanged]; };
    self.updates.statusChanged = ^(NSString *message) { weakSelf.notice = message; [weakSelf render]; };
    [self.root addSubview:self.courseWindow.view]; self.courseWindow.view.hidden = YES;
    self.root.onAppearanceChange = ^{ [weakSelf refreshAppearance]; };
    if (!self.preview) [self.courseWindow startAutomaticChecks];
    [self layout];
}
- (SSCourseController *)makeCourseController {return [[SSCourseController alloc] initWithPreview:self.preview];}
- (void)refreshAppearance {
    if (!self.window || self.renderBusy) return;
    NSResponder *focus = self.window.firstResponder; NSInteger calendarFocus = focus == self.yearPicker ? 1 : (focus == self.monthPicker ? 2 : 0);
    ActionButton *button = [focus isKindOfClass:ActionButton.class] ? (ActionButton *)focus : nil; NSView *scope = [button isDescendantOf:self.sidebar] ? self.sidebar : ([button isDescendantOf:self.header] ? self.header : nil); SEL action = button.action; NSInteger tag = button.tag;NSString *focusIdentifier=button.identifier;
    self.overviewSnapshot = nil; self.window.backgroundColor = Canvas();
    [self render]; [self.courseWindow refreshPresentation];
    if (calendarFocus) [self.window makeFirstResponder:calendarFocus == 1 ? self.yearPicker : self.monthPicker];
    else if(scope){NSView *replacement=AMFindButton(scope,action,tag,focusIdentifier);if(replacement)[self.window makeFirstResponder:replacement];}
    if (self.editor) { ThemeEditor(self.editor.notesField); if (self.editor.window.firstResponder && [self.editor.window.firstResponder isKindOfClass:NSTextView.class]) ThemeEditor((NSTextView *)self.editor.window.firstResponder); }
}
- (void)loadPreview {
    NSArray *samples = @[
        @[@"数据结构", @"完成二叉树实验报告", @0, @20, @0, @2, @NO, @"整理实验结果，附上运行截图。"],
        @[@"英语", @"阅读论文并完成摘要", @1, @18, @0, @1, @NO, @"重点阅读 Introduction 和 Discussion。"],
        @[@"设计", @"整理作品集第一版", @3, @23, @59, @0, @NO, @"梳理三个最有代表性的项目。"],
        @[@"高等数学", @"提交第六周习题", @0, @23, @59, @1, @NO, @""],
        @[@"生活", @"预约周末的羽毛球场", @2, @12, @0, @0, @NO, @""],
        @[@"计算机网络", @"复习 TCP / IP 协议", @-1, @18, @0, @0, @YES, @""],
        @[@"英语", @"完成课程阅读", @0, @9, @0, @0, @YES, @"已经整理好阅读笔记。"],
        @[@"设计", @"小组方案沟通", @0, @17, @30, @1, @NO, @"带上草图，与大家确认下一步。"],
        @[@"高等数学", @"订正第二章错题", @-3, @21, @0, @0, @YES, @""],
        @[@"写作", @"提交读书心得", @-2, @18, @0, @1, @NO, @"补充最后一段思考。"],
        @[@"计算机网络", @"完成网络实验", @-9, @20, @0, @0, @YES, @""],
        @[@"英语", @"单词与听力复习", @-15, @20, @0, @0, @YES, @""],
        @[@"数据结构", @"完成链表练习", @-18, @23, @59, @0, @YES, @""]
    ];
    for (NSArray *row in samples) {
        NSDate *day = [Cal() dateByAddingUnit:NSCalendarUnitDay value:[row[2] integerValue] toDate:NSDate.date options:0];
        NSDate *due = [Cal() dateBySettingHour:[row[3] integerValue] minute:[row[4] integerValue] second:0 ofDate:day options:0];
        [self.tasks addObject:[@{@"id":NSUUID.UUID.UUIDString, @"subject":row[0], @"title":row[1], @"due":due, @"priority":row[5], @"completed":row[6], @"archived":@NO, @"notes":row[7], @"reminder":@2} mutableCopy]];
    }
}
- (void)installMenu {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new]; [menu addItem:appItem]; NSMenu *app = [[NSMenu alloc] initWithTitle:@"AM's Homework Helper"]; appItem.submenu = app;
    [app addItemWithTitle:@"关于 AM's Homework Helper" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    NSMenuItem *check = [app addItemWithTitle:@"检查更新…" action:@selector(checkForUpdates:) keyEquivalent:@""]; check.target = self.updates;
    NSMenuItem *settings = [app addItemWithTitle:@"设置…" action:@selector(showSettings:) keyEquivalent:@","]; settings.target = self;
    [app addItem:[NSMenuItem separatorItem]]; [app addItemWithTitle:@"隐藏 AM's Homework Helper" action:@selector(hide:) keyEquivalent:@"h"];
    [app addItemWithTitle:@"退出 AM's Homework Helper" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem *fileItem = [NSMenuItem new]; [menu addItem:fileItem]; NSMenu *file = [[NSMenu alloc] initWithTitle:@"任务"]; fileItem.submenu = file;
    NSMenuItem *add = [file addItemWithTitle:@"新建任务" action:@selector(addTask:) keyEquivalent:@"n"]; add.target = self;
    NSMenuItem *courses = [file addItemWithTitle:@"GitHub 课程与作业…" action:@selector(openCourses:) keyEquivalent:@"g"]; courses.target = self;
    NSMenuItem *import = [file addItemWithTitle:@"粘贴并识别 DDL" action:@selector(importClipboard:) keyEquivalent:@"v"]; import.target = self; import.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    NSMenuItem *search = [file addItemWithTitle:@"搜索任务" action:@selector(focusSearch:) keyEquivalent:@"f"]; search.target = self;
    NSMenuItem *overview = [file addItemWithTitle:@"总览" action:@selector(navigate:) keyEquivalent:@"1"]; overview.target = self; overview.tag = 0;
    NSMenuItem *calendar = [file addItemWithTitle:@"日历" action:@selector(openCalendar:) keyEquivalent:@"2"]; calendar.target = self;
    NSMenuItem *list = [file addItemWithTitle:@"任务" action:@selector(openList:) keyEquivalent:@"3"]; list.target = self;
    NSMenuItem *inbox = [file addItemWithTitle:@"待审核作业" action:@selector(navigate:) keyEquivalent:@"4"]; inbox.target = self; inbox.tag = 3;
    NSMenuItem *export = [file addItemWithTitle:@"导出任务备份…" action:@selector(exportTasks:) keyEquivalent:@""]; export.target = self;
    NSMenuItem *recovery=[file addItemWithTitle:@"恢复任务…" action:@selector(recoverTasks:) keyEquivalent:@""];recovery.target=self;
    NSMenuItem *diagnostics=[file addItemWithTitle:@"诊断与反馈…" action:@selector(showDiagnostics:) keyEquivalent:@""];diagnostics.target=self;
    NSMenuItem *restore = [file addItemWithTitle:@"导入任务备份…" action:@selector(importTasks:) keyEquivalent:@""]; restore.target = self;
    NSMenuItem *batch = [file addItemWithTitle:@"完成当前任务列表…" action:@selector(completeVisibleTasks:) keyEquivalent:@""]; batch.target = self;
    NSMenuItem *undoImport = [file addItemWithTitle:@"撤销上次自动加入" action:@selector(undoAutomaticImport:) keyEquivalent:@""]; undoImport.target = self;
    [file addItemWithTitle:@"关闭窗口" action:@selector(performClose:) keyEquivalent:@"w"];
    NSMenuItem *editItem = [NSMenuItem new]; [menu addItem:editItem]; NSMenu *edit = [[NSMenu alloc] initWithTitle:@"编辑"]; editItem.submenu = edit;
    [edit addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [edit addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"z"]; redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [edit addItem:[NSMenuItem separatorItem]];
    [edit addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"]; [edit addItemWithTitle:@"复制" action:@selector(copy:) keyEquivalent:@"c"]; [edit addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"]; [edit addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    NSMenuItem *windowItem = [NSMenuItem new]; [menu addItem:windowItem]; NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"窗口"]; windowItem.submenu = windowMenu;
    NSMenuItem *show = [windowMenu addItemWithTitle:@"显示 AM's Homework Helper" action:@selector(showMain:) keyEquivalent:@"0"]; show.target = self;
    [windowMenu addItemWithTitle:@"最小化" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    NSApp.mainMenu = menu; NSApp.windowsMenu = windowMenu;
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window { return self.taskUndo; }
- (BOOL)windowShouldClose:(NSWindow *)window {
    if (window==self.settingsWindow) { if (![self.settingsController resolveUnsavedChanges]) return NO; [self.window endSheet:window]; [window orderOut:nil]; self.settingsWindow=nil; self.settingsController=nil; return NO; }
    return YES;
}
- (void)undo:(id)sender { [self.taskUndo undo]; }
- (void)redo:(id)sender { [self.taskUndo redo]; }
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(undo:)) { item.title = self.taskUndo.undoMenuItemTitle; return self.taskUndo.canUndo; }
    if (item.action == @selector(redo:)) { item.title = self.taskUndo.redoMenuItemTitle; return self.taskUndo.canRedo; }
    return YES;
}
- (void)layout {
    if (!self.scroll) return;
    CGFloat w = NSWidth(self.root.bounds), h = NSHeight(self.root.bounds), x = 216, content = w - x - 24;
    self.sidebar.hidden = NO; self.sidebar.frame = NSMakeRect(0, 0, 192, h);
    self.header.frame = NSMakeRect(x, 48, content, self.page>=3 ? 64:88);
    BOOL coursePage = self.page >= 3;
    self.scroll.hidden = coursePage || self.calendarMode;
    self.calendarScroll.hidden = coursePage || !self.calendarMode;
    self.agenda.hidden = coursePage || !self.calendarMode;
    self.calendarStatus.hidden = coursePage || !self.calendarMode;
    self.search.hidden = coursePage; self.sortMenu.hidden = self.page != 2;
    self.taskFilter.hidden = self.page != 2;
    self.search.frame = NSMakeRect(w - 280, 140, 256, 32);
    self.taskFilter.frame = NSMakeRect(x, 140, 160, 32); self.sortMenu.frame = NSMakeRect(x + 176, 140, 152, 32);
    self.calendarStatus.frame = NSMakeRect(x, 140, 240, 32);
    [self layoutTaskArea];
    self.courseWindow.view.hidden = !coursePage;
    if (self.courseWindow) { self.courseWindow.view.frame = NSMakeRect(x, 112, content, h - 136); [self.courseWindow layoutContent]; }
    [self render];
}
- (void)layoutTaskArea {
    CGFloat w=NSWidth(self.root.bounds),h=NSHeight(self.root.bounds),x=216,content=w-x-24;
    self.taskDetails.hidden=self.page>=3 || self.calendarMode || !self.selectedTaskID;
    if(self.calendarMode){
        if(w>=1180){self.calendarScroll.frame=NSMakeRect(x,188,content-304,h-212);self.agenda.frame=NSMakeRect(w-304,188,280,h-212);}
        else {CGFloat agendaHeight=self.selectedTaskID ? 280:176;self.calendarScroll.frame=NSMakeRect(x,188,content,h-228-agendaHeight);self.agenda.frame=NSMakeRect(x,h-24-agendaHeight,content,agendaHeight);}
    }else{
        CGFloat inspector=self.selectedTaskID && self.page<3 ? 320:0;
        if(inspector && content<760){CGFloat detailHeight=MIN(240,(h-212)*0.52);self.scroll.frame=NSMakeRect(x,188,content,MAX(120,h-228-detailHeight));self.taskDetails.frame=NSMakeRect(x,h-24-detailHeight,content,detailHeight);}
        else {self.scroll.frame=NSMakeRect(x,188,content-(inspector ? inspector+16:0),h-212);self.taskDetails.frame=NSMakeRect(w-24-inspector,188,inspector,h-212);}
    }
}
- (NSArray *)selectionTasks {
    if(self.page==2)return [[self visibleTasks] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *task,NSDictionary *bindings){return ![task[@"deleted"] boolValue];}]];
    if(self.page==1){NSMutableArray *result=NSMutableArray.array;for(NSDictionary *task in DDLCalendarTasks(self.tasks,self.calendarStatus.selectedSegment,self.query))if([Cal() isDate:task[@"due"] inSameDayAsDate:self.selectedDay])[result addObject:task];return result;}
    if(self.page==0){NSDate *end=[Cal() dateByAddingUnit:NSCalendarUnitDay value:8 toDate:[Cal() startOfDayForDate:NSDate.date] options:0];NSMutableArray *result=NSMutableArray.array;for(NSDictionary *task in self.tasks)if(![task[@"completed"] boolValue] && ![task[@"archived"] boolValue] && ![task[@"deleted"] boolValue] && [task[@"due"] compare:end]==NSOrderedAscending && (!self.query.length || DDLMatchesFilter(task,0,self.query,NSDate.date,Cal())))[result addObject:task];return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"due"] compare:b[@"due"]];}];}
    return @[];
}
- (void)validateTaskSelection {
    if(self.page>=3 || !self.selectedTaskID)return;
    BOOL found=NO;for(NSDictionary *task in self.selectionTasks)if([task[@"id"] isEqual:self.selectedTaskID]){found=YES;break;}
    if(!found){self.selectedTaskID=nil;self.focusedTaskID=nil;}
}
- (void)selectTask:(NSButton *)sender {
    self.selectedTaskID=sender.identifier;if(self.calendarMode)self.focusedTaskID=sender.identifier;
    [self render];[self focusSelectedTaskRow];
}
- (void)focusSelectedTaskRow {
    NSView *container=self.calendarMode ? self.agendaDocument:self.document;
    for(NSView *view in container.subviews)if([view isKindOfClass:TaskSelectionRow.class] && [view.identifier isEqual:self.selectedTaskID]){[self.window makeFirstResponder:view];[view scrollRectToVisible:view.bounds];return;}
    if(self.calendarMode && self.selectedTaskID)[self.window makeFirstResponder:self.taskDetailsText];
}
- (void)closeTaskDetails:(id)sender {self.selectedTaskID=nil;self.focusedTaskID=nil;[self.window makeFirstResponder:self.search];[self render];}
- (void)moveTaskSelection:(NSInteger)direction {
    NSArray *tasks=self.selectionTasks;if(!tasks.count)return;NSInteger index=0;
    for(NSUInteger i=0;i<tasks.count;i++)if([tasks[i][@"id"] isEqual:self.selectedTaskID]){index=(NSInteger)i+direction;break;}
    index=MAX(0,MIN(index,(NSInteger)tasks.count-1));NSButton *row=NSButton.new;row.identifier=tasks[index][@"id"];[self selectTask:row];
}
- (TaskSelectionRow *)selectionRowForTask:(NSDictionary *)task {
    TaskSelectionRow *row=TaskSelectionRow.new;row.fill=Card();row.radius=10;row.stroke=[self.selectedTaskID isEqual:task[@"id"]] ? Accent():Line();row.identifier=task[@"id"];row.accessibilityLabel=[NSString stringWithFormat:@"查看任务详情：%@",task[@"title"]];
    __weak typeof(self) owner=self;NSString *identifier=task[@"id"];
    row.onSelect=^{NSButton *button=NSButton.new;button.identifier=identifier;[owner selectTask:button];};row.onClose=^{[owner closeTaskDetails:nil];};row.onMove=^(NSInteger direction){[owner moveTaskSelection:direction];};return row;
}
- (void)renderTaskDetailsIn:(Surface *)panel {
    NSDictionary *task=[self taskWithID:self.selectedTaskID];if(!task)return;
    NSString *appearance=[self.root.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]];
    BOOL sameTask=[self.displayedTaskID isEqual:self.selectedTaskID];
    if(sameTask && [self.detailsSnapshot isEqual:task] && [self.detailsAppearance isEqual:appearance] && NSEqualSizes(self.detailsSize,panel.bounds.size) && self.taskDetailsScroll.superview==panel)return;
    NSPoint position=sameTask ? self.taskDetailsScroll.contentView.bounds.origin:NSZeroPoint;
    BOOL restoreFocus=sameTask && self.window.firstResponder==self.taskDetailsText;NSRange selection=self.taskDetailsText.selectedRange;
    self.detailsSnapshot=task.copy;self.detailsAppearance=appearance;self.detailsSize=panel.bounds.size;
    self.displayedTaskID=self.selectedTaskID;Clear(panel);CGFloat w=NSWidth(panel.bounds),h=NSHeight(panel.bounds);
    Put(panel,Text(@"任务详情",14,NSFontWeightSemibold,Ink()),16,16,w-72,24);
    ActionButton *close=Button(@"",self,@selector(closeTaskDetails:),3);close.symbol=@"xmark";close.accessibilityLabel=@"关闭任务详情";Put(panel,close,w-44,12,28,28);
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(12,52,w-24,MAX(64,h-112))];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;scroll.drawsBackground=NO;
    TaskDetailsText *text=[[TaskDetailsText alloc] initWithFrame:NSMakeRect(0,0,w-24,NSHeight(scroll.bounds))];text.editable=NO;text.selectable=YES;text.richText=YES;text.drawsBackground=NO;text.textContainerInset=NSMakeSize(4,8);text.minSize=NSMakeSize(0,NSHeight(scroll.bounds));text.maxSize=NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);text.verticallyResizable=YES;text.horizontallyResizable=NO;text.autoresizingMask=NSViewWidthSizable;text.textContainer.widthTracksTextView=YES;ThemeEditor(text);
    NSMutableAttributedString *body=NSMutableAttributedString.new;
    void (^append)(NSString *,CGFloat,NSFontWeight,NSColor *)=^(NSString *value,CGFloat size,NSFontWeight weight,NSColor *color){[body appendAttributedString:[[NSAttributedString alloc] initWithString:value attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:weight],NSForegroundColorAttributeName:color}]];};
    append([task[@"title"] stringByAppendingString:@"\n\n"],17,NSFontWeightSemibold,Ink());
    append([NSString stringWithFormat:@"%@\n截止：%@\n%@\n\n",task[@"subject"] ?: @"",DDLFormatDate(task[@"due"],@"yyyy年M月d日 HH:mm"),[task[@"archived"] boolValue] ? @"已归档":([task[@"completed"] boolValue] ? @"已完成":@"待完成")],13,NSFontWeightRegular,Muted());
    append(@"备注\n",13,NSFontWeightSemibold,Ink());append([task[@"notes"] length] ? task[@"notes"]:@"暂无备注，可通过“编辑任务”添加。",13,NSFontWeightRegular,[task[@"notes"] length] ? Ink():Muted());
    [text.textStorage setAttributedString:body];__weak typeof(self) owner=self;text.onClose=^{[owner closeTaskDetails:nil];};scroll.documentView=text;[panel addSubview:scroll];[text.layoutManager ensureLayoutForTextContainer:text.textContainer];[text setFrameSize:NSMakeSize(w-24,MAX(NSHeight(scroll.bounds),NSMaxY([text.layoutManager usedRectForTextContainer:text.textContainer])+16))];
    [scroll.contentView scrollToPoint:position];self.taskDetailsScroll=scroll;self.taskDetailsText=text;
    if(restoreFocus){[self.window makeFirstResponder:text];text.selectedRange=NSMakeRange(MIN(selection.location,text.string.length),MIN(selection.length,text.string.length-MIN(selection.location,text.string.length)));}
    ActionButton *edit=Button(@"编辑任务",self,@selector(editTask:),2);edit.identifier=task[@"id"];BOOL canRestore=![task[@"notes"] length] && SSSuggestedNotes(task).length;
    Put(panel,edit,16,h-48,canRestore ? (w-40)/2:w-32,32);
    if(canRestore){ActionButton *restore=Button(@"补全备注…",self,@selector(restoreTaskNotes:),0);restore.identifier=task[@"id"];restore.accessibilityLabel=@"从识别内容补全备注";Put(panel,restore,24+(w-40)/2,h-48,(w-40)/2,32);}
}
- (void)navigate:(id)sender {
    NSInteger destination = [sender tag];
    if (destination < 0 || destination > 4) return;
    if (self.page != destination) {
        if(self.courseWindow.hasUnsavedReview && ![self.courseWindow resolveUnsavedReview])return;
        self.pageStates[@(self.page)] = @{@"query":self.query ?: @"", @"scroll":[NSValue valueWithPoint:self.scroll.contentView.bounds.origin], @"filter":@(self.filter),@"sort":@(self.sortMenu.indexOfSelectedItem),@"taskSelection":self.selectedTaskID ?: @""};
        NSDictionary *state = self.pageStates[@(destination)];
        self.query = state[@"query"] ?: @""; self.search.stringValue = self.query; self.selectedTaskID=[state[@"taskSelection"] length] ? state[@"taskSelection"]:nil;
        if (state[@"filter"]) self.filter = [state[@"filter"] integerValue];
        if(state[@"sort"])[self.sortMenu selectItemAtIndex:[state[@"sort"] integerValue]];
        [self.taskFilter selectItemAtIndex:self.filter];
        self.page = destination; self.notice = @"";
        self.calendarMode = destination == 1;
        [self.searchTimer invalidate]; self.searchTimer = nil;
        if (destination >= 3) [self.courseWindow setInbox:destination == 3];
        [self layout];
        if (state[@"scroll"]) [self.scroll.contentView scrollToPoint:[state[@"scroll"] pointValue]];
    }
    [self showWindow];
}
- (NSArray *)visibleTasks {
    NSDate *now = NSDate.date; NSCalendar *calendar = Cal();
    NSArray *tasks = [self.tasks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *task, NSDictionary *bindings) { return DDLMatchesFilter(task, self.filter, self.query, now, calendar); }]];
    if (self.filter == 5) {
        return [tasks sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSDate *da = [a[@"deletedAt"] isKindOfClass:NSDate.class] ? a[@"deletedAt"] : [NSDate distantPast];
            NSDate *db = [b[@"deletedAt"] isKindOfClass:NSDate.class] ? b[@"deletedAt"] : [NSDate distantPast];
            NSComparisonResult comparison = [db compare:da];
            return comparison == NSOrderedSame ? [a[@"title"] localizedStandardCompare:b[@"title"]] : comparison;
        }];
    }
    BOOL priority = self.sortMenu.indexOfSelectedItem == 1;
    return [tasks sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if (priority && [a[@"priority"] integerValue] != [b[@"priority"] integerValue]) return [b[@"priority"] compare:a[@"priority"]];
        NSComparisonResult comparison = [a[@"due"] compare:b[@"due"]];
        if (comparison == NSOrderedSame) return [a[@"title"] localizedStandardCompare:b[@"title"]];
        return self.filter == 3 ? -comparison : comparison;
    }];
}
- (NSInteger)countFilter:(NSInteger)filter {
    NSDate *now = NSDate.date; NSCalendar *calendar = Cal();
    NSInteger n = 0; for (NSDictionary *task in self.tasks) if (DDLMatchesFilter(task, filter, @"", now, calendar)) n++; return n;
}
- (void)render {
    if (self.renderBusy || !self.document) return; self.renderBusy = YES;
    [self renderSidebar];
    [self renderHeader]; [self renderTaskContent];
    NSInteger pending = [self countFilter:0]; self.statusItem.button.title = pending ? [NSString stringWithFormat:@" %ld", (long)pending] : @""; self.statusItem.button.toolTip = [NSString stringWithFormat:@"%ld 项待完成 · 点击打开 / 右键菜单", (long)pending];
    self.renderBusy = NO;
}
- (void)renderTaskContent {
    [self validateTaskSelection];[self layoutTaskArea];
    BOOL rowFocused=[self.window.firstResponder isKindOfClass:TaskSelectionRow.class];
    [self renderContent];
    if(self.selectedTaskID && self.page<3 && !self.calendarMode)[self renderTaskDetailsIn:self.taskDetails];
    if(rowFocused && self.selectedTaskID)[self focusSelectedTaskRow];
}
- (void)renderSidebar {
    NSPoint sidebarOffset=self.navigationScroll.contentView.bounds.origin;NSButton *focusedButton=[self.window.firstResponder isKindOfClass:NSButton.class] ? (NSButton *)self.window.firstResponder:nil;NSString *focusedID=focusedButton.identifier;SEL focusedAction=focusedButton.action;NSInteger focusedTag=focusedButton.tag;
    Clear(self.sidebar); CGFloat h = NSHeight(self.sidebar.bounds);
    NSTextField *brand = Text(@"AM Helper", 14, NSFontWeightSemibold, Ink()); brand.maximumNumberOfLines = 1; brand.lineBreakMode = NSLineBreakByTruncatingTail; brand.accessibilityLabel = @"AM's Homework Helper"; brand.toolTip = @"AM's Homework Helper";
    Put(self.sidebar, brand, 20, 32, 160, 44);
    NSPoint offset=sidebarOffset;
    self.navigationScroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,96,192,MAX(140,h-276))];self.navigationScroll.hasVerticalScroller=YES;self.navigationScroll.autohidesScrollers=YES;self.navigationScroll.drawsBackground=NO;
    NSArray *snapshots=self.courseWindow.courseSnapshots ?: @[];CGFloat navigationHeight=4*44+44+(self.coursesCollapsed ? 0:(snapshots.count+1)*40);
    Surface *navigation=Box(NSColor.clearColor,0);navigation.frame=NSMakeRect(0,0,192,MAX(NSHeight(self.navigationScroll.frame),navigationHeight));self.navigationScroll.documentView=navigation;[self.sidebar addSubview:self.navigationScroll];
    NSArray *names=@[@"总览",@"日历",@"任务",@"待审核作业"];NSArray *icons=@[@"square.grid.2x2",@"calendar",@"checklist",@"tray"];
    for(NSInteger i=0;i<4;i++){NSString *name=i==3 && self.courseWindow.pendingCount ? [NSString stringWithFormat:@"%@  %lu",names[i],(unsigned long)self.courseWindow.pendingCount]:names[i];ActionButton *button=Button(name,self,@selector(navigate:),3);button.symbol=icons[i];button.tag=i;button.selected=self.page==i;button.identifier=[NSString stringWithFormat:@"navigation-%ld",(long)i];Put(navigation,button,12,i*44,168,36);}
    ActionButton *group=Button(@"课程",self,@selector(toggleCourses:),3);group.identifier=@"course-group";group.symbol=self.coursesCollapsed ? @"chevron.right":@"chevron.down";group.accessibilityLabel=self.coursesCollapsed ? @"展开课程":@"收起课程";Put(navigation,group,12,176,168,36);
    if(!self.coursesCollapsed){ActionButton *all=Button(@"所有课程",self,@selector(selectSidebarCourse:),3);all.identifier=@"";all.symbol=@"books.vertical";all.selected=self.page==4 && !self.courseWindow.selectedCourseID;Put(navigation,all,20,220,160,36);
        for(NSUInteger i=0;i<snapshots.count;i++){NSDictionary *course=snapshots[i];NSString *title=[course[@"pending"] unsignedIntegerValue] ? [NSString stringWithFormat:@"%@  %@",course[@"name"],course[@"pending"]]:course[@"name"];ActionButton *button=Button(title,self,@selector(selectSidebarCourse:),3);button.symbol=course[@"symbol"];button.identifier=course[@"id"];button.selected=self.page==4 && [self.courseWindow.selectedCourseID isEqual:course[@"id"]];button.toolTip=[NSString stringWithFormat:@"%@ · %@",course[@"id"],course[@"status"]];Put(navigation,button,20,260+i*40,160,36);}}
    [self.navigationScroll.contentView scrollToPoint:offset];

    ActionButton *account = Button(self.courseWindow.accountSummary ?: @"连接 GitHub", self, @selector(accountSettings:), 3); account.identifier=@"account";account.symbol = @"person.crop.circle";
    ActionButton *gettingStarted=Button(@"开始使用",self,@selector(startUsing:),3);gettingStarted.identifier=@"getting-started";gettingStarted.symbol=@"questionmark.circle";Put(self.sidebar,gettingStarted,12,h-168,168,36);
    Put(self.sidebar, account, 12, h - 124, 168, 36);
    ActionButton *settings = Button(@"设置", self, @selector(showSettings:), 3); settings.identifier=@"settings";settings.symbol = @"gearshape"; Put(self.sidebar, settings, 12, h - 80, 168, 36);
    if(focusedID){NSView *replacement=AMFindButton(self.sidebar,focusedAction,focusedTag,focusedID);if(replacement)[self.window makeFirstResponder:replacement];}
    Put(self.sidebar, Text(self.preview ? @"模拟数据 · 不会保存" : [NSString stringWithFormat:@"本机数据 · v%@", [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.1"], 11, NSFontWeightRegular, Muted()), 20, h - 32, 164, 16);
}
- (void)toggleCourses:(id)sender {self.coursesCollapsed=!self.coursesCollapsed;[self renderSidebar];}
- (void)selectSidebarCourse:(NSButton *)sender {
    if(self.courseWindow.hasUnsavedReview && ![self.courseWindow resolveUnsavedReview])return;
    NSString *identifier=sender.identifier.length ? sender.identifier:nil;
    NSButton *route=NSButton.new;route.tag=4;[self navigate:route];
    if([self.courseWindow selectCourseID:identifier])[self render];
}
- (void)startUsing:(id)sender {[self.courseWindow startUsing:sender];}
- (void)accountSettings:(id)sender { [self.courseWindow accountSettings:sender]; }
- (void)showSettings:(id)sender {
    [self showWindow]; if (self.window.attachedSheet) return;
    self.settingsController = AMSettingsController.new;
    NSMutableDictionary *displaySettings=[self.preview ? @{@"mode":@"rules",@"endpoint":@"http://localhost:11434",@"model":@"",@"automaticImport":@YES} : SSRecognitionSettings() mutableCopy];NSMutableArray *available=NSMutableArray.array;[available addObjectsFromArray:self.courseWindow.courseRepositoryNames];displaySettings[@"availableCourses"]=available;NSDictionary *lastLocal=self.preview ? nil:SSReadPlist(@"recognition-last-result.plist");if(lastLocal[@"date"])[displaySettings setObject:[NSString stringWithFormat:@"最近本地分析：%@ · %@ · %@",lastLocal[@"course"],DDLFormatDate(lastLocal[@"date"],@"M/d HH:mm"),[lastLocal[@"success"] boolValue] ? @"完成":@"部分失败，规则可用"] forKey:@"localStatus"];[self.settingsController updateSettings:displaySettings];
    __weak typeof(self) owner = self;
    self.settingsController.localHandler=^(NSDictionary *configuration,NSString *action,void (^ready)(NSDictionary *)) {
        if(owner.preview){ready(@{@"models":@[@{@"name":@"示例本地模型",@"digest":@"synthetic"}],@"message":@"模拟预览：不会连接真实模型服务。"});return;}
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
            NSError *failure=nil;SSRecognitionClient *client=SSRecognitionClient.new;NSDictionary *result=nil;
            if([action isEqual:@"models"]){NSArray *models=[client localModels:configuration error:&failure];result=models ? @{@"models":models,@"message":models.count ? @"本地服务已连接，请选择模型后测试识别。":@"服务已连接，但没有已安装模型。请在 Ollama 中准备模型后再次检测。"}:@{@"message":failure.localizedDescription ?: @"无法检测本地服务。"};}
            else {NSString *sample=@"# 作业：实验报告\n截止：2027年4月14日21:00 UTC+8\n完成运动实验分析，提交一份 Markdown 报告。";
                id extracted=[client extract:sample settings:configuration error:&failure];NSArray *validated=extracted ? SSValidatedModelResults(extracted,sample,@"example/course",@"homework.md",@"synthetic",Cal(),&failure):nil;
                result=@{@"message":validated.count==1 ? @"测试通过：本地模型返回了可核验的作业与截止原文。":(failure.localizedDescription ?: @"模型未识别模拟作业，请换模型或检查服务。")};}
            dispatch_async(dispatch_get_main_queue(),^{ready(result);});
        });
    };
    self.settingsController.saveHandler = ^NSString *(NSDictionary *settings, NSString *key) {
        NSError *error = nil; if (!SSValidateRecognitionSettings(settings,&error)) return error.localizedDescription;
        if (owner.preview) return @"";
        NSDictionary *previous = SSRecognitionSettings();
        if ([settings[@"mode"] isEqual:@"cloud"]) {
            if (![settings[@"cloudCourses"] count]) return @"请勾选允许发送老师原文的课程。";
            if (!key.length && ![SSReadSecret(@"recognition-api")[@"endpoint"] isEqual:settings[@"endpoint"]]) return @"请为这个 API 地址填写密钥；不会把其他服务的密钥发送到这里。";
        }
        if ([settings[@"mode"] isEqual:@"cloud"] && (![previous[@"cloudConsent"] boolValue] || ![previous[@"endpoint"] isEqual:settings[@"endpoint"]] || ![previous[@"mode"] isEqual:@"cloud"] || ![previous[@"cloudCourses"] isEqual:settings[@"cloudCourses"]])) {
            NSAlert *alert=NSAlert.new; alert.messageText=@"允许发送老师的课程文档？";
            alert.informativeText=@"启用后，仅勾选课程中新增或变化的老师文本文档会发送到你填写的 API 服务，用于提取和概括作业。个人任务库、作业答案、Git 凭据和其他本机文件不会发送。每天最多20次请求，但仍可能产生费用。";
            [alert addButtonWithTitle:@"启用云端识别"]; [alert addButtonWithTitle:@"取消"]; if ([alert runModal]!=NSAlertFirstButtonReturn) return @"尚未启用云端；设置保留供继续编辑。";
        }
        if ([settings[@"mode"] isEqual:@"cloud"] && key.length && !SSWriteSecret(@"recognition-api",@{@"key":key,@"endpoint":settings[@"endpoint"]})) return @"密钥未能存入钥匙串，设置尚未保存。";
        NSMutableDictionary *next=settings.mutableCopy; next[@"cloudConsent"]=@([settings[@"mode"] isEqual:@"cloud"]);
        return SSWritePlist(@"recognition-settings.plist",next,&error) ? @"" : (error.localizedDescription ?: @"设置保存失败。");
    };
    self.settingsController.actionHandler = ^(NSString *action) {

        if (![owner.settingsController resolveUnsavedChanges]) return;
        [owner.window endSheet:owner.settingsWindow]; [owner.settingsWindow orderOut:nil]; owner.settingsWindow=nil; owner.settingsController=nil;
        if ([action isEqual:@"account"]) [owner accountSettings:nil];
        else if([action isEqual:@"diagnostics"])[owner showDiagnostics:nil];
        else if([action isEqual:@"recovery"])[owner recoverTasks:nil];
        else if([action isEqual:@"notification-help"])[owner notificationHelp:nil];
        else if ([action isEqual:@"notifications"]) [owner showNotificationSettings:nil];
        else if ([action isEqual:@"check-update"]) [owner.updates checkForUpdates:nil];
        else if ([action isEqual:@"updates"]) [owner.updates showSettings:nil];
        else if([action isEqual:@"skill-export"])[owner.courseWindow exportSkillContext:nil];
        else if([action isEqual:@"skill-import"])[owner.courseWindow importSkillResults:nil];
        else if([action isEqual:@"skill-status"]){NSButton *route=NSButton.new;route.tag=4;[owner navigate:route];[owner.courseWindow showSkillJobs:nil];}
        else if([action isEqual:@"skill-courses"])[owner.courseWindow adjustSkillCourses:nil];
        else if([action isEqual:@"skill-all"])[owner.courseWindow exportAllSkillContext:nil];
        else if ([action isEqual:@"advanced"]) [owner.courseWindow authenticationSettings:nil];
    };
    self.settingsWindow=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,620,640) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.settingsWindow.title=@"设置"; self.settingsWindow.contentViewController=self.settingsController; self.settingsWindow.delegate=self;
    [self.window beginSheet:self.settingsWindow completionHandler:nil];
}
- (void)renderHeader {
    Clear(self.header); CGFloat w = NSWidth(self.header.bounds);
    if (self.calendarMode) { [self renderCalendarHeader]; return; }
    NSString *title = @[@"今日与近期安排", @"日历", @"任务", @"待审核作业", @"课程"][self.page];
    if(self.page==4)title=self.courseWindow.selectedCourseID.lastPathComponent ?: @"所有课程";
    Put(self.header, Text(title, 25, NSFontWeightSemibold, Ink()), 0, 4, w - 152, 32);
    NSString *subtitle = (self.notice.length && self.page < 3) ? self.notice : (self.page == 0 ? DDLFormatDate(NSDate.date, @"M月d日 EEEE") : (self.page == 3 ? @"核对老师原文后，将作业加入日历与提醒" : (self.page == 4 ? @"先检查新作业，需要时再同步课程文件" : @"按截止时间安排任务")));
    if(self.page<3)Put(self.header, Text(subtitle, 13, NSFontWeightRegular, Muted()), 0, 48, w, 24);
    if (self.page < 3) { ActionButton *add = Button(@"新建任务", self, @selector(addTask:), 1); add.symbol = @"plus"; Put(self.header, add, w - 136, 0, 136, 36); }
}
- (void)renderDashboard {
    NSPoint position = self.scroll.contentView.bounds.origin; Clear(self.document);
    CGFloat w = self.scroll.contentSize.width - 8, y = 0;
    if (self.courseWindow.pendingCount) {
        ActionButton *inbox = Button([NSString stringWithFormat:@"%lu 项作业待审核", (unsigned long)self.courseWindow.pendingCount], self, @selector(navigate:), 2); inbox.tag = 3; inbox.symbol = @"tray";
        Put(self.document, inbox, 4, y, w, 40); y += 56;
    }
    NSDate *now = NSDate.date; NSDate *today = [Cal() startOfDayForDate:NSDate.date], *tomorrow = [Cal() dateByAddingUnit:NSCalendarUnitDay value:1 toDate:today options:0], *week = [Cal() dateByAddingUnit:NSCalendarUnitDay value:8 toDate:today options:0];
    NSArray *labels = @[@"已逾期", @"今天", @"未来七天"];
    for (NSInteger section = 0; section < 3; section++) {
        NSMutableArray *tasks = NSMutableArray.array;
        for (NSDictionary *task in self.tasks) {
            if ([task[@"completed"] boolValue] || [task[@"archived"] boolValue] || [task[@"deleted"] boolValue]) continue;
            NSDate *due = task[@"due"];
            BOOL match = section == 0 ? [due compare:now] == NSOrderedAscending : (section == 1 ? [due compare:now] != NSOrderedAscending && [due compare:tomorrow] == NSOrderedAscending : [due compare:tomorrow] != NSOrderedAscending && [due compare:week] == NSOrderedAscending);
            if (match && (!self.query.length || DDLMatchesFilter(task, 0, self.query, NSDate.date, Cal()))) [tasks addObject:task];
        }
        [tasks sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"due"] compare:b[@"due"]]; }];
        Put(self.document, Text([NSString stringWithFormat:@"%@ · %lu", labels[section], (unsigned long)tasks.count], 15, NSFontWeightSemibold, Ink()), 4, y, w, 24); y += 32;
        for (NSDictionary *task in tasks) { CGFloat height=[self taskRowHeight:task base:80]; if(y+height>=position.y-100 && y<=position.y+self.scroll.contentSize.height+100)Put(self.document, [self taskRow:task width:w], 4, y, w, height); y += height+8; }
        if (!tasks.count) { Put(self.document, Text(@"暂无任务", 13, NSFontWeightRegular, Muted()), 8, y, w - 16, 24); y += 40; }
        y += 16;
    }
    self.document.frame = NSMakeRect(0, 0, self.scroll.contentSize.width, MAX(y, self.scroll.contentSize.height));
    [self.scroll.contentView scrollToPoint:position];
}
- (CGFloat)taskRowHeight:(NSDictionary *)task base:(CGFloat)base {return base;}
- (Surface *)taskRow:(NSDictionary *)task width:(CGFloat)w {
    BOOL completed = [task[@"completed"] boolValue];
    Surface *row = [self selectionRowForTask:task]; row.frame = NSMakeRect(0, 0, w, 80);
    NSButton *check = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleTask:)]; check.identifier = task[@"id"]; check.state = completed ? NSControlStateValueOn : NSControlStateValueOff;
    check.accessibilityLabel = [NSString stringWithFormat:@"%@：%@", completed ? @"恢复待完成" : @"标记完成", task[@"title"]]; Put(row, check, 16, 26, 24, 28);
    NSTextField *title = Text(task[@"title"], 14, NSFontWeightMedium, completed ? Muted() : Ink()); title.toolTip = task[@"title"]; Put(row, title, 52, 12, w - 196, 24);
    NSString *detail = [NSString stringWithFormat:@"%@ · %@%@", task[@"subject"], DDLFormatDate(task[@"due"], @"M月d日 HH:mm"), [task[@"priority"] integerValue] == 2 ? @" · 紧急" : ([task[@"priority"] integerValue] == 1 ? @" · 重要" : @"")];
    NSTextField *description = Text(detail, 12, NSFontWeightRegular, Muted()); description.toolTip = detail; Put(row, description, 52, 44, w - 260, 20);
    NSTextField *status = Text(DDLRemaining(task[@"due"], NSDate.date, completed), 12, NSFontWeightMedium, EventColor(task)); status.alignment = NSTextAlignmentRight; Put(row, status, w - 188, 44, 168, 20);
    ActionButton *edit = Button(@"编辑", self, @selector(editTask:), 3); edit.identifier = task[@"id"]; Put(row, edit, w - 120, 12, 64, 32);
    ActionButton *more = Button(@"", self, @selector(taskActions:), 3); more.symbol = @"ellipsis"; more.identifier = task[@"id"]; more.accessibilityLabel = @"任务更多操作"; Put(row, more, w - 52, 12, 36, 32);
    return row;
}
- (void)taskActions:(NSButton *)sender {
    NSDictionary *task = [self taskWithID:sender.identifier]; if (!task) return;
    NSMenu *menu = NSMenu.new;
    for (NSArray *entry in @[@[@"复制任务内容", NSStringFromSelector(@selector(copyTask:))], @[[task[@"archived"] boolValue] ? @"恢复到任务" : @"归档", NSStringFromSelector(@selector(archiveTask:))], @[@"移到最近删除", NSStringFromSelector(@selector(deleteTask:))]]) {
        NSMenuItem *item = [menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""]; item.target = self; item.representedObject = task[@"id"];
    }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(sender.bounds)) inView:sender];
}

- (Surface *)deletedRow:(NSDictionary *)task width:(CGFloat)w {
    Surface *row = GradientBox(Card(), Canvas(), 12); row.stroke = Line(); row.frame = NSMakeRect(0, 0, w, 98);
    NSTextField *subject = Text(task[@"subject"], 10, NSFontWeightSemibold, Muted()); Put(row, subject, 17, 13, w - 220, 18);
    NSTextField *title = Text(task[@"title"], 15, NSFontWeightMedium, Muted()); title.selectable = YES; title.toolTip = task[@"title"];
    title.attributedStringValue = [[NSAttributedString alloc] initWithString:task[@"title"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:15 weight:NSFontWeightMedium], NSForegroundColorAttributeName:Muted(), NSStrikethroughStyleAttributeName:@(NSUnderlineStyleSingle)}];
    Put(row, title, 17, 35, w - 210, 24);
    NSString *deletedInfo = [task[@"deletedAt"] isKindOfClass:NSDate.class] ? [NSString stringWithFormat:@"删除于 %@ · 截止 %@", DDLFormatDate(task[@"deletedAt"], @"M月d日 HH:mm"), DDLFormatDate(task[@"due"], @"M月d日 HH:mm")] : @"最近删除";
    Put(row, Text(deletedInfo, 10, NSFontWeightRegular, Muted()), 17, 67, w - 210, 17);
    ActionButton *restore = Button(@"恢复", self, @selector(restoreTask:), 2); restore.identifier = task[@"id"]; restore.accessibilityLabel = [NSString stringWithFormat:@"恢复：%@", task[@"title"]]; Put(row, restore, w - 172, 34, 64, 30);
    ActionButton *purge = Button(@"彻底删除", self, @selector(purgeTask:), 3); purge.identifier = task[@"id"]; purge.accessibilityLabel = [NSString stringWithFormat:@"彻底删除：%@", task[@"title"]]; Put(row, purge, w - 104, 34, 90, 30);
    return row;
}

- (void)renderCalendarHeader {
    CGFloat w = NSWidth(self.header.bounds);
    self.calendarMonthTitle = Text(@"", 25, NSFontWeightSemibold, Ink()); Put(self.header, self.calendarMonthTitle, 0, 4, w - 152, 32);
    ActionButton *add = Button(@"新建任务", self, @selector(addTask:), 1); add.symbol = @"plus"; Put(self.header, add, w - 136, 0, 136, 36);
    self.yearPicker = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger year = 1900; year <= 2200; year++) [self.yearPicker addItemWithTitle:[NSString stringWithFormat:@"%ld 年", (long)year]];
    self.yearPicker.target = self; self.yearPicker.action = @selector(jumpCalendar:);
    self.monthPicker = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger month = 1; month <= 12; month++) [self.monthPicker addItemWithTitle:[NSString stringWithFormat:@"%ld 月", (long)month]];
    self.monthPicker.target = self; self.monthPicker.action = @selector(jumpCalendar:);
    Put(self.header, self.yearPicker, 0, 48, 104, 32); Put(self.header, self.monthPicker, 112, 48, 80, 32);
    ActionButton *prev = Button(@"", self, @selector(navigateCalendar:), 3); prev.tag = -1; prev.symbol = @"chevron.up"; prev.accessibilityLabel = @"上个月";
    ActionButton *today = Button(@"今天", self, @selector(navigateCalendar:), 2);
    ActionButton *next = Button(@"", self, @selector(navigateCalendar:), 3); next.tag = 1; next.symbol = @"chevron.down"; next.accessibilityLabel = @"下个月";
    Put(self.header, prev, 208, 48, 32, 32); Put(self.header, today, 248, 48, 64, 32); Put(self.header, next, 320, 48, 32, 32);
    self.calendarProgressText = Text(@"", 12, NSFontWeightRegular, Muted()); self.calendarProgressText.alignment = NSTextAlignmentRight; Put(self.header, self.calendarProgressText, w - 240, 48, 240, 24);
    [self updateCalendarHeaderState];
}
- (void)updateCalendarHeaderState {
    if (!self.calendarMode || !self.calendarMonthTitle) return;
    self.calendarMonthTitle.stringValue = DDLFormatDate(self.month, @"yyyy 年 M 月");
    [self.yearPicker selectItemWithTitle:DDLFormatDate(self.month, @"yyyy 年")];
    [self.monthPicker selectItemWithTitle:DDLFormatDate(self.month, @"M 月")];
    NSDictionary *summary = DDLMonthSummary(self.tasks, self.month, NSDate.date, Cal());
    double ratio = [summary[@"total"] doubleValue] > 0 ? [summary[@"completed"] doubleValue] / [summary[@"total"] doubleValue] : 0;
    self.calendarProgressText.stringValue = [summary[@"total"] integerValue] ? [NSString stringWithFormat:@"本月完成度  %.0f%%", ratio * 100] : @"本月暂无任务";
}
- (Surface *)agendaRow:(NSDictionary *)task width:(CGFloat)w {
    BOOL done = [task[@"completed"] boolValue];
    Surface *row = [self selectionRowForTask:task];
    Put(row, Text(task[@"subject"], 10, NSFontWeightSemibold, EventColor(task)), 14, 13, w - 83, 18);
    NSTextField *time = Text(DDLFormatDate(task[@"due"], @"HH:mm"), 11, NSFontWeightSemibold, Ink()); time.alignment = NSTextAlignmentRight; Put(row, time, w - 71, 12, 57, 20);
    NSTextField *title = Text(task[@"title"], 14, NSFontWeightMedium, done ? Muted() : Ink()); title.maximumNumberOfLines = 2; title.lineBreakMode = NSLineBreakByWordWrapping; title.selectable = NO; title.toolTip = task[@"title"];
    if (done) title.attributedStringValue = [[NSAttributedString alloc] initWithString:task[@"title"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:14 weight:NSFontWeightMedium], NSForegroundColorAttributeName:Muted(), NSStrikethroughStyleAttributeName:@(NSUnderlineStyleSingle)}];
    Put(row, title, 14, 40, w - 28, 40);
    NSString *state = done ? @"✓ 已完成" : DDLRemaining(task[@"due"], NSDate.date, NO);
    if ([task[@"priority"] integerValue] > 0 && !done) state = [state stringByAppendingString:[task[@"priority"] integerValue] == 2 ? @" · 紧急" : @" · 重要"];
    Put(row, Text(state, 10, NSFontWeightMedium, EventColor(task)), 14, 86, w - 28, 18);
    ActionButton *toggle = Button(done ? @"恢复待办" : @"标记完成", self, @selector(toggleTask:), done ? 2 : 1); toggle.identifier = task[@"id"]; toggle.accessibilityLabel = [NSString stringWithFormat:@"%@：%@", toggle.title, task[@"title"]]; Put(row, toggle, 14, 115, 104, 30);
    ActionButton *edit = Button(@"编辑", self, @selector(editTask:), 3); edit.identifier = task[@"id"]; edit.accessibilityLabel = [NSString stringWithFormat:@"编辑：%@", task[@"title"]]; Put(row, edit, w - 68, 115, 54, 30);
    if (done) { ActionButton *remove = Button(@"删除", self, @selector(deleteTask:), 3); remove.identifier = task[@"id"]; remove.accessibilityLabel = [NSString stringWithFormat:@"删除：%@", task[@"title"]]; Put(row, remove, 124, 115, 54, 30); }
    return row;
}
- (void)renderOverview {
    NSArray *visible = DDLCalendarTasks(self.tasks, self.calendarStatus.selectedSegment, self.query);
    NSPoint calendarPosition = self.calendarScroll.contentView.bounds.origin;
    NSCalendar *calendar = Cal();
    NSDictionary *tasksByDay = DDLTasksByDay(visible, calendar);
    if (!self.calendarBaseMonth) self.calendarBaseMonth = self.month;
    NSDate *baseStart = nil; [Cal() rangeOfUnit:NSCalendarUnitMonth startDate:&baseStart interval:NULL forDate:self.calendarBaseMonth];
    CGFloat calendarWidth = self.calendarScroll.contentSize.width;
    self.calendarSectionHeight = MAX(510, self.calendarScroll.contentSize.height);
    NSInteger minute = (NSInteger)floor(NSDate.date.timeIntervalSince1970 / 60);
    BOOL rebuild = ![self.overviewSnapshot isEqualToArray:visible] || ![self.overviewBaseMonth isEqual:baseStart]
        || !NSEqualSizes(self.overviewSize, self.calendarScroll.contentSize) || self.overviewMinute != minute
        || ![self.overviewTimeZone isEqual:calendar.timeZone.name];
    __weak typeof(self) weakSelf = self;
    if (rebuild) {
        Clear(self.calendarDocument);
        for (NSInteger offset = -6; offset <= 6; offset++) {
            NSDate *month = [Cal() dateByAddingUnit:NSCalendarUnitMonth value:offset toDate:baseStart options:0];
            CGFloat sectionY = (offset + 6) * self.calendarSectionHeight;
            NSTextField *monthTitle = Text(DDLFormatDate(month, @"yyyy 年 M 月"), 18, NSFontWeightSemibold, Ink()); Put(self.calendarDocument, monthTitle, 4, sectionY + 6, calendarWidth - 8, 28);
            OverviewGrid *grid = [OverviewGrid new]; grid.fill = Panel(); grid.gradientEnd = nil; grid.stroke = Line(); grid.radius = 14; grid.month = month; grid.selection = self.selectedDay; grid.tasksByDay = tasksByDay;
            grid.onSelect = ^(NSDate *date, NSString *taskID) {
                weakSelf.selectedDay = date; weakSelf.month = date; weakSelf.focusedTaskID = taskID; weakSelf.selectedTaskID=taskID; weakSelf.notice = @"";
                [weakSelf.agendaScroll.contentView scrollToPoint:NSZeroPoint]; [weakSelf render];
            };
            Put(self.calendarDocument, grid, 0, sectionY + 38, calendarWidth - 6, self.calendarSectionHeight - 48); [grid reload];
        }
        self.overviewSnapshot = [[NSArray alloc] initWithArray:visible copyItems:YES];
        self.overviewBaseMonth = baseStart; self.overviewSize = self.calendarScroll.contentSize; self.overviewMinute = minute;
        self.overviewTimeZone = calendar.timeZone.name;
    } else {
        for (NSView *view in self.calendarDocument.subviews) if ([view isKindOfClass:OverviewGrid.class]) [(OverviewGrid *)view updateSelection:self.selectedDay];
    }
    self.calendarDocument.frame = NSMakeRect(0, 0, calendarWidth, self.calendarSectionHeight * 13);
    if (self.calendarNeedsCenter) calendarPosition.y = self.calendarSectionHeight * 6;
    calendarPosition.y = MAX(0, MIN(calendarPosition.y, self.calendarDocument.frame.size.height - self.calendarScroll.contentSize.height));
    [self.calendarScroll.contentView scrollToPoint:calendarPosition]; [self.calendarScroll reflectScrolledClipView:self.calendarScroll.contentView]; self.calendarNeedsCenter = NO;
    [self refreshCalendarHover];
    NSPoint position = self.agendaScroll.contentView.bounds.origin;
    if(self.selectedTaskID){[self renderTaskDetailsIn:self.agenda];return;}
    Clear(self.agenda); Clear(self.agendaDocument);
    Put(self.agenda, Text(DDLFormatDate(self.selectedDay, @"M 月 d 日"), 23, NSFontWeightSemibold, Ink()), 18, 20, 223, 32);
    ActionButton *add = Button(@"+", self, @selector(addTask:), 2); add.accessibilityLabel = [NSString stringWithFormat:@"为 %@ 新建任务", DDLFormatDate(self.selectedDay, @"M月d日")]; add.font = [NSFont systemFontOfSize:20]; Put(self.agenda, add, NSWidth(self.agenda.bounds) - 48, 16, 32, 32);
    NSArray *dayTasks = tasksByDay[[calendar startOfDayForDate:self.selectedDay]] ?: @[];
    NSInteger completed = 0; for (NSDictionary *task in dayTasks) if ([task[@"completed"] boolValue]) completed++;
    NSString *detail = [NSString stringWithFormat:@"%@ · %lu 项待做 · %ld 项已完成", DDLFormatDate(self.selectedDay, @"EEEE"), dayTasks.count - completed, (long)completed];
    Put(self.agenda, Text(detail, 10, NSFontWeightRegular, Muted()), 18, 62, 264, 18);
    Put(self.agenda, self.agendaScroll, 12, 80, NSWidth(self.agenda.bounds) - 24, MAX(64, NSHeight(self.agenda.bounds) - 96));
    CGFloat w = self.agendaScroll.contentSize.width - 4, y = 0, focusY = -1;
    for (NSDictionary *task in dayTasks) {
        if ([self.focusedTaskID isEqual:task[@"id"]]) focusY = y;
        BOOL compact = NSWidth(self.root.bounds) < 1180; CGFloat height=[self taskRowHeight:task base:compact ? 80:159]; Put(self.agendaDocument, compact ? [self taskRow:task width:w] : [self agendaRow:task width:w], 2, y, w, height); y += height+8;
    }
    if (!dayTasks.count) {
        NSTextField *mark = Text(@"☀", 32, NSFontWeightLight, Accent()); mark.alignment = NSTextAlignmentCenter; Put(self.agendaDocument, mark, 0, 42, w, 48);
        NSString *message = self.query.length || self.calendarStatus.selectedSegment != 0 ? @"这一天没有匹配的任务" : @"这一天暂无任务";
        NSTextField *title = Text(message, 13, NSFontWeightMedium, Ink()); title.alignment = NSTextAlignmentCenter; Put(self.agendaDocument, title, 0, 100, w, 23);
        NSTextField *hint = Text(self.query.length || self.calendarStatus.selectedSegment != 0 ? @"试试切换到「全部」或清空搜索。" : @"也可以点 +，为这一天安排新任务。", 10, NSFontWeightRegular, Muted()); hint.alignment = NSTextAlignmentCenter; Put(self.agendaDocument, hint, 0, 137, w, 36);
        y = 185;
    }
    self.agendaDocument.frame = NSMakeRect(0, 0, self.agendaScroll.contentSize.width, MAX(y, self.agendaScroll.contentSize.height));
    if (focusY >= 0) position.y = focusY;
    position.y = MAX(0, MIN(position.y, self.agendaDocument.frame.size.height - self.agendaScroll.contentSize.height));
    [self.agendaScroll.contentView scrollToPoint:position]; [self.agendaScroll reflectScrolledClipView:self.agendaScroll.contentView];
}
- (void)navigateCalendar:(NSButton *)sender {
    NSDate *targetMonth = nil;
    if (sender.tag == 0) {
        targetMonth = NSDate.date; self.selectedDay = NSDate.date; self.month = targetMonth;
        self.focusedTaskID = nil; self.selectedTaskID=nil; self.notice = @""; [self.agendaScroll.contentView scrollToPoint:NSZeroPoint]; [self render];
    }
    else {
        NSDate *first; [Cal() rangeOfUnit:NSCalendarUnitMonth startDate:&first interval:NULL forDate:self.month];
        targetMonth = [Cal() dateByAddingUnit:NSCalendarUnitMonth value:sender.tag toDate:first options:0];
    }
    [self scrollCalendarToMonth:targetMonth animated:YES];
}
- (void)scrollCalendarToMonth:(NSDate *)targetMonth animated:(BOOL)animated {
    if (!targetMonth || self.calendarSectionHeight <= 0 || !self.calendarBaseMonth) return;
    NSDate *baseStart = nil, *targetStart = nil;
    [Cal() rangeOfUnit:NSCalendarUnitMonth startDate:&baseStart interval:NULL forDate:self.calendarBaseMonth];
    [Cal() rangeOfUnit:NSCalendarUnitMonth startDate:&targetStart interval:NULL forDate:targetMonth];
    NSInteger offset = [[Cal() components:NSCalendarUnitMonth fromDate:baseStart toDate:targetStart options:0] month];
    self.month = targetStart;
    if (offset < -6 || offset > 6) {
        self.calendarBaseMonth = targetStart; self.calendarNeedsCenter = YES; [self render]; return;
    }
    CGFloat maximumY = MAX(0, self.calendarDocument.frame.size.height - self.calendarScroll.contentSize.height);
    NSPoint point = NSMakePoint(0, MAX(0, MIN((offset + 6) * self.calendarSectionHeight, maximumY)));
    [self updateCalendarHeaderState];
    if (!animated || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) { [self.calendarScroll.contentView scrollToPoint:point]; [self.calendarScroll reflectScrolledClipView:self.calendarScroll.contentView]; return; }
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.24; context.allowsImplicitAnimation = YES;
        [[self.calendarScroll.contentView animator] setBoundsOrigin:point];
    } completionHandler:^{ [self.calendarScroll reflectScrolledClipView:self.calendarScroll.contentView]; }];
}
- (void)jumpCalendar:(id)sender {
    NSInteger year = self.yearPicker.titleOfSelectedItem.integerValue;
    NSInteger month = self.monthPicker.titleOfSelectedItem.integerValue;
    NSDateComponents *selected = [Cal() components:(NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:self.selectedDay];
    NSDateComponents *firstParts = [NSDateComponents new]; firstParts.year = year; firstParts.month = month; firstParts.day = 1; firstParts.hour = selected.hour; firstParts.minute = selected.minute;
    NSDate *first = [Cal() dateFromComponents:firstParts]; if (!first) return;
    NSInteger lastDay = [Cal() rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:first].length;
    self.month = first; self.selectedDay = [Cal() dateByAddingUnit:NSCalendarUnitDay value:MIN(lastDay, selected.day) - 1 toDate:first options:0];
    self.calendarBaseMonth = first; self.calendarNeedsCenter = YES; self.focusedTaskID = nil; self.selectedTaskID=nil; self.notice = @""; [self.agendaScroll.contentView scrollToPoint:NSZeroPoint]; [self render];
}
- (void)calendarScrolled:(NSNotification *)notification {
    if (!self.calendarMode || self.calendarSectionHeight <= 0 || !self.calendarBaseMonth) return;
    [self refreshCalendarHover];
    CGFloat centerY = self.calendarScroll.contentView.bounds.origin.y + self.calendarScroll.contentSize.height * 0.45;
    NSInteger index = MAX(0, MIN(12, (NSInteger)floor(centerY / self.calendarSectionHeight)));
    NSDate *baseStart = nil; [Cal() rangeOfUnit:NSCalendarUnitMonth startDate:&baseStart interval:NULL forDate:self.calendarBaseMonth];
    NSDate *visibleMonth = [Cal() dateByAddingUnit:NSCalendarUnitMonth value:index - 6 toDate:baseStart options:0];
    if ([Cal() isDate:visibleMonth equalToDate:self.month toUnitGranularity:NSCalendarUnitMonth]) return;
    self.month = visibleMonth; [self updateCalendarHeaderState];
}
- (void)refreshCalendarHover {
    if (!self.calendarScroll.window) return;
    NSPoint point = self.calendarScroll.window.mouseLocationOutsideOfEventStream;
    NSRect visible = self.calendarScroll.contentView.bounds;
    for (NSView *view in self.calendarDocument.subviews) {
        if (![view isKindOfClass:OverviewGrid.class] || !NSIntersectsRect(view.frame, visible)) continue;
        [(OverviewGrid *)view refreshHoverAtWindowPoint:point];
    }
}
- (void)changeCalendarStatus:(id)sender { self.focusedTaskID = nil; self.selectedTaskID=nil; self.notice = @""; [self.agendaScroll.contentView scrollToPoint:NSZeroPoint]; [self render]; }
- (void)openCalendar:(id)sender { NSButton *route = NSButton.new; route.tag = 1; [self navigate:route]; }
- (void)openList:(id)sender { NSButton *route = NSButton.new; route.tag = 2; [self navigate:route]; }
- (void)taskScrolled:(NSNotification *)notification {
    if(self.taskScrollRendering || self.renderBusy || self.page>=3 || self.calendarMode)return;
    NSInteger bucket=(NSInteger)(self.scroll.contentView.bounds.origin.y/64);if(bucket==self.taskScrollBucket)return;self.taskScrollBucket=bucket;self.taskScrollRendering=YES;[self renderContent];self.taskScrollRendering=NO;
}
- (void)renderContent {
    if (self.page >= 3) return;
    if (self.page == 0) { [self renderDashboard]; return; }
    if (self.calendarMode) { [self renderOverview]; return; }
    NSPoint position = self.scroll.contentView.bounds.origin;
    Clear(self.document); CGFloat w = self.scroll.contentSize.width - 8, y = 0;
    NSArray *tasks = [self visibleTasks];
    NSString *heading = self.query.length ? [NSString stringWithFormat:@"搜索结果 · %lu", tasks.count] : [NSString stringWithFormat:@"%@ · %lu", @[@"待办清单", @"今天的安排", @"未来 7 天", @"已完成", @"已归档", @"最近删除"][self.filter], tasks.count];
    Put(self.document, Text(heading, 12, NSFontWeightSemibold, Muted()), 5, 0, w - 12, 22); y = 33;
    if (tasks.count == 0) {
        Surface *empty = GradientBox(Card(), Canvas(), 14); empty.stroke = Line(); Put(self.document, empty, 4, y, w, 202);
        NSTextField *icon = Text(self.query.length ? @"⌕" : @"✓", 32, NSFontWeightLight, Accent()); icon.alignment = NSTextAlignmentCenter; Put(empty, icon, 0, 31, w, 42);
        NSString *emptyTitle = self.query.length ? @"没有找到匹配的任务" : (self.calendarMode ? @"这一天还没有安排" : (self.filter == 5 ? @"最近删除是空的" : @"这里暂时没有任务"));
        NSString *emptyHint = self.query.length ? @"试试学科、任务名称，或清空搜索。" : (self.filter == 5 ? @"删除已完成的任务后会暂时放在这里，可随时恢复。" : @"点击“新建任务”添加安排。");
        NSTextField *title = Text(emptyTitle, 16, NSFontWeightSemibold, Ink()); title.alignment = NSTextAlignmentCenter; Put(empty, title, 0, 86, w, 25);
        NSTextField *hint = Text(emptyHint, 12, NSFontWeightRegular, Muted()); hint.alignment = NSTextAlignmentCenter; Put(empty, hint, 0, 124, w, 23);
        y += 218;
    } else {
        for (NSDictionary *task in tasks) {
            CGFloat height=self.filter==5 ? 98:[self taskRowHeight:task base:80];if(y+height>=position.y-100 && y<=position.y+self.scroll.contentSize.height+100){Surface *row=self.filter==5 ? [self deletedRow:task width:w]:[self taskRow:task width:w];Put(self.document,row,4,y,w,height);}y+=height+8;
        }
    }
    self.document.frame = NSMakeRect(0, 0, self.scroll.contentSize.width, MAX(y + 12, self.scroll.contentSize.height));
    position.y = MIN(position.y, MAX(0, self.document.frame.size.height - self.scroll.contentSize.height)); [self.scroll.contentView scrollToPoint:position]; [self.scroll reflectScrolledClipView:self.scroll.contentView];
}
- (void)changeFilter:(id)sender { self.filter = [sender isKindOfClass:NSPopUpButton.class] ? [sender indexOfSelectedItem] : [sender tag]; self.page = 2; self.calendarMode = NO; self.notice = @""; [self.scroll.contentView scrollToPoint:NSZeroPoint]; [self layout]; }
- (void)sortChanged:(id)sender { [self renderTaskContent]; }
- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object != self.search) return;
    [self.searchTimer invalidate]; self.searchTimer = nil;
    self.query = [self.search.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.focusedTaskID = nil;
    if (!self.query.length) { [self applySearch]; return; }
    __weak typeof(self) weakSelf = self;
    self.searchTimer = [NSTimer scheduledTimerWithTimeInterval:0.18 repeats:NO block:^(NSTimer *timer) { [weakSelf applySearch]; }];
}
- (void)applySearch {
    [self.searchTimer invalidate]; self.searchTimer = nil;
    [self.scroll.contentView scrollToPoint:NSZeroPoint]; [self.agendaScroll.contentView scrollToPoint:NSZeroPoint];
    [self renderTaskContent];
}
- (void)focusSearch:(id)sender { [self showWindow]; if (self.page >= 3) [self.courseWindow focusSearch]; else [self.window makeFirstResponder:self.search]; }
- (void)showWindow { [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (void)showMain:(id)sender { [self showWindow]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag { [self showWindow]; return YES; }
- (BOOL)resolveEditsForExit:(BOOL)updating {
    if (self.courseWindow.submissionFailedDuringExit) { [self.courseWindow acknowledgeSubmissionFailure]; return NO; }
    if (self.courseWindow.hasUnsavedReview && ![self.courseWindow resolveUnsavedReview]) return NO;
    if (self.settingsController) { if (![self.settingsController resolveUnsavedChanges]) return NO; [self.window endSheet:self.settingsWindow]; [self.settingsWindow orderOut:nil]; self.settingsWindow=nil; self.settingsController=nil; }
    if (self.editor) {
        if (self.editor.hasUnsavedChanges) {
            NSAlert *alert = NSAlert.new; alert.messageText = updating ? @"更新前保存修改？" : @"退出前保存修改？";
            alert.informativeText = @"当前任务或作业审核有未保存内容。";
            [alert addButtonWithTitle:updating ? @"保存后更新" : @"保存后退出"];
            [alert addButtonWithTitle:updating ? @"放弃修改并更新" : @"放弃修改并退出"];
            [alert addButtonWithTitle:updating ? @"稍后更新" : @"取消退出"];
            NSModalResponse choice = [alert runModal];
            if (choice == NSAlertThirdButtonReturn) return NO;
            if (choice == NSAlertFirstButtonReturn) { if (![self.editor saveForExit]) return NO; }
            else [self closeEditor];
        } else [self closeEditor];
    }
    if (self.courseWindow.hasSubmissionSheet) {
        if (self.courseWindow.hasUnsavedSubmission) {
            NSAlert *alert = NSAlert.new; alert.messageText = @"提交窗口有未完成内容";
            alert.informativeText = @"选择“检查并提交”会执行所选文件的提交与推送，完成后才继续退出或更新。验证或提交失败将暂缓退出。";
            [alert addButtonWithTitle:updating ? @"检查并提交后更新" : @"检查并提交后退出"];
            [alert addButtonWithTitle:updating ? @"放弃填写并更新" : @"放弃填写并退出"];
            [alert addButtonWithTitle:updating ? @"稍后更新" : @"取消退出"];
            NSModalResponse choice = [alert runModal];
            if (choice == NSAlertThirdButtonReturn) return NO;
            if (choice == NSAlertFirstButtonReturn) { if (![self.courseWindow saveSubmissionForExit]) return NO; }
            else [self.courseWindow discardSubmission];
        } else [self.courseWindow discardSubmission];
    }
    // Open import/file/other sheets must be completed by the user first.
    if (self.window.attachedSheet) { self.notice = @"请先完成或关闭当前弹窗，再退出或更新。"; [self render]; return NO; }
    return YES;
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (!self.exitCoordinator) return NSTerminateNow;
    if (self.exitCoordinator.pending) return NSTerminateLater;
    if (self.courseWindow.operationBusy) { self.notice = @"正在等待当前课程操作完成，再退出或更新…"; [self render]; }
    __weak typeof(self) weakSelf = self;
    [self.exitCoordinator requestForUpdate:self.updates.installing completion:^(BOOL ready) {
        if (!ready) [weakSelf.updates terminationCancelled];
        [NSApp replyToApplicationShouldTerminate:ready];
    }];
    return NSTerminateLater;
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }
- (void)applicationDidBecomeActive:(NSNotification *)notification { if (!self.preview && self.window) [self refreshPermission]; }
- (void)tick:(NSTimer *)timer { [self render]; if (!self.preview) [self refreshReminders]; }
- (void)woke:(NSNotification *)notification { [self render]; if (!self.preview) { [self refreshPermission]; [self refreshReminders]; } }
- (void)statusClick:(id)sender {
    if (NSApp.currentEvent.type == NSEventTypeRightMouseUp) {
        NSMenu *menu = [NSMenu new];
        NSMenuItem *show = [menu addItemWithTitle:@"打开 AM's Homework Helper" action:@selector(showMain:) keyEquivalent:@""]; show.target = self;
        NSMenuItem *add = [menu addItemWithTitle:@"新建任务" action:@selector(addTask:) keyEquivalent:@""]; add.target = self;
        [menu addItem:[NSMenuItem separatorItem]]; [menu addItemWithTitle:@"退出" action:@selector(terminate:) keyEquivalent:@"q"];
        [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, self.statusItem.button.bounds.size.height) inView:self.statusItem.button];
    } else if (self.window.visible && self.window.keyWindow) [self.window orderOut:nil]; else [self showWindow];
}
- (NSString *)identifierForSender:(id)sender {
    return [sender isKindOfClass:NSMenuItem.class] ? [sender representedObject] : [sender identifier];
}
- (NSMutableDictionary *)taskWithID:(NSString *)identifier { for (NSMutableDictionary *task in self.tasks) if ([task[@"id"] isEqual:identifier]) return task; return nil; }
- (void)addTask:(id)sender {
    [self showWindow]; if (self.window.attachedSheet) return;
    self.editor = [[EditorController alloc] initWithTask:nil owner:self];
    if (self.calendarMode) [self.editor chooseDate:self.selectedDay];
    [self.window beginSheet:self.editor.window completionHandler:nil];
}
- (void)openCourses:(id)sender { NSButton *route = NSButton.new; route.tag = 4; [self navigate:route]; }
- (void)reviewGitHubCandidate:(NSDictionary *)candidate {
    if (candidate[@"kind"] && ![candidate[@"kind"] isEqual:@"assignment"]) return;
    [self showWindow];
    if (self.window.attachedSheet) return;
    NSDictionary *existing = nil;
    for (NSDictionary *task in self.tasks) if ([task[@"sourceID"] isEqual:candidate[@"id"]]) { existing = task; break; }
    NSMutableDictionary *draft = existing ? [existing mutableCopy] : [@{@"id":NSUUID.UUID.UUIDString, @"title":candidate[@"suggestedTitle"] ?: candidate[@"title"], @"subject":[candidate[@"repository"] lastPathComponent], @"notes":SSSuggestedNotes(candidate), @"completed":@NO, @"archived":@NO, @"reminderOffsets":DDLDefaultReminderOffsets()} mutableCopy];
    draft[@"_reviewCandidate"] = candidate; draft[@"_existing"] = @(existing != nil);
    if (!existing) {
        NSDate *date = ![candidate[@"needsDate"] boolValue] && ![candidate[@"needsTime"] boolValue] ? candidate[@"due"] : nil;
        NSDictionary *basis = candidate[@"dateBasis"];
        if (!date && ![candidate[@"needsTime"] boolValue] && ![candidate[@"warnings"] count] && [basis[@"date"] isKindOfClass:NSDate.class] && [basis[@"commit"] length]) date = candidate[@"suggestedDue"];
        draft[@"due"] = date;
    }
    draft[@"sourceID"] = candidate[@"id"];
    draft[@"sourceBlobSHA"] = candidate[@"blobSHA"];
    draft[@"sourceObservedDue"] = candidate[@"observedDue"] ?: candidate[@"due"];
    draft[@"sourceRepository"] = candidate[@"repository"];
    draft[@"sourcePath"] = candidate[@"path"];
    draft[@"sourceLine"] = candidate[@"line"];
    self.editor = [[EditorController alloc] initWithTask:draft owner:self];
    NSArray *pending = self.courseWindow.pendingReviewCandidates; NSMutableArray *queue = NSMutableArray.array;
    NSUInteger start = [pending indexOfObjectPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) { return [item[@"id"] isEqual:candidate[@"id"]]; }];
    if (start == NSNotFound) [queue addObject:candidate[@"id"]];
    else for (NSUInteger offset = 0; offset < pending.count; offset++) [queue addObject:pending[(start + offset) % pending.count][@"id"]];
    self.editor.reviewQueue = queue; [self.editor updateReviewProgress];
    self.editor.window.title = existing ? @"审核更新" : @"审核作业";
    [self.window beginSheet:self.editor.window completionHandler:nil];
}
- (void)continueReviewQueue:(NSArray<NSString *> *)queue after:(NSString *)identifier {
    NSMutableArray *remaining = [queue mutableCopy] ?: NSMutableArray.array; [remaining removeObject:identifier];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.editor || self.window.attachedSheet || self.exitCoordinator.pending || self.courseWindow.operationsPaused) return;
        NSMutableDictionary *pending = NSMutableDictionary.dictionary;
        for (NSDictionary *item in self.courseWindow.pendingReviewCandidates) pending[item[@"id"]] = item;
        [remaining filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *key, NSDictionary *bindings) { return pending[key] != nil; }]];
        if (!remaining.count) { self.notice = @"本轮审核已结束，待审核清单已更新。"; [self render]; return; }
        [self reviewGitHubCandidate:pending[remaining.firstObject]];
        self.editor.reviewQueue = remaining; [self.editor updateReviewProgress];
    });
}
- (void)importClipboard:(id)sender {
    if (!self.editor) [self addTask:nil];
    if (self.editor && !self.editor.task) [self.editor importClipboard:sender];
}
- (void)recoverTasks:(id)sender {
    if(self.window.attachedSheet)return;NSArray *points=SSRecoveryPoints();NSAlert *alert=NSAlert.new;alert.messageText=@"预览任务恢复点";
    if(!points.count){alert.informativeText=@"暂无可用恢复点。原任务文件已保留，可通过“导入任务备份”恢复。";[alert addButtonWithTitle:@"知道了"];[alert runModal];return;}
    NSPopUpButton *picker=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,460,32)];for(NSDictionary *point in points)[picker addItemWithTitle:[NSString stringWithFormat:@"%@ · %@ · %@项",DDLFormatDate(point[@"date"],@"yyyy-MM-dd HH:mm:ss"),[point[@"kind"] isEqual:@"daily"] ? @"每日备份":@"修改前",point[@"count"]]];
    alert.accessoryView=picker;alert.informativeText=@"选择后先预览内容，再确认恢复。恢复会替换当前任务，可按 ⌘Z 撤销；不修改课程文件或登录信息。";[alert addButtonWithTitle:@"预览"];[alert addButtonWithTitle:@"取消"];if([alert runModal]!=NSAlertFirstButtonReturn)return;
    NSError *error=nil;NSArray *tasks=SSRecoveryTasks(points[picker.indexOfSelectedItem][@"id"],&error);if(!tasks){self.notice=error.localizedDescription;[self render];return;}
    NSAlert *preview=NSAlert.new;preview.messageText=[NSString stringWithFormat:@"恢复 %lu 项任务？",(unsigned long)tasks.count];NSMutableArray *lines=NSMutableArray.array;for(NSDictionary *task in tasks)[lines addObject:[NSString stringWithFormat:@"%@ · %@",task[@"title"],DDLFormatDate(task[@"due"],@"yyyy-MM-dd HH:mm")]];
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,460,240)];scroll.hasVerticalScroller=YES;NSTextView *text=[[NSTextView alloc] initWithFrame:scroll.bounds];text.editable=NO;text.string=[lines componentsJoinedByString:@"\n"];text.font=[NSFont systemFontOfSize:13];text.textContainer.widthTracksTextView=YES;scroll.documentView=text;preview.accessoryView=scroll;[preview addButtonWithTitle:@"恢复这些任务"];[preview addButtonWithTitle:@"取消"];if([preview runModal]!=NSAlertFirstButtonReturn)return;
    BOOL blocked=self.taskStoreBlocked;self.taskStoreBlocked=NO;if(![self replaceTasks:tasks action:@"恢复任务" error:&error]){self.taskStoreBlocked=blocked;self.notice=error.localizedDescription;[self render];}
}
- (void)showDiagnostics:(id)sender {
    if(self.window.attachedSheet)return;NSArray *events=SSDiagnostics();NSMutableArray *lines=NSMutableArray.array;for(NSDictionary *event in events)[lines addObject:[NSString stringWithFormat:@"%@ · %@ · %@ · %.3f秒",DDLFormatDate(event[@"date"],@"yyyy-MM-dd HH:mm:ss"),event[@"stage"],event[@"outcome"],[event[@"seconds"] doubleValue]]];
    NSAlert *alert=NSAlert.new;alert.messageText=@"诊断与反馈";alert.informativeText=@"只包含阶段、结果类别、时间与耗时；不包含任务、课程原文、路径、账户或凭据。不会自动上传。导出后可自行附上复现步骤。";NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,240)];scroll.hasVerticalScroller=YES;NSTextView *text=[[NSTextView alloc] initWithFrame:scroll.bounds];text.editable=NO;text.font=[NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];text.string=lines.count ? [lines componentsJoinedByString:@"\n"]:@"暂无诊断记录";scroll.documentView=text;alert.accessoryView=scroll;[alert addButtonWithTitle:@"关闭"];[alert addButtonWithTitle:@"导出预览内容…"];if([alert runModal]==NSAlertSecondButtonReturn){NSSavePanel *panel=NSSavePanel.savePanel;panel.nameFieldStringValue=@"AM-Helper-diagnostics.txt";if([panel runModal]==NSModalResponseOK){NSError *error=nil;if(![text.string writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error]){self.notice=@"诊断导出失败，请检查保存位置。";[self render];}}}
}
- (void)restoreTaskNotes:(id)sender {
    NSString *identifier=[self identifierForSender:sender];NSDictionary *task=[self taskWithID:identifier];NSString *generated=task ? SSSuggestedNotes(task):@"";
    if(!task || [task[@"notes"] length] || !generated.length || self.window.attachedSheet)return;
    NSAlert *alert=NSAlert.new;alert.messageText=@"从识别内容补全备注？";alert.informativeText=@"可在保存后继续编辑。只补全这项空备注，不覆盖其他任务。";
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,440,200)];scroll.hasVerticalScroller=YES;NSTextView *preview=[[NSTextView alloc] initWithFrame:scroll.bounds];preview.editable=NO;preview.font=[NSFont systemFontOfSize:13];preview.string=generated;preview.textContainer.widthTracksTextView=YES;preview.autoresizingMask=NSViewWidthSizable;scroll.documentView=preview;alert.accessoryView=scroll;[alert addButtonWithTitle:@"补全备注"];[alert addButtonWithTitle:@"取消"];
    if([alert runModal]!=NSAlertFirstButtonReturn)return;
    task=[self taskWithID:identifier];if(!task || [task[@"notes"] length])return;
    NSMutableArray *tasks=NSMutableArray.array;for(NSDictionary *item in self.tasks){NSMutableDictionary *copy=item.mutableCopy;if([item[@"id"] isEqual:identifier]){copy[@"notes"]=SSSuggestedNotes(item);copy[@"notesOrigin"]=@"generated";copy[@"notesUserEdited"]=@NO;}[tasks addObject:copy];}
    NSError *error=nil;if(![self replaceTasks:tasks action:@"补全作业备注" error:&error]){self.notice=error.localizedDescription ?: @"备注保存失败，请重试。";[self render];}
}
- (void)editTask:(id)sender {
    if (self.window.attachedSheet) return; NSDictionary *task = [self taskWithID:[self identifierForSender:sender]]; if (!task) return;
    self.editor = [[EditorController alloc] initWithTask:task owner:self]; [self.window beginSheet:self.editor.window completionHandler:nil];
}
- (void)closeEditor { [self.window endSheet:self.editor.window]; [self.editor.window orderOut:nil]; self.editor = nil; }
- (NSArray *)snapshot { return [[NSArray alloc] initWithArray:self.tasks copyItems:YES]; }
- (BOOL)replaceTasks:(NSArray *)tasks action:(NSString *)action error:(NSError **)error {
    NSArray *normalized=DDLNormalizeTasks(tasks); if (normalized.count!=tasks.count) {if(error)*error=[NSError errorWithDomain:@"AMReview" code:1 userInfo:@{NSLocalizedDescriptionKey:@"部分任务格式无效，未写入任何修改。请核对名称和截止时间后重试。"}];return NO;}
    if (!self.preview) {
        if(self.taskStoreBlocked){if(error)*error=[NSError errorWithDomain:@"AMTaskStore" code:2 userInfo:@{NSLocalizedDescriptionKey:@"原任务文件损坏。请先预览恢复点，恢复后再保存任务。"}];return NO;}
        NSDate *start=NSDate.date;BOOL saved=SSSaveTasks([self snapshot],normalized,error);SSDiagnostic(@"save",saved ? @"success":@"failed",-start.timeIntervalSinceNow);if(!saved)return NO;
    }
    [self prepareUndo:action]; self.tasks=[normalized mutableCopy];
    if (!self.preview) [self refreshReminders];
    [self.courseWindow refreshPresentation]; [self render]; return YES;
}
- (NSString *)saveReviewItems:(NSArray *)items automatic:(BOOL)automatic {
    // A bounded local trace contains only stages/outcomes, never course content,
    // source identifiers, paths, notes, tokens or underlying OS error strings.
    void (^trace)(NSString *,NSString *)=^(NSString *stage,NSString *outcome){
        if(self.preview)return;id stored=SSReadPlist(@"review-diagnostics.plist");NSMutableArray *events=[stored isKindOfClass:NSArray.class] ? [stored mutableCopy]:NSMutableArray.array;
        [events addObject:@{@"date":NSDate.date,@"stage":stage,@"outcome":outcome}];while(events.count>64)[events removeObjectAtIndex:0];SSWritePlist(@"review-diagnostics.plist",events,NULL);
    };
    trace(@"click",@"started");
    if(![items isKindOfClass:NSArray.class] || !items.count){trace(@"validation",@"missing-items");return @"没有可保存的作业，请重新选择。";}
    NSMutableArray *next=[[self snapshot] mutableCopy], *added=NSMutableArray.array; NSMutableSet *seen=NSMutableSet.set;NSUInteger savedCount=0;
    for (NSDictionary *item in items) {
        NSDictionary *record=item[@"record"]; NSDictionary *draft=item[@"draft"] ?: @{};
        if (![record isKindOfClass:NSDictionary.class] || ![record[@"id"] isKindOfClass:NSString.class] || ![record[@"id"] length] || [seen containsObject:record[@"id"]]) {trace(@"validation",@"invalid-items");return @"所选作业重复或格式无效，请重新选择。";}
        [seen addObject:record[@"id"]];
        NSDictionary *live=[self.courseWindow reviewSourceWithID:record[@"id"]];
        if (!live || ![live[@"blobSHA"] isEqual:record[@"blobSHA"]]) {trace(@"source",@"changed");return @"老师原文已变化，整批未保存。填写内容已保留，请刷新来源并重新核对。";}
        if (![live[@"kind"] ?: @"assignment" isEqual:@"assignment"]) {trace(@"source",@"classification");return @"材料类型已变化，整批未保存。请先确认属于作业。";}
        for(NSString *key in @[@"dateText",@"due",@"suggestedDue",@"needsDate",@"needsTime"]){if(![(live[key] ?: NSNull.null) isEqual:(record[key] ?: NSNull.null)]){trace(@"source",@"recognition-changed");return @"截止时间识别结果已变化，整批未保存。请刷新来源并重新核对。";}}
        NSUInteger index=[next indexOfObjectPassingTest:^BOOL(NSDictionary *task,NSUInteger i,BOOL *stop){return [task[@"sourceID"] isEqual:record[@"id"]];}];
        NSDictionary *existing=index==NSNotFound ? nil : next[index];
        if (automatic && !SSCanAutomaticallyImport(live,next,NSDate.date)) continue;
        NSError *error=nil; NSDictionary *task=SSReviewedTask(live,draft,existing,&error); if (!task) {trace(@"validation",@"missing-information");return error.localizedDescription ?: @"任务校验失败，请核对填写内容。";}
        if (existing) next[index]=task; else { [next addObject:task]; [added addObject:task]; }savedCount++;
    }
    if (![next isEqual:[self snapshot]]) {
        trace(@"write",@"started");NSError *error=nil; if (![self replaceTasks:next action:automatic ? @"自动加入作业" : @"审核作业" error:&error]) {trace(@"write",@"failed");return @"本机存储失败，整批未保存。填写内容和原有任务保留，请检查磁盘空间及应用数据目录权限后重试。";}
        if (automatic) self.automaticBatch=added;
        self.notice=[NSString stringWithFormat:@"%@ %lu 项作业，可按 ⌘Z 撤销。",automatic ? @"自动加入" : @"已保存",(unsigned long)savedCount]; [self render];
    }
    trace(@"refresh",@"saved");
    return @"";
}
- (void)undoAutomaticImport:(id)sender {
    NSMutableArray *next=[[self snapshot] mutableCopy], *undone=NSMutableArray.array; NSUInteger removed=0;
    for (NSDictionary *task in self.automaticBatch) {NSUInteger i=[next indexOfObject:task];if(i!=NSNotFound){[next removeObjectAtIndex:i];[undone addObject:task];removed++;}}
    NSError *error=nil;
    if (removed && [self.courseWindow deferAutomaticImportOfTasks:undone error:&error] && [self replaceTasks:next action:@"撤销自动加入" error:&error]) {self.automaticBatch=nil;self.notice=[NSString stringWithFormat:@"已撤销 %lu 项自动加入；已编辑的任务保留。",(unsigned long)removed];}
    else self.notice=error.localizedDescription ?: @"没有可撤销的自动加入任务；已编辑的任务会保留。";
    [self render];
}
- (void)completeVisibleTasks:(id)sender {
    NSArray *visible=[self visibleTasks]; NSMutableSet *ids=NSMutableSet.set; for (NSDictionary *task in visible) if (![task[@"completed"] boolValue] && ![task[@"deleted"] boolValue]) [ids addObject:task[@"id"]];
    if (!ids.count) return;
    NSAlert *alert=NSAlert.new;alert.messageText=[NSString stringWithFormat:@"完成当前筛选的 %lu 项任务？",(unsigned long)ids.count];alert.informativeText=@"仅处理当前列表中未完成的任务，可按 ⌘Z 撤销。";[alert addButtonWithTitle:@"标记完成"];[alert addButtonWithTitle:@"取消"];
    if([alert runModal]!=NSAlertFirstButtonReturn)return;
    NSMutableArray *next=[[self snapshot] mutableCopy];for(NSUInteger i=0;i<next.count;i++)if([ids containsObject:next[i][@"id"]]){NSMutableDictionary *copy=[next[i] mutableCopy];copy[@"completed"]=@YES;next[i]=copy;}
    NSError *error=nil;self.notice=[self replaceTasks:next action:@"批量完成" error:&error] ? @"已批量完成，可按 ⌘Z 撤销。" : (error.localizedDescription ?: @"保存失败。");[self render];
}
- (void)prepareUndo:(NSString *)name { NSArray *snapshot = [self snapshot]; [self.taskUndo registerUndoWithTarget:self handler:^(AppDelegate *target) { [target restoreSnapshot:snapshot]; }]; [self.taskUndo setActionName:name]; }
- (void)restoreSnapshot:(NSArray *)snapshot { NSError *error=nil; self.notice=[self replaceTasks:snapshot action:@"任务修改" error:&error] ? @"已恢复上一步操作。" : (error.localizedDescription ?: @"撤销未能保存，原任务保留。"); [self render]; }
- (BOOL)commitTask:(NSDictionary *)task originalID:(NSString *)identifier {
    NSMutableArray *next=[[self snapshot] mutableCopy]; NSUInteger index=[next indexOfObjectPassingTest:^BOOL(NSDictionary *item,NSUInteger idx,BOOL *stop){return [item[@"id"] isEqual:identifier];}];
    if(index==NSNotFound)[next addObject:task];else next[index]=task;
    NSError *error=nil; if(![self replaceTasks:next action:identifier ? @"编辑任务" : @"添加任务" error:&error]) {self.editor.validation.stringValue=@"任务未能保存，请检查本机存储后重试。";self.editor.validation.textColor=NSColor.systemRedColor;return NO;}
    if(!identifier){self.filter=0;self.query=@"";self.search.stringValue=@"";if(self.calendarMode)self.calendarStatus.selectedSegment=0;}
    if(self.calendarMode){self.selectedDay=task[@"due"];self.month=task[@"due"];self.calendarBaseMonth=self.month;self.calendarNeedsCenter=YES;self.focusedTaskID=task[@"id"];}
    self.notice=identifier ? @"任务已更新，提醒时间也已同步。" : @"新任务已加入清单。";
    if(!self.preview && self.authorization==UNAuthorizationStatusNotDetermined)[self requestPermission];[self render];return YES;
}
- (void)changeTask:(NSString *)identifier action:(NSString *)action change:(BOOL (^)(NSMutableDictionary *))change {
    NSMutableArray *next=[DDLNormalizeTasks([self snapshot]) mutableCopy]; NSUInteger index=[next indexOfObjectPassingTest:^BOOL(NSDictionary *item,NSUInteger i,BOOL *stop){return [item[@"id"] isEqual:identifier];}];if(index==NSNotFound)return;
    if(!change(next[index]))[next removeObjectAtIndex:index];NSError *error=nil;
    self.notice=[self replaceTasks:next action:action error:&error] ? [action stringByAppendingString:@"已保存，可按 ⌘Z 撤销。"] : (error.localizedDescription ?: @"保存失败，任务保持完整。");[self render];
}
- (void)toggleTask:(NSButton *)sender { [self changeTask:sender.identifier action:@"完成状态" change:^BOOL(NSMutableDictionary *task){task[@"completed"]=@(![task[@"completed"] boolValue]);return YES;}]; }
- (void)archiveTask:(id)sender { [self changeTask:[self identifierForSender:sender] action:@"归档任务" change:^BOOL(NSMutableDictionary *task){task[@"archived"]=@(![task[@"archived"] boolValue]);return YES;}]; }
- (void)deleteTask:(id)sender { [self changeTask:[self identifierForSender:sender] action:@"移入最近删除" change:^BOOL(NSMutableDictionary *task){task[@"deleted"]=@YES;task[@"deletedAt"]=NSDate.date;return YES;}]; }
- (void)restoreTask:(id)sender { [self changeTask:[self identifierForSender:sender] action:@"恢复任务" change:^BOOL(NSMutableDictionary *task){task[@"deleted"]=@NO;[task removeObjectForKey:@"deletedAt"];return YES;}]; }
- (void)purgeTask:(id)sender { [self changeTask:[self identifierForSender:sender] action:@"彻底删除" change:^BOOL(NSMutableDictionary *task){return NO;}]; }
- (void)copyTask:(NSMenuItem *)sender {
    NSDictionary *task = [self taskWithID:sender.representedObject]; if (!task) return;
    NSString *text = [NSString stringWithFormat:@"[%@] %@\n截止：%@\n%@", task[@"subject"], task[@"title"], DDLFormatDate(task[@"due"], @"yyyy-MM-dd HH:mm"), task[@"notes"]];
    [NSPasteboard.generalPasteboard clearContents]; [NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString];
}
- (void)exportTasks:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel]; panel.nameFieldStringValue = [NSString stringWithFormat:@"AM-Helper-备份-%@.plist", DDLFormatDate(NSDate.date, @"yyyyMMdd-HHmmss")]; panel.title = @"导出全部任务备份";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSError *error = nil; NSData *data = [NSPropertyListSerialization dataWithPropertyList:self.tasks format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        BOOL ok = data && [data writeToURL:panel.URL options:NSDataWritingAtomic error:&error];
        self.notice = ok ? @"任务备份已导出。" : [NSString stringWithFormat:@"导出失败：%@", error.localizedDescription]; [self render];
    }];
}
- (void)importTasks:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = NO; panel.allowsMultipleSelection = NO; panel.title = @"导入任务备份"; panel.message = @"导入会合并任务，相同内容会跳过。现有任务会保留，也可以按 ⌘Z 撤销导入。";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK) return;
        NSNumber *size=nil;[panel.URL getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];if(size.unsignedLongLongValue>20*1024*1024){self.notice=@"备份超过20 MB，请检查文件后再导入。";[self render];return;}
        NSError *error=nil; NSData *data = [NSData dataWithContentsOfURL:panel.URL options:NSDataReadingMappedIfSafe error:&error];
        id items = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error] : nil;
        if (![items isKindOfClass:NSArray.class]) { self.notice = @"备份格式无效，请选择本软件导出的 plist 文件。"; [self render]; return; }
        NSArray *valid = DDLNormalizeTasks(items); if (valid.count != [items count]) { self.notice = @"备份含有异常任务，本次未导入。原有任务保持完整。"; [self render]; return; }
        NSArray *merged = DDLMergeTasks(self.tasks, valid); NSInteger added = merged.count - self.tasks.count;
        NSAlert *confirmation=NSAlert.new;confirmation.messageText=@"预览任务备份导入";
        NSUInteger duplicates=valid.count-added, conflicts=0;NSMutableArray *titles=NSMutableArray.array;
        for(NSDictionary *item in valid){[titles addObject:[NSString stringWithFormat:@"%@ · %@ · %@",item[@"subject"],item[@"title"],DDLFormatDate(item[@"due"],@"yyyy-MM-dd HH:mm")]];for(NSDictionary *old in self.tasks)if([old[@"id"] isEqual:item[@"id"]] && ![old isEqual:item]){conflicts++;break;}}
        confirmation.informativeText=[NSString stringWithFormat:@"备份 %lu 项，新增 %ld 项，重复 %lu 项，标识冲突 %lu 项。重复跳过，冲突以新标识保留两份；现有任务不覆盖。\n恢复备份会保存在本机。",(unsigned long)valid.count,(long)added,(unsigned long)duplicates,(unsigned long)conflicts];
        NSScrollView *preview=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,200)];preview.hasVerticalScroller=YES;NSTextView *list=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,460,200)];list.editable=NO;list.font=[NSFont systemFontOfSize:13];list.string=[titles componentsJoinedByString:@"\n"];preview.documentView=list;confirmation.accessoryView=preview;
        [confirmation addButtonWithTitle:@"合并导入"];[confirmation addButtonWithTitle:@"取消"];if([confirmation runModal]!=NSAlertFirstButtonReturn)return;
        BOOL wasBlocked=self.taskStoreBlocked;self.taskStoreBlocked=NO;
        if ((added > 0 || wasBlocked) && ![self replaceTasks:merged action:@"导入备份" error:&error]) {self.taskStoreBlocked=wasBlocked;self.notice=error.localizedDescription ?: @"导入未能保存，原任务保持完整。";[self render];return;}
        self.notice = [NSString stringWithFormat:@"已导入 %ld 项任务，相同内容自动跳过。", (long)added]; [self render];
    }];
}

- (void)refreshPermission {
    if (self.preview) return;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.authorization = settings.authorizationStatus;
            if (self.notificationError.length) self.notificationStatus = @"提醒安排失败 · 点此重试";
            else if (settings.authorizationStatus == UNAuthorizationStatusDenied) self.notificationStatus = @"通知未开启 · 点此设置";
            else if (settings.authorizationStatus == UNAuthorizationStatusNotDetermined) self.notificationStatus = @"允许通知后可收到提醒";
            else if (settings.alertSetting != UNNotificationSettingEnabled) self.notificationStatus = @"横幅未开启 · 点此设置";
            else self.notificationStatus = [NSString stringWithFormat:@"通知已开启 · %ld 条待提醒", (long)self.scheduledCount];
            [self renderSidebar];
        });
    }];
}
- (void)requestPermission {
    if (self.preview) return;
    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) self.notice = [NSString stringWithFormat:@"通知授权遇到问题：%@", error.localizedDescription];
            else if (!granted) self.notice = @"任务已保存；在系统设置中允许通知后，电脑才能显示提醒。";
            [self refreshPermission]; [self refreshReminders]; [self render];
        });
    }];
}
- (void)refreshReminders {
    if(self.preview)return;
    if(!self.reminderScheduler){self.reminderScheduler=AMReminderScheduler.new;__weak typeof(self) owner=self;self.reminderScheduler.changed=^(NSInteger scheduled,NSString *error,NSString *notice){owner.scheduledCount=scheduled;owner.notificationError=error;if(notice.length)owner.notice=notice;[owner refreshPermission];if(error)[owner render];};}
    self.notificationGeneration++;[self.reminderScheduler schedule:[self snapshot]];
}
- (void)notificationHelp:(id)sender {
    NSAlert *alert=NSAlert.new;alert.messageText=@"测试提醒收到了吗？";alert.informativeText=@"请先在提醒设置发送测试，等待约5秒。通知已经交给系统后，是否展示仍取决于权限、专注模式和系统状态。";[alert addButtonWithTitle:@"我收到了"];[alert addButtonWithTitle:@"没有收到"];[alert addButtonWithTitle:@"取消"];
    NSInteger answer=[alert runModal];if(answer==NSAlertSecondButtonReturn){NSAlert *help=NSAlert.new;help.messageText=@"检查系统通知设置";help.informativeText=@"1. 允许 AM Helper 通知、横幅和声音。\n2. 检查专注模式是否静音。\n3. 确认应用在通知设置中的身份为当前安装版本。\n4. 回到提醒设置重试；任务保存不依赖通知成功。";[help addButtonWithTitle:@"打开系统设置"];[help addButtonWithTitle:@"稍后"];if([help runModal]==NSAlertFirstButtonReturn)[self openSystemNotifications];}
}
- (void)showNotificationSettings:(id)sender {
    [self showWindow]; if (self.window.attachedSheet) return;
    NSAlert *alert = [NSAlert new]; alert.messageText = @"提醒设置";
    if (self.preview) {
        alert.informativeText = @"当前是界面预览，任务只存在内存中，系统通知未注册。正常启动后，可以在这里开启通知、发送测试提醒。"; [alert addButtonWithTitle:@"知道了"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil]; return;
    }
    BOOL notDetermined = self.authorization == UNAuthorizationStatusNotDetermined;
    BOOL denied = self.authorization == UNAuthorizationStatusDenied;
    alert.informativeText = [NSString stringWithFormat:@"%@\n\n每个任务可以设置最多 10 个提醒点，例如「5小时、1小时、到期」。点击测试后，约 5 秒会出现系统通知。\n\n请在系统通知设置中允许 AM's Homework Helper 的横幅和声音。专注模式可能使提醒静音；电脑关机时不显示提醒。关闭窗口后应用仍在菜单栏运行。", self.notificationStatus];
    [alert addButtonWithTitle:notDetermined ? @"允许电脑提醒" : (denied ? @"打开系统设置" : @"发送测试提醒")];
    [alert addButtonWithTitle:@"完成"]; if (!denied) [alert addButtonWithTitle:@"系统通知设置"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSAlertFirstButtonReturn) {
            if (notDetermined) [self requestPermission]; else if (denied) [self openSystemNotifications]; else [self testNotification];
        } else if (response == NSAlertThirdButtonReturn) [self openSystemNotifications];
    }];
}
- (void)openSystemNotifications { [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.Notifications-Settings.extension"]]; }
- (void)testNotification {
    if (self.preview) return;
    UNMutableNotificationContent *content = [UNMutableNotificationContent new]; content.title = @"AM's Homework Helper · 提醒测试"; content.body = @"收到这条通知，就说明电脑提醒已准备好。"; content.sound = UNNotificationSound.defaultSound;
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:@"ddl.test" content:content trigger:[UNTimeIntervalNotificationTrigger triggerWithTimeInterval:5 repeats:NO]];
    [UNUserNotificationCenter.currentNotificationCenter addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.notice = error ? [NSString stringWithFormat:@"测试提醒失败：%@", error.localizedDescription] : @"测试提醒已安排，将在约 5 秒后显示。"; [self render]; });
    }];
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList | UNNotificationPresentationOptionSound);
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showWindow]; NSString *identifier = response.notification.request.content.userInfo[@"taskID"];
        if (identifier && !self.window.attachedSheet) { NSMenuItem *item = [NSMenuItem new]; item.representedObject = identifier; [self editTask:item]; }
        completionHandler();
    });
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication; [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [AppDelegate new]; application.delegate = delegate; [application run];
    }
    return 0;
}
