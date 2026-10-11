#import "SSCourseWindow.h"
#import <fcntl.h>
#import <unistd.h>
#import "SSGit.h"
#import "SSGitHub.h"
#import "SSLocalData.h"
#import "DDLCore.h"
#import "DDLUI.h"
#import "SSAssignments.h"
#import "SSRecognition.h"
#import "SSSecurity.h"
#import "AMUI-Swift.h"

#import "SSSubmission.inc"

@interface SSCourseTable : NSTableView @end
@implementation SSCourseTable
- (void)keyDown:(NSEvent *)event { if ([event.charactersIgnoringModifiers isEqual:@"\r"] && self.selectedRow >= 0) { [NSApp sendAction:self.doubleAction to:self.target from:self]; return; } [super keyDown:event]; }
@end

static NSButton *SSButton(NSString *text, id target, SEL action, NSRect frame) { ActionButton *button=Button(text,target,action,0);button.frame=frame;return button; }
@interface SSCourseController ()
@property SSGitHub *github;
@property SSGit *git;
@property NSMutableArray<NSMutableDictionary *> *courses;
@property NSMutableDictionary<NSString *, NSArray *> *candidates;
@property NSMutableDictionary<NSString *, NSArray *> *materials;
@property NSMutableDictionary *kindOverrides;
@property NSMutableDictionary *automaticDeferrals;
@property NSMutableDictionary *skillProgress;
@property NSMutableDictionary *skillBatches;
@property NSMutableDictionary *skillJobs;
@property NSTimer *skillTimer;
@property NSMutableArray *skillWatchers;
@property NSPopUpButton *typeFilter;
@property NSButton *typeButton;
@property NSArray<NSDictionary *> *availableForks;
@property dispatch_queue_t queue;
@property AMCourseController *courseWorkspace;
@property NSPopUpButton *reviewFilter;
@property NSInteger presentedSection;
@property NSInteger presentedType;
@property NSInteger presentedReviewFilter;
@property NSSegmentedControl *sections;
@property NSSearchField *search;
@property NSString *query;
@property NSString *selectedFork;
@property NSString *selectedCandidateID;
@property NSMutableDictionary *pageStates;
@property NSUInteger workGeneration;
@property NSButton *scanButton;
@property NSButton *syncButton;
@property NSButton *commitButton;
@property NSButton *moreButton;
@property NSButton *assistantButton;
@property NSButton *assistantImportButton;
@property NSButton *reviewButton;
@property NSButton *setupButton;
@property NSButton *recoveryButton;
@property AMSkillJobsController *skillJobsController;
@property BOOL showingSkillJobs;
@property NSMutableDictionary *deferredScans;
@property NSButton *cancelReadButton;
@property NSProgressIndicator *progress;
@property NSTextField *emptyLabel;
@property NSMutableDictionary *statuses;
@property NSString *operationFork;
@property NSString *operationKind;
@property NSString *operationPhase;
@property NSString *statusFork;
@property BOOL connected;
@property BOOL preview;
@property BOOL guided;
@property AMSetupController *setupWorkspace;
@property NSWindow *setupWindow;
@property NSMutableArray<NSMutableDictionary *> *setupRecords;
@property NSInteger setupStep;
@property NSDictionary *loginChallenge;
@property NSArray *setupSelection;
@property BOOL firstCheckRunning;
@property NSMutableDictionary *errorDetails;
@property BOOL refreshing;
@property NSTableView *table;
@property NSTextView *detail;
@property NSTextField *accountLabel;
@property NSTextField *statusLabel;
@property NSTimer *timer;
@property BOOL busy;
@property BOOL loginActive;
@property NSArray<NSButton *> *actionButtons;
@property NSDictionary *reports;
@property SSSubmissionController *submission;
@property BOOL allowingExitSubmission;
@property BOOL exitSubmissionInFlight;
@property AMReviewController *reviewWorkspace;
@property BOOL resolvingReview;
@property (readwrite) BOOL submissionFailedDuringExit;
@end

@implementation SSCourseController
- (instancetype)initWithPreview:(BOOL)preview {
    if ((self = [super initWithNibName:nil bundle:nil])) {
        self.preview = preview; self.github = SSGitHub.new; self.git = SSGit.new;
        self.courses = NSMutableArray.array; self.candidates = NSMutableDictionary.dictionary; self.statuses = NSMutableDictionary.dictionary; self.query = @""; self.pageStates = NSMutableDictionary.dictionary;
        self.materials = NSMutableDictionary.dictionary;self.errorDetails=NSMutableDictionary.dictionary;
        NSDictionary *discoveries = preview ? nil : SSReadPlist(@"discoveries.plist");
        if ([discoveries[@"candidates"] isKindOfClass:NSDictionary.class]) [self.candidates addEntriesFromDictionary:discoveries[@"candidates"]];
        if ([discoveries[@"materials"] isKindOfClass:NSDictionary.class]) [self.materials addEntriesFromDictionary:discoveries[@"materials"]];
        self.skillProgress=[discoveries[@"skillProgress"] isKindOfClass:NSDictionary.class] ? [discoveries[@"skillProgress"] mutableCopy] : NSMutableDictionary.dictionary;
        self.skillBatches=[discoveries[@"skillBatches"] isKindOfClass:NSDictionary.class] ? [discoveries[@"skillBatches"] mutableCopy] : NSMutableDictionary.dictionary;
        self.skillJobs=[discoveries[@"skillJobs"] isKindOfClass:NSDictionary.class] ? [discoveries[@"skillJobs"] mutableCopy]:NSMutableDictionary.dictionary;
        self.skillWatchers=NSMutableArray.array;
        for(NSString *batch in self.skillJobs.allKeys){NSMutableDictionary *job=[self.skillJobs[batch] mutableCopy];if([job[@"state"] isEqual:@"核验中"])job[@"state"]=@"等待助手";self.skillJobs[batch]=job;}
        id overrides = preview ? nil : SSReadPlist(@"discovery-overrides.plist");
        self.kindOverrides = [overrides isKindOfClass:NSDictionary.class] ? [overrides mutableCopy] : NSMutableDictionary.dictionary;
        id deferred=preview ? nil : SSReadPlist(@"automatic-review.plist");self.automaticDeferrals=[deferred isKindOfClass:NSDictionary.class] ? [deferred mutableCopy] : NSMutableDictionary.dictionary;
        NSArray *saved = preview ? @[] : SSReadPlist(@"courses.plist");
        for (id item in [saved isKindOfClass:NSArray.class] ? saved : @[]) if ([item isKindOfClass:NSDictionary.class] && [item[@"fork"] isKindOfClass:NSString.class]) [self.courses addObject:[item mutableCopy]];
        self.connected = !preview && self.github.hasCredentials;
        __weak typeof(self) weakSelf = self;
        self.git.identityVerifier = ^NSDictionary *(NSDictionary *course, NSError **error) { return [weakSelf.github verifyCourse:course error:error]; };
        [self configureCredentialAccess];
        self.git.progress = ^(NSString *phase) { dispatch_async(dispatch_get_main_queue(), ^{ if (weakSelf.busy) [weakSelf status:phase]; }); };
        self.queue = dispatch_queue_create("ddl.course-work", DISPATCH_QUEUE_SERIAL);
        [self buildUI]; [self refreshCourses];
    } return self;
}
- (void)configureCredentialAccess { __weak typeof(self) weakSelf=self;self.git.teacherCredentialProvider=[@[@"oauth",@"githubCLI"] containsObject:self.github.authType] ? ^NSString *(NSDictionary *course,NSError **error){if(![weakSelf.github readableTeacher:course error:error])return nil;return [weakSelf.github accessToken:error];} : nil; }
- (NSWindow *)window { return self.view.window; }
- (BOOL)operationBusy { return self.busy; }
- (BOOL)hasUnsavedReview { return self.reviewWorkspace.hasUnsavedChanges || self.courseWorkspace.hasUnsavedChanges || self.setupWindow.sheetParent != nil; }
- (BOOL)resolveUnsavedReview { if(self.setupWindow.sheetParent){NSAlert *alert=NSAlert.new;alert.messageText=@"课程配置尚未关闭";alert.informativeText=@"已成功关联的课程已经保存；尚未关联的目录选择会被放弃。";[alert addButtonWithTitle:@"继续配置"];[alert addButtonWithTitle:@"放弃未关联选择并继续"];if([alert runModal]!=NSAlertSecondButtonReturn)return NO;[self closeCourseSetup];} self.resolvingReview=YES; self.reviewWorkspace.paused=NO; self.courseWorkspace.paused=NO; BOOL ok=[self.reviewWorkspace resolveUnsavedChanges] && [self.courseWorkspace resolveUnsavedChanges]; self.resolvingReview=NO; self.reviewWorkspace.paused=self.busy || self.operationsPaused; self.courseWorkspace.paused=self.busy || self.operationsPaused; return ok; }
- (void)discardReview { [self.reviewWorkspace discardChanges];[self.courseWorkspace discardChanges];[self closeCourseSetup]; }
- (BOOL)hasSubmissionSheet { return self.submission.window.sheetParent != nil; }
- (BOOL)hasUnsavedSubmission { return self.hasSubmissionSheet && self.submission.hasUnsavedChanges; }
- (void)setOperationsPaused:(BOOL)paused { _operationsPaused = paused; [self refreshPresentation]; }
- (void)cancelPendingLogin { [self cancelLogin:nil]; }
- (void)discardSubmission { [self.submission cancel:nil]; self.submission = nil; }
- (void)acknowledgeSubmissionFailure { self.submissionFailedDuringExit = NO; }
- (BOOL)persistForExit:(NSError **)error { return self.preview || SSWritePlist(@"courses.plist", self.courses, error); }
- (BOOL)saveSubmissionForExit {
    self.allowingExitSubmission = YES; self.exitSubmissionInFlight = YES;
    BOOL saved = [self.submission saveForExit]; self.allowingExitSubmission = NO;
    if (!saved) self.exitSubmissionInFlight = NO;
    return saved;
}
- (NSString *)accountSummary { if (self.loginActive) return @"取消 GitHub 登录"; if (self.busy && !self.connected) return @"正在连接 GitHub…"; return self.connected ? @"GitHub 已连接" : @"连接 GitHub"; }
- (void)buildUI {
    Surface *root = Box(Canvas(), 0); root.frame = NSMakeRect(0, 0, 960, 600); self.view = root;
    __weak typeof(self) weakSelf = self; root.onResize = ^{ [weakSelf layoutContent]; }; root.onAppearanceChange = ^{ [weakSelf refreshPresentation]; };
    self.accountLabel = Text(@"", 13, NSFontWeightRegular, Muted()); [root addSubview:self.accountLabel];
    self.scanButton = SSButton(@"检查新作业", self, @selector(scan:), NSZeroRect);((ActionButton *)self.scanButton).tone=1; [root addSubview:self.scanButton];
    self.syncButton = SSButton(@"同步课程文件", self, @selector(sync:), NSZeroRect); [root addSubview:self.syncButton];
    self.commitButton = SSButton(@"提交作业", self, @selector(commit:), NSZeroRect); [root addSubview:self.commitButton];
    self.moreButton = SSButton(@"更多", self, @selector(more:), NSZeroRect); [root addSubview:self.moreButton];
    self.assistantButton=SSButton(@"助手识别",self,@selector(exportSkillContext:),NSZeroRect);[root addSubview:self.assistantButton];
    self.assistantImportButton=SSButton(@"导入助手结果…",self,@selector(importSkillResults:),NSZeroRect);[root addSubview:self.assistantImportButton];
    self.sections = Segments(@[@"课程内容", @"已加入任务", @"仓库信息"], self, @selector(sectionChanged:)); [root addSubview:self.sections];
    self.typeFilter = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.typeFilter addItemsWithTitles:@[@"全部类型", @"作业", @"课上任务", @"考试", @"待确认类型"]]; self.typeFilter.target = self; self.typeFilter.action = @selector(sectionChanged:); [root addSubview:self.typeFilter];
    self.reviewFilter = [[PastelPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [self.reviewFilter addItemsWithTitles:@[@"全部待审核", @"新作业", @"更新建议"]]; self.reviewFilter.target = self; self.reviewFilter.action = @selector(sectionChanged:); [root addSubview:self.reviewFilter];
    self.search = [[NSSearchField alloc] initWithFrame:NSZeroRect]; self.search.placeholderString = @"搜索作业或来源文件"; self.search.delegate = self; self.search.sendsSearchStringImmediately = YES; [root addSubview:self.search];
    self.statusLabel = Text(@"", 12, NSFontWeightRegular, Muted()); [root addSubview:self.statusLabel];
    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect]; self.progress.style = NSProgressIndicatorStyleSpinning; self.progress.displayedWhenStopped = NO; [root addSubview:self.progress];
    self.setupButton = SSButton(@"添加课程", self, @selector(setup:), NSZeroRect); [root addSubview:self.setupButton];
    self.recoveryButton = SSButton(@"", self, @selector(recover:), NSZeroRect); [root addSubview:self.recoveryButton];
    self.emptyLabel = Text(@"", 14, NSFontWeightMedium, Muted()); self.emptyLabel.alignment = NSTextAlignmentCenter; [root addSubview:self.emptyLabel];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = YES; scroll.borderType = NSNoBorder;
    self.table = [[SSCourseTable alloc] initWithFrame:NSZeroRect]; self.table.delegate = self; self.table.dataSource = self; self.table.rowHeight = 44; self.table.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing; self.table.intercellSpacing = NSMakeSize(8, 0); self.table.usesAlternatingRowBackgroundColors = NO; self.table.backgroundColor = Card();
    for (NSArray *spec in @[@[@"title", @"作业", @250], @[@"due", @"截止时间", @190], @[@"source", @"来源", @240], @[@"state", @"状态", @100]]) { NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:spec[0]]; column.title = spec[1]; column.width = [spec[2] doubleValue]; column.minWidth = 72; [self.table addTableColumn:column]; }
    self.table.target = self; self.table.action = @selector(candidateSelected:); self.table.doubleAction = @selector(review:); scroll.documentView = self.table; [root addSubview:scroll];
    NSScrollView *detailScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect]; detailScroll.hasVerticalScroller = YES; detailScroll.autohidesScrollers = YES; detailScroll.drawsBackground = NO;
    self.detail = [[PastelNotesView alloc] initWithFrame:NSZeroRect]; self.detail.editable = NO; self.detail.font = [NSFont systemFontOfSize:13]; self.detail.textColor = Ink(); self.detail.backgroundColor = Canvas(); self.detail.textContainerInset = NSMakeSize(8, 8); self.detail.autoresizingMask = NSViewWidthSizable; self.detail.textContainer.widthTracksTextView = YES; detailScroll.documentView = self.detail; [root addSubview:detailScroll];
    self.reviewButton = SSButton(@"审核作业…", self, @selector(review:), NSZeroRect); self.reviewButton.bezelColor=NSColor.controlAccentColor; [root addSubview:self.reviewButton];
    self.typeButton = SSButton(@"更改类型…", self, @selector(changeType:), NSZeroRect); [root addSubview:self.typeButton];
    self.actionButtons = @[self.scanButton, self.syncButton, self.commitButton, self.moreButton, self.setupButton];
    self.reviewWorkspace = [AMReviewController new];
    __weak typeof(self) owner = self;
    self.reviewWorkspace.sourceHandler=^NSDictionary *(NSString *identifier){
        NSDictionary *source=[owner reviewSourceWithID:identifier];if(!source)return nil;
        NSMutableDictionary *copy=[SSEnrichDiscovery(source) mutableCopy];
        for(NSDictionary *task in owner.tasksProvider ? owner.tasksProvider():@[])if([task[@"sourceID"] isEqual:identifier]){copy[@"existingTask"]=task;break;}
        return copy;
    };
    self.reviewWorkspace.saveHandler = ^NSString *(NSArray *items) {
        if ((owner.operationsPaused && !owner.resolvingReview) || owner.busy) return @"请等待当前操作结束后再保存。";
        if (!owner.saveReviewItems) return @"任务保存接口尚未就绪。";
        NSString *previous=owner.selectedCandidateID;NSUInteger nextIndex=0;NSArray *before=owner.visible;
        for(NSUInteger i=0;i<before.count;i++)if([before[i][@"id"] isEqual:previous]){nextIndex=i;break;}
        NSString *message = owner.saveReviewItems(items, NO);
        if (!message.length) {
            NSArray *remaining=owner.visible;BOOL retained=NO;for(NSDictionary *record in remaining)if([record[@"id"] isEqual:previous]){retained=YES;break;}
            if(!retained)owner.selectedCandidateID=remaining.count ? remaining[MIN(nextIndex,remaining.count-1)][@"id"]:nil;
            [owner refreshPresentation];
        }
        return message;
    };
    [self addChildViewController:self.reviewWorkspace]; [root addSubview:self.reviewWorkspace.view];
    self.courseWorkspace=AMCourseController.new;
    self.courseWorkspace.saveHandler=self.reviewWorkspace.saveHandler;
    self.courseWorkspace.sourceHandler=self.reviewWorkspace.sourceHandler;
    self.courseWorkspace.actionHandler=^(NSString *action,NSString *identifier){
        if([action isEqual:@"restore-notes"]){if(owner.restoreTaskNotes)owner.restoreTaskNotes(identifier);return;}
        if([action isEqual:@"edit-task"]){if(owner.editTask)owner.editTask(identifier);return;}
        if([action isEqual:@"select"]){dispatch_async(dispatch_get_main_queue(),^{
            for(NSDictionary *record in owner.visible)if([record[@"id"] isEqual:identifier]){owner.selectedCandidateID=identifier;[owner refreshPresentation];break;}
        });return;}
        if(owner.busy || owner.operationsPaused)return;
        NSArray *visible=owner.visible;
        for(NSUInteger index=0;index<visible.count;index++)if([visible[index][@"id"] isEqual:identifier]){
            owner.selectedCandidateID=identifier;[owner.table selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
            if([action isEqual:@"type"]){if(owner.hasUnsavedReview && ![owner resolveUnsavedReview])return;[owner changeType:nil];}else if([action isEqual:@"review"])[owner review:nil];break;
        }
    };
    [self addChildViewController:self.courseWorkspace];[root addSubview:self.courseWorkspace.view];
    self.skillJobsController=AMSkillJobsController.new;[self addChildViewController:self.skillJobsController];[root addSubview:self.skillJobsController.view];self.skillJobsController.view.hidden=YES;
    self.skillJobsController.actionHandler=^(NSString *action,NSString *batch){[owner skillJobAction:action batch:batch];};
    self.cancelReadButton=SSButton(@"取消检查",self,@selector(cancelReadOperation:),NSZeroRect);[root addSubview:self.cancelReadButton];self.cancelReadButton.hidden=YES;
    [self layoutContent];
}
- (void)layoutContent {
    CGFloat w = NSWidth(self.view.bounds), h = NSHeight(self.view.bounds);
    self.accountLabel.frame = NSMakeRect(0, 0, w - 152, 28); self.setupButton.frame = NSMakeRect(w - 136, 0, 136, 28);
    self.scanButton.frame = NSMakeRect(0,32,124,32); self.syncButton.frame=NSMakeRect(136,32,132,32);self.commitButton.frame=NSMakeRect(280,32,108,32);self.moreButton.frame=NSMakeRect(w-72,32,72,32);
    self.assistantButton.frame=NSMakeRect([self course] ? 400:136,32,124,32);self.assistantImportButton.frame=NSMakeRect(276,48,124,36);
    self.assistantButton.hidden=self.inbox;self.assistantImportButton.hidden=YES;
    self.assistantButton.enabled=self.assistantImportButton.enabled=!self.busy && !self.operationsPaused;
    self.sections.frame = NSMakeRect(0, 80, 296, 28); self.sections.hidden = self.inbox;
    self.typeFilter.frame = NSMakeRect(308, 80, 120, 28); self.typeFilter.hidden = self.inbox || self.sections.selectedSegment != 0;
    self.reviewFilter.frame = NSMakeRect(0, 80, 152, 28); self.reviewFilter.hidden = !self.inbox;
    self.search.frame = NSMakeRect(MAX(448, w - 272), 80, MAX(128, MIN(272, w - 448)), 28);
    if (self.inbox) self.search.frame = NSMakeRect(w - 272, 80, 272, 28);
    self.statusLabel.frame = NSMakeRect(24, 116, w - 180, 24); self.progress.frame = NSMakeRect(0, 120, 16, 16); self.recoveryButton.frame = NSMakeRect(w - 144, 112, 144, 28);
    self.table.enclosingScrollView.frame = NSMakeRect(0, 184, w, MAX(112, h - 348));
    self.detail.enclosingScrollView.frame = NSMakeRect(0, h - 152, w, 104); self.reviewButton.frame = NSMakeRect(w - 152, h - 40, 152, 36);
    self.typeButton.frame = NSMakeRect(0, h - 40, 136, 36);
    self.emptyLabel.frame = NSMakeRect(16, 204, w - 32, 72);
    CGFloat reviewTop = self.inbox ? (self.statusLabel.stringValue.length ? 144 : 116) : 144;
    self.reviewWorkspace.view.frame = NSMakeRect(0, reviewTop, w, MAX(240,h - reviewTop));
    self.reviewWorkspace.view.hidden = !self.inbox;
    if (self.inbox) { self.table.enclosingScrollView.hidden = YES; self.detail.enclosingScrollView.hidden = YES; self.reviewButton.hidden = YES; self.typeButton.hidden = YES; self.emptyLabel.hidden = YES; self.search.hidden = YES; }
    else { self.detail.enclosingScrollView.hidden = NO; self.search.hidden = NO; }
    self.courseWorkspace.view.hidden=self.inbox;self.courseWorkspace.view.frame=NSMakeRect(0,144,w,MAX(200,h-144));
    if(!self.inbox){self.table.enclosingScrollView.hidden=YES;self.detail.enclosingScrollView.hidden=YES;self.reviewButton.hidden=YES;self.typeButton.hidden=YES;self.emptyLabel.hidden=YES;}
    self.skillJobsController.view.frame=NSMakeRect(0,144,w,MAX(240,h-144));self.skillJobsController.view.hidden=!self.showingSkillJobs;
    if(self.showingSkillJobs){self.courseWorkspace.view.hidden=YES;self.reviewWorkspace.view.hidden=YES;}
    self.cancelReadButton.frame=NSMakeRect(w-144,112,144,28);self.cancelReadButton.hidden=!self.busy || !self.git.readsCancellable;
    CGFloat available = w - 132; self.table.tableColumns[3].width = 96;
    NSArray *weights = @[@0.34, @0.28, @0.38];
    for (NSUInteger i = 0; i < 3; i++) self.table.tableColumns[i].width = MAX(72, available * [weights[i] doubleValue]);
}
- (void)setInbox:(BOOL)inbox {
    if (_inbox == inbox) return;
    NSString *oldKey = _inbox ? @"inbox" : @"courses";
    self.pageStates[oldKey] = @{@"fork":self.selectedFork ?: @"", @"query":self.query ?: @"", @"selection":self.selectedCandidateID ?: @"", @"scroll":@(self.table.enclosingScrollView.contentView.bounds.origin.y), @"section":@(self.sections.selectedSegment), @"type":@(self.typeFilter.indexOfSelectedItem), @"review":@(self.reviewFilter.indexOfSelectedItem)};
    self.showingSkillJobs=NO;
    _inbox = inbox; NSDictionary *state = self.pageStates[inbox ? @"inbox" : @"courses"];
    self.selectedFork = [state[@"fork"] length] ? state[@"fork"] : nil; self.selectedCandidateID = state[@"selection"]; self.query = state[@"query"] ?: @""; self.search.stringValue = self.query;
    self.sections.selectedSegment = [state[@"section"] integerValue]; [self.typeFilter selectItemAtIndex:[state[@"type"] integerValue]]; [self.reviewFilter selectItemAtIndex:[state[@"review"] integerValue]];
    [self refreshCourses]; [self.table.enclosingScrollView.contentView scrollToPoint:NSMakePoint(0, [state[@"scroll"] doubleValue])];
}
- (void)startAutomaticChecks {
    if (self.preview || self.timer) return;
    [self startSkillReception];
    NSDictionary *progress=SSReadPlist(@"onboarding.plist");
    if([progress[@"completed"] boolValue] && self.connected)[self scanAll:nil];
    else dispatch_async(dispatch_get_main_queue(),^{[self setup:nil];});
    self.timer = [NSTimer scheduledTimerWithTimeInterval:6 * 3600 target:self selector:@selector(scanAll:) userInfo:nil repeats:YES];
}
- (void)dealloc { [self.timer invalidate];[self.skillTimer invalidate];for(dispatch_source_t source in self.skillWatchers)dispatch_source_cancel(source); }
- (NSUInteger)pendingCount {
    NSUInteger count = 0; NSMutableSet *seen = NSMutableSet.set;
    for (NSDictionary *course in self.courses) for (NSDictionary *candidate in [self discoveriesForFork:course[@"fork"]]) if ([candidate[@"kind"] isEqual:@"assignment"] && ![seen containsObject:candidate[@"id"]] && ![[self stateForCandidate:candidate] isEqual:@"已导入"]) { [seen addObject:candidate[@"id"]]; count++; }
    return count;
}
- (void)accountSettings:(id)sender {
    if(self.operationsPaused)return;if(self.busy){if(self.loginActive)[self cancelLogin:nil];return;}
    if(!self.connected){[self setup:nil];return;}
    NSAlert *alert=NSAlert.new;alert.messageText=@"GitHub 已连接";alert.informativeText=[@[@"oauth",@"githubCLI"] containsObject:self.github.authType] ? @"私有课程通过 HTTPS 访问，无需 SSH。登录令牌只保存在本机。旧 GitHub App 安装需在 GitHub 单独撤销。" : @"正在使用旧 GitHub App 登录，可切换到内置 GitHub 官方登录。";
    [alert addButtonWithTitle:@"配置课程…"];[alert addButtonWithTitle:@"退出登录"];[alert addButtonWithTitle:@"高级登录设置…"];[alert addButtonWithTitle:@"重新登录"];[alert addButtonWithTitle:@"关闭"];
    NSModalResponse choice=[alert runModal];if(choice==NSAlertFirstButtonReturn)[self addFork:nil];else if(choice==NSAlertSecondButtonReturn)[self signOut:nil];else if(choice==NSAlertThirdButtonReturn)[self authenticationSettings:nil];else if(choice==NSAlertThirdButtonReturn+1)[self login:nil];
}
- (void)authenticationSettings:(id)sender {
    if(self.busy || self.operationsPaused || self.preview)return;
    NSAlert *alert=NSAlert.new;alert.messageText=@"登录与兼容设置";alert.informativeText=@"推荐内置 GitHub CLI 官方浏览器登录。旧 OAuth／GitHub App 仅供兼容，可能受组织限制。切换不删除任务或旧凭据。";
    [alert addButtonWithTitle:@"GitHub 官方登录"];[alert addButtonWithTitle:@"旧 GitHub App 登录"];[alert addButtonWithTitle:@"撤销旧 App 安装…"];[alert addButtonWithTitle:@"旧 App 公开配置…"];[alert addButtonWithTitle:@"旧 App 安装授权…"];[alert addButtonWithTitle:@"旧 OAuth 登录"];[alert addButtonWithTitle:@"取消"];
    NSModalResponse choice=[alert runModal];if(choice==NSAlertThirdButtonReturn){[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/settings/installations"]];return;}
    if(choice==NSAlertThirdButtonReturn+1){[self setClientID:nil];return;}if(choice==NSAlertThirdButtonReturn+2){[self installApp:nil];return;}
    if(choice!=NSAlertFirstButtonReturn && choice!=NSAlertSecondButtonReturn && choice!=NSAlertThirdButtonReturn+3)return;NSError *error=nil;
    if(![self.github selectAuthentication:choice==NSAlertFirstButtonReturn ? @"githubCLI":(choice==NSAlertSecondButtonReturn ? @"githubApp":@"oauth") error:&error]){[self showError:error];return;}
    [self configureCredentialAccess];self.connected=self.github.hasCredentials;if(!self.connected)[self login:nil];else [self refreshPresentation];
}
- (void)setup:(id)sender {
    if(self.busy || self.operationsPaused)return;self.guided=YES;
    NSDictionary *saved=self.preview ? nil:SSReadPlist(@"onboarding.plist");self.setupSelection=[saved[@"completed"] boolValue] ? nil:saved[@"selected"];
    if(self.connected && ![saved[@"completed"] boolValue] && [saved[@"step"] integerValue]>=2 && [saved[@"records"] isKindOfClass:NSArray.class]){
        self.setupRecords=NSMutableArray.array;for(NSDictionary *row in saved[@"records"])[self.setupRecords addObject:row.mutableCopy];self.setupStep=MIN(3,[saved[@"step"] integerValue]);self.setupSelection=saved[@"selected"];
        [self presentCourseSetup];[self updateCourseSetup:@"继续上次配置。检查不会自动重复执行；可以重试未完成课程。"];return;
    }
    self.setupStep=self.connected ? 1:0;[self presentCourseSetup];if(self.connected)[self addFork:nil];
}
- (void)startUsing:(id)sender {
    if(self.busy || self.operationsPaused)return;NSAlert *alert=NSAlert.new;alert.messageText=@"开始使用";alert.informativeText=@"查看四个日常操作的说明，或继续配置课程。";[alert addButtonWithTitle:@"查看使用提示"];[alert addButtonWithTitle:@"重新运行配置引导"];[alert addButtonWithTitle:@"取消"];
    NSInteger choice=[alert runModal];if(choice==NSAlertFirstButtonReturn){self.setupStep=4;[self presentCourseSetup];[self updateCourseSetup:@""];}else if(choice==NSAlertSecondButtonReturn){self.setupSelection=nil;self.setupStep=self.connected ? 1:0;[self presentCourseSetup];if(self.connected)[self addFork:nil];}
}
- (void)chooseLocalFolder {
    NSAlert *alert = NSAlert.new; alert.messageText = @"关联课程文件夹"; alert.informativeText = @"已下载课程仓库时选择已有文件夹；还未下载时选择保存位置。";
    [alert addButtonWithTitle:@"选择已有文件夹"]; [alert addButtonWithTitle:@"下载课程仓库"]; [alert addButtonWithTitle:@"稍后"];
    NSModalResponse answer = [alert runModal]; if (answer == NSAlertFirstButtonReturn) [self linkFolder:nil]; else if (answer == NSAlertSecondButtonReturn) [self cloneFork:nil];
}
- (void)more:(NSButton *)sender {
    NSMenu *menu = NSMenu.new; menu.autoenablesItems = NO; NSDictionary *course = [self course];
    for (NSArray *entry in @[@[@"添加课程…", NSStringFromSelector(@selector(addFork:))], @[@"关联文件夹…", NSStringFromSelector(@selector(linkFolder:))], @[@"下载课程仓库…", NSStringFromSelector(@selector(cloneFork:))], @[@"打开文件夹", NSStringFromSelector(@selector(openFolder:))], @[@"继续处理冲突…", NSStringFromSelector(@selector(continueMerge:))], @[@"重试推送", NSStringFromSelector(@selector(push:))], @[@"启用 / 停用自动检查", NSStringFromSelector(@selector(toggleCourse:))], @[@"仓库详情", NSStringFromSelector(@selector(repositoryDetails:))], @[@"操作详情…", NSStringFromSelector(@selector(operationDetails:))],@[@"恢复课程访问…",NSStringFromSelector(@selector(restoreAccess:))],@[@"高级登录设置…",NSStringFromSelector(@selector(authenticationSettings:))], @[@"移除课程…", NSStringFromSelector(@selector(removeCourse:))]]) {
        NSMenuItem *item = [menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""]; item.target = self; item.enabled=course!=nil || item.action==@selector(addFork:) || item.action==@selector(authenticationSettings:);
        if (item.action == @selector(continueMerge:)) item.enabled = [course[@"pendingMergeTip"] length] > 0;
        if (item.action == @selector(push:)) item.enabled = [course[@"pushFailed"] boolValue];
        if (item.action == @selector(toggleCourse:)) item.title = [course[@"enabled"] isEqual:@NO] ? @"启用自动检查" : @"停用自动检查";
    }
    for (NSArray *entry in @[@[@"助手识别",NSStringFromSelector(@selector(exportSkillContext:))],@[@"识别批次与进度…",NSStringFromSelector(@selector(showSkillJobs:))],@[@"调整助手课程…",NSStringFromSelector(@selector(adjustSkillCourses:))],@[@"重新分析全部材料…",NSStringFromSelector(@selector(exportAllSkillContext:))],@[@"手动导入助手结果…",NSStringFromSelector(@selector(importSkillResults:))],@[@"高级：用本地模型重新识别…",NSStringFromSelector(@selector(recognizeLocal:))],@[@"高级：课程识别模板…",NSStringFromSelector(@selector(editCourseTemplate:))]]) {NSMenuItem *item=[menu addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];item.target=self;item.enabled=!self.busy && ((![entry[1] isEqual:NSStringFromSelector(@selector(editCourseTemplate:))] && ![entry[1] isEqual:NSStringFromSelector(@selector(recognizeLocal:))]) || course != nil);}
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(sender.bounds)) inView:sender];
}
- (void)editCourseTemplate:(id)sender {
    NSMutableDictionary *course=[self savedCourse:[self course]];if(!course || self.busy || self.operationsPaused)return;
    NSAlert *alert=NSAlert.new;alert.messageText=@"课程识别模板";alert.informativeText=@"可用 titlePattern、contentPattern、deadlinePattern 提取每行的第一个捕获组。留空对象 {} 使用默认 Markdown / 文本模板。模板新增的材料仍须审核；不覆盖已确认任务。";
    NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,480,160)];scroll.hasVerticalScroller=YES;NSTextView *input=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,460,160)];input.font=[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];input.string=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:course[@"recognitionTemplate"] ?: @{} options:NSJSONWritingPrettyPrinted error:NULL] encoding:NSUTF8StringEncoding];scroll.documentView=input;alert.accessoryView=scroll;[alert addButtonWithTitle:@"保存模板"];[alert addButtonWithTitle:@"取消"];
    if([alert runModal]!=NSAlertFirstButtonReturn)return;NSError *error=nil;id template=[NSJSONSerialization JSONObjectWithData:[input.string dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];if(!template || !SSValidateCourseTemplate(template,&error)){[self showError:error];return;}
    NSMutableDictionary *next=course.mutableCopy;next[@"recognitionTemplate"]=template;NSMutableArray *all=self.courses.mutableCopy;all[[all indexOfObject:course]]=next;
    if(!self.preview && !SSWritePlist(@"courses.plist",all,&error)){[self showError:error];return;}[course setDictionary:next];[self status:@"模板已保存，下次检查生效。"]; }
#import "SSCourseSkill.inc"
#import "SSCourseLocal.inc"
#import "SSCourseSetup.inc"
- (void)repositoryDetails:(id)sender { self.sections.selectedSegment = 2; [self refreshPresentation]; }
- (void)operationDetails:(id)sender { NSAlert *alert=NSAlert.new;NSString *key=self.selectedFork ?: @"all";alert.messageText=[self course][@"fork"] ?: @"课程检查";alert.informativeText=self.errorDetails[key] ?: self.statuses[key] ?: @"尚无操作记录。";[alert addButtonWithTitle:@"关闭"];[alert addButtonWithTitle:@"复制详情"];[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse choice){if(choice==NSAlertSecondButtonReturn){[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:SSRedactedText(alert.informativeText) forType:NSPasteboardTypeString];}}]; }
- (void)restoreAccess:(id)sender {if(self.busy || self.operationsPaused)return;NSString *issue=self.reports[self.selectedFork ?: @"all"][@"issue"];if([issue isEqual:@"login"]){self.guided=YES;[self login:nil];}else if([issue isEqual:@"ssh"]){self.guided=YES;[self authenticationSettings:nil];}else if([issue isEqual:@"sso"]){NSString *owner=[[self course][@"upstream"] componentsSeparatedByString:@"/"].firstObject;[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/orgs/%@/sso",owner]]];}else if([issue isEqual:@"permission"] && [self.github.authType isEqual:@"githubCLI"]){NSAlert *alert=NSAlert.new;alert.messageText=@"当前账户无法读取课程";alert.informativeText=@"先在 GitHub 打开老师仓库，核对登录账户和已有课程权限；学校要求 SSO 时完成学校登录。无需申请批准本项目应用。";[alert addButtonWithTitle:@"打开老师仓库"];[alert addButtonWithTitle:@"重新登录"];[alert addButtonWithTitle:@"稍后"];NSInteger answer=[alert runModal];NSString *teacher=[self course][@"upstream"];if(answer==NSAlertFirstButtonReturn && SSCanonicalRepository([@"https://github.com/" stringByAppendingString:teacher ?: @""]))[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:[@"https://github.com/" stringByAppendingString:teacher]]];else if(answer==NSAlertSecondButtonReturn)[self login:nil];}else if([issue isEqual:@"approval"] || [issue isEqual:@"permission"])[NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/settings/applications"]];else [self setup:nil];}
- (void)recover:(id)sender { if ([[self course][@"pendingMergeTip"] length]) [self continueMerge:nil]; else [self push:nil]; }
- (void)focusSearch { if(self.inbox)[self.reviewWorkspace focusSearch];else [self.view.window makeFirstResponder:self.search]; }
- (void)sectionChanged:(id)sender {
    if(self.hasUnsavedReview && ![self resolveUnsavedReview]){[self.sections setSelectedSegment:self.presentedSection];[self.typeFilter selectItemAtIndex:self.presentedType];[self.reviewFilter selectItemAtIndex:self.presentedReviewFilter];return;}
    [self refreshPresentation];
}
- (void)controlTextDidChange:(NSNotification *)notification { if (notification.object == self.search) { self.query = self.search.stringValue; [self refreshPresentation]; } }
- (void)saveCourses { if (self.preview) return; NSError *error = nil; if (!SSWritePlist(@"courses.plist", self.courses, &error)) [self showError:error]; }
- (NSMutableDictionary *)savedCourse:(NSDictionary *)course { for (NSMutableDictionary *saved in self.courses) if ([saved[@"fork"] isEqual:course[@"fork"]]) return saved; return nil; }
- (NSArray<NSString *> *)courseRepositoryNames {NSMutableArray *names=NSMutableArray.array;for(NSDictionary *course in self.courses)if(course[@"fork"])[names addObject:course[@"fork"]];return names.copy;}
- (NSDictionary *)course { for (NSDictionary *course in self.courses) if ([course[@"fork"] isEqual:self.selectedFork]) return course; return nil; }
- (NSArray *)discoveriesForFork:(NSString *)fork {
    NSMutableArray *result = NSMutableArray.array;
    for (NSDictionary *item in [(self.candidates[fork] ?: @[]) arrayByAddingObjectsFromArray:self.materials[fork] ?: @[]]) {
        NSMutableDictionary *copy = item.mutableCopy; NSString *kind = self.kindOverrides[item[@"id"]] ?: item[@"kind"] ?: @"assignment";
        if (![@[@"assignment", @"classroom", @"exam", @"unknown"] containsObject:kind]) kind = @"unknown";
        copy[@"automaticDeferred"]=@([self.automaticDeferrals[item[@"id"]] isEqual:item[@"blobSHA"]]);
        copy[@"kind"] = kind; if (self.kindOverrides[item[@"id"]]) copy[@"kindReason"] = @"你已手动确认类型";
        BOOL exact=NO, nearby=NO;
        for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) {
            if ([task[@"sourceID"] isEqual:copy[@"id"]]) exact=YES;
            if ([task[@"sourceRepository"] isEqual:copy[@"repository"]] && [task[@"sourcePath"] isEqual:copy[@"path"]]) nearby=YES;
        }
        if (!exact && nearby) {copy[@"identityUncertain"]=@YES;NSMutableArray *warnings=[copy[@"warnings"] mutableCopy] ?: NSMutableArray.array;[warnings addObject:@"同一文档已有任务，来源匹配不确定；请核对是否是新作业，避免重复加入。旧任务保留。"];copy[@"warnings"]=warnings;}

        [result addObject:copy];
    } return result;
}
- (BOOL)deferAutomaticImportOfTasks:(NSArray *)tasks error:(NSError **)error {
    NSMutableDictionary *next=self.automaticDeferrals.mutableCopy;
    for(NSDictionary *task in tasks)if([task[@"sourceID"] length] && [task[@"sourceBlobSHA"] length])next[task[@"sourceID"]]=task[@"sourceBlobSHA"];
    if(!self.preview && !SSWritePlist(@"automatic-review.plist",next,error))return NO;
    self.automaticDeferrals=next;return YES;
}
- (BOOL)setKind:(NSString *)kind forDiscovery:(NSDictionary *)record error:(NSError **)error {
    if (!record[@"id"] || ![@[@"assignment", @"classroom", @"exam", @"unknown"] containsObject:kind]) return NO;
    NSMutableDictionary *next = self.kindOverrides.mutableCopy; next[record[@"id"]] = kind;
    if (!self.preview && !SSWritePlist(@"discovery-overrides.plist", next, error)) return NO;
    self.kindOverrides = next; [self refreshPresentation]; return YES;
}
- (void)changeType:(id)sender {
    NSInteger row = self.table.selectedRow; if (self.busy || self.operationsPaused || row < 0 || row >= (NSInteger)self.visible.count) return;
    NSDictionary *record = self.visible[row]; if ([record[@"confirmed"] boolValue]) return;
    NSAlert *alert = NSAlert.new; alert.messageText = @"确认课程内容类型"; alert.informativeText = @"只有作业进入待审核清单。考试与课上任务只在课程页标注；已确认的任务不会被自动删除。";
    NSPopUpButton *menu = [[PastelPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 32) pullsDown:NO]; [menu addItemsWithTitles:@[@"作业", @"课上任务", @"考试", @"待确认类型"]];
    NSArray *kinds = @[@"assignment", @"classroom", @"exam", @"unknown"]; NSInteger selected = [kinds indexOfObject:record[@"kind"]]; [menu selectItemAtIndex:selected == NSNotFound ? 3 : selected]; alert.accessoryView = menu;
    [alert addButtonWithTitle:@"保存类型"]; [alert addButtonWithTitle:@"取消"];
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse answer) { if (answer == NSAlertFirstButtonReturn) { NSError *error = nil; if (![self setKind:kinds[menu.indexOfSelectedItem] forDiscovery:record error:&error]) [self showError:error]; } }];
}
- (NSArray *)visible {
    NSMutableArray *result = NSMutableArray.array; NSMutableSet *seen = NSMutableSet.set;
    if (!self.inbox && self.sections.selectedSegment == 1) {
        for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) if (![task[@"deleted"] boolValue] && [task[@"sourceRepository"] isEqual:[self course][@"upstream"]]) {
            NSMutableDictionary *copy = task.mutableCopy; copy[@"confirmed"] = @YES; copy[@"path"] = task[@"sourcePath"] ?: @""; copy[@"line"] = task[@"sourceLine"] ?: @0; [result addObject:copy];
        }
    } else {
        for (NSDictionary *course in self.courses) {
            if (self.selectedFork && ![course[@"fork"] isEqual:self.selectedFork]) continue;
            for (NSDictionary *candidate in [self discoveriesForFork:course[@"fork"]]) {
                if (self.inbox && ![candidate[@"kind"] isEqual:@"assignment"]) continue;
                NSArray *types = @[@"", @"assignment", @"classroom", @"exam", @"unknown"];
                if (!self.inbox && self.typeFilter.indexOfSelectedItem > 0 && ![candidate[@"kind"] isEqual:types[self.typeFilter.indexOfSelectedItem]]) continue;
                NSString *state = [self stateForCandidate:candidate];
                // Reviewed assignments belong to tasks, never to a review/material queue.
                if ([state isEqual:@"已导入"]) continue;
                if (self.inbox && ((self.reviewFilter.indexOfSelectedItem == 1 && ![state isEqual:@"待审核"]) || (self.reviewFilter.indexOfSelectedItem == 2 && ![state isEqual:@"有更新"]))) continue;
                if (![seen containsObject:candidate[@"id"]]) { [seen addObject:candidate[@"id"]]; [result addObject:candidate]; }
            }
        }
    }
    NSString *query = [self.query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length) [result filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) { NSString *text = [NSString stringWithFormat:@"%@ %@ %@", item[@"title"], item[@"path"], item[@"repository"] ?: item[@"subject"]]; return [text rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound; }]];
    return result;
}
- (NSArray<NSDictionary *> *)pendingReviewCandidates {
    return [[self visible] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        return ![item[@"confirmed"] boolValue] && (!item[@"kind"] || [item[@"kind"] isEqual:@"assignment"]) && ![[self stateForCandidate:item] isEqual:@"已导入"];
    }]];
}
- (NSArray<NSDictionary *> *)allPendingReviewCandidates {
    NSMutableArray *records=NSMutableArray.array; NSMutableSet *seen=NSMutableSet.set;
    for (NSDictionary *course in self.courses) for (NSDictionary *record in [self discoveriesForFork:course[@"fork"]]) if ([record[@"kind"] isEqual:@"assignment"] && ![seen containsObject:record[@"id"]] && ![[self stateForCandidate:record] isEqual:@"已导入"]) { [seen addObject:record[@"id"]]; [records addObject:record]; }
    return records;
}
- (NSDictionary *)reviewSourceWithID:(NSString *)identifier {
    for(NSString *fork in self.deferredScans){NSDictionary *scan=self.deferredScans[fork];for(NSDictionary *row in [(scan[@"candidates"] ?: @[]) arrayByAddingObjectsFromArray:scan[@"materials"] ?: @[]])if([row[@"id"] isEqual:identifier]){NSMutableDictionary *record=row.mutableCopy;if(self.kindOverrides[identifier])record[@"kind"]=self.kindOverrides[identifier];return record;}for(NSDictionary *row in self.candidates[fork])if([row[@"id"] isEqual:identifier])return nil;}
    // An imported source is still valid for editing. Pending status and active
    // page filters must never decide whether its source version is current.
    for (NSDictionary *course in self.courses) for (NSDictionary *record in [self discoveriesForFork:course[@"fork"]]) if ([record[@"id"] isEqual:identifier]) return record;
    return nil;
}
- (void)refreshCourses {
    if(self.selectedFork && ![self savedCourse:@{@"fork":self.selectedFork}])self.selectedFork=nil;
    [self refreshPresentation];
}
- (NSString *)selectedCourseID {return self.selectedFork;}
- (NSArray *)courseSnapshots {
    NSMutableArray *result=NSMutableArray.array;
    for(NSDictionary *course in self.courses){NSUInteger pending=0;for(NSDictionary *record in [self discoveriesForFork:course[@"fork"]])if([record[@"kind"] isEqual:@"assignment"] && ![[self stateForCandidate:record] isEqual:@"已导入"])pending++;
        NSString *symbol=[course[@"path"] length] ? @"book.closed":@"folder.badge.questionmark";
        if([course[@"pendingMergeTip"] length] || [course[@"pushFailed"] boolValue] || self.reports[course[@"fork"]][@"error"])symbol=@"exclamationmark.triangle";
        if(self.busy && [self.operationFork isEqual:course[@"fork"]])symbol=@"arrow.triangle.2.circlepath";
        [result addObject:@{@"id":course[@"fork"],@"name":[course[@"fork"] lastPathComponent],@"pending":@(pending),@"symbol":symbol,@"linked":@([course[@"path"] length]>0),@"status":self.statuses[course[@"fork"]] ?: ([course[@"path"] length] ? @"已关联":@"待关联目录")}];
    }return result;
}
- (BOOL)selectCourseID:(NSString *)identifier {
    if(identifier && ![self savedCourse:@{@"fork":identifier}])return NO;
    if(self.showingSkillJobs){self.showingSkillJobs=NO;[self refreshPresentation];}
    if([self.selectedFork isEqual:identifier] || (!identifier && !self.selectedFork))return YES;
    if(self.hasUnsavedReview && ![self resolveUnsavedReview])return NO;
    NSString *oldKey=[@"course:" stringByAppendingString:self.selectedFork ?: @"all"];
    self.pageStates[oldKey]=@{@"positions":[self.courseWorkspace scrollPositions],@"query":self.query ?: @"",@"id":self.selectedCandidateID ?: @"",@"section":@(self.sections.selectedSegment),@"type":@(self.typeFilter.indexOfSelectedItem),@"scroll":@(self.table.enclosingScrollView.contentView.bounds.origin.y)};
    self.selectedFork=identifier;NSDictionary *state=self.pageStates[[@"course:" stringByAppendingString:identifier ?: @"all"]];self.query=state[@"query"] ?: @"";self.search.stringValue=self.query;self.selectedCandidateID=state[@"id"];self.sections.selectedSegment=[state[@"section"] integerValue];[self.typeFilter selectItemAtIndex:[state[@"type"] integerValue]];
    [self refreshPresentation];[self.courseWorkspace restoreScrollPositions:state[@"positions"] ?: @[]];[self.table.enclosingScrollView.contentView scrollToPoint:NSMakePoint(0,[state[@"scroll"] doubleValue])];return YES;
}
- (void)refreshPresentation {
    if (self.refreshing || !self.table) return; self.refreshing = YES;
    if(!self.hasUnsavedReview && self.deferredScans.count){for(NSString *fork in self.deferredScans){NSDictionary *scan=self.deferredScans[fork];self.candidates[fork]=[self retainingSkill:self.candidates[fork] current:scan[@"candidates"] documents:scan[@"documents"]];self.materials[fork]=[self retainingSkill:self.materials[fork] current:scan[@"materials"] ?: @[] documents:scan[@"documents"]];}[self.deferredScans removeAllObjects];if(!self.preview)SSWritePlist(@"discoveries.plist",self.discoveryEnvelope,NULL);}
    NSDictionary *course = [self course]; NSString *key = self.selectedFork ?: @"all";
    NSDate *last = course[@"lastScan"];
    NSString *context = course ? [NSString stringWithFormat:@"%@ · 上次成功检查：%@%@", course[@"upstream"], last ? DDLFormatDate(last, @"M月d日 HH:mm") : @"尚未检查", [course[@"enabled"] isEqual:@NO] ? @" · 自动检查已停用" : @""] : @"所有课程的发现结果集中在这里";
    self.accountLabel.stringValue = context;
    self.statusLabel.stringValue = self.statuses[key] ?: @"";
    if (self.busy) self.statusLabel.stringValue = [NSString stringWithFormat:@"%@：%@", self.operationFork ?: @"课程检查", self.statuses[self.operationFork ?: @"all"] ?: @"正在处理…"];
    self.statusLabel.toolTip = self.statusLabel.stringValue; self.accountLabel.toolTip = context;
    BOOL local = [course[@"path"] length] > 0;
    self.setupButton.title = !self.connected ? @"连接 GitHub" : (course && !local ? @"关联文件夹…" : @"添加课程…");
    self.setupButton.enabled = !self.busy && !self.operationsPaused; self.moreButton.enabled = !self.busy && !self.operationsPaused;
    self.syncButton.hidden = self.inbox || !course; self.commitButton.hidden = self.inbox || !course;
    self.scanButton.title=course ? @"检查新作业":@"检查所有课程";self.scanButton.bezelColor=NSColor.controlAccentColor;
    self.syncButton.enabled = self.commitButton.enabled = !self.busy && !self.operationsPaused && local && self.connected;
    BOOL anyLocal = NO; for (NSDictionary *item in self.courses) if ([item[@"path"] length]) anyLocal = YES; self.scanButton.enabled = !self.busy && !self.operationsPaused && (local || (!course && anyLocal));
    self.recoveryButton.hidden = !course || (![course[@"pendingMergeTip"] length] && ![course[@"pushFailed"] boolValue]); self.recoveryButton.enabled = !self.busy && !self.operationsPaused;
    self.recoveryButton.title = [course[@"pendingMergeTip"] length] ? @"处理冲突…" : @"重试推送";
    NSArray *visible = [self visible];
    NSMutableArray *reviewRecords = NSMutableArray.array;
    for (NSDictionary *record in visible) {
        NSMutableDictionary *copy = [SSEnrichDiscovery(record) mutableCopy];copy[@"reviewStatus"]=[self stateForCandidate:record];
        for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) if ([task[@"sourceID"] isEqual:record[@"id"]]) { copy[@"existingTask"] = task; break; }
        [reviewRecords addObject:copy];
    }
    NSMutableArray *jobs=NSMutableArray.array;for(NSString *key in self.skillJobs){NSMutableDictionary *row=[self.skillJobs[key] mutableCopy];row[@"id"]=key;[jobs addObject:row];}[jobs sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"date"] compare:a[@"date"]];}];[self.skillJobsController updateRecords:jobs busy:self.busy || self.operationsPaused];
    self.scanButton.toolTip=self.busy ? @"已有课程操作正在执行，请等待完成或取消安全读取。":(!local && !anyLocal ? @"先关联或下载课程文件夹，再检查新作业。":@"只读取老师内容，不合并或推送。");
    self.syncButton.toolTip=self.connected && local ? @"合并老师更新，再安全更新个人 fork。":@"需要登录并关联本地课程文件夹。";self.commitButton.toolTip=self.syncButton.toolTip;
    self.reviewWorkspace.paused = self.operationsPaused;
    if (self.inbox) [self.reviewWorkspace updateRecords:reviewRecords];
    NSString *selectedID = self.selectedCandidateID; NSPoint scrollPosition = self.table.enclosingScrollView.contentView.bounds.origin;
    [self.table reloadData]; [self.table deselectAll:nil];
    if (selectedID) for (NSUInteger i = 0; i < visible.count; i++) if ([visible[i][@"id"] isEqual:selectedID]) { [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO]; break; }
    [self.table.enclosingScrollView.contentView scrollToPoint:scrollPosition];
    BOOL info = !self.inbox && self.sections.selectedSegment == 2;
    self.table.enclosingScrollView.hidden = info || !visible.count;
    self.emptyLabel.hidden = info || visible.count > 0;
    self.emptyLabel.stringValue = !self.courses.count ? @"连接 GitHub，然后添加你的课程仓库" : (course && !local ? @"这门课尚未关联本地文件夹\n点击“关联文件夹…”继续" : (self.query.length ? @"没有匹配的作业，试试其他关键词" : (self.inbox ? @"暂无待审核作业，检查课程后会在这里显示" : @"暂无待审核作业，点击“检查新作业”刷新")));
    self.emptyLabel.maximumNumberOfLines = 2; self.emptyLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.table.backgroundColor = Card(); self.detail.textColor = Ink(); ThemeEditor(self.detail);
    if (info) [self report:nil]; else [self candidateSelected:nil];
    self.reviewButton.hidden = info;
    self.table.tableColumns.firstObject.title = self.inbox ? @"作业" : @"课程内容";
    self.typeButton.hidden = info || (!self.inbox && self.sections.selectedSegment == 1);
    self.typeFilter.hidden = self.inbox || self.sections.selectedSegment != 0;
    NSMutableArray *content=NSMutableArray.array;
    for(NSDictionary *record in visible){
        NSMutableDictionary *copy=[SSEnrichDiscovery(record) mutableCopy];
        if([record[@"confirmed"] boolValue]){
            NSDictionary *source=[self reviewSourceWithID:record[@"sourceID"]];
            if(source && [source[@"kind"] isEqual:@"assignment"]){NSMutableDictionary *review=[SSEnrichDiscovery(source) mutableCopy];review[@"existingTask"]=record;review[@"reviewStatus"]=[self stateForCandidate:source];copy[@"reviewRecord"]=review;}
        }else{
            copy[@"reviewStatus"]=[self stateForCandidate:record];
            for(NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[])if([task[@"sourceID"] isEqual:record[@"id"]]){copy[@"existingTask"]=task;if([copy[@"reviewStatus"] isEqual:@"已导入"])copy[@"due"]=task[@"due"];break;}
        }
        [content addObject:copy];
    }
    NSString *information=info ? self.detail.string : @"";
    if(!course && !self.inbox){NSMutableArray *summary=NSMutableArray.array;for(NSDictionary *snapshot in self.courseSnapshots)[summary addObject:self.reports[snapshot[@"id"]][@"error"] ? [NSString stringWithFormat:@"%@ · %@ · 保留上次成功检查结果",snapshot[@"name"],snapshot[@"status"]] : [NSString stringWithFormat:@"%@ · %@ · %lu 项待审核",snapshot[@"name"],snapshot[@"status"],(unsigned long)[snapshot[@"pending"] unsignedIntegerValue]]];information=[summary componentsJoinedByString:@"\n\n"];[content removeAllObjects];}
    [self.courseWorkspace updateRecords:content selected:self.selectedCandidateID ?: @"" information:information empty:self.emptyLabel.stringValue paused:self.busy || self.operationsPaused];
    self.presentedSection=self.sections.selectedSegment;self.presentedType=self.typeFilter.indexOfSelectedItem;self.presentedReviewFilter=self.reviewFilter.indexOfSelectedItem;
    [self layoutContent]; self.refreshing = NO;
    if (self.stateChanged) self.stateChanged();
}
- (void)cancelReadOperation:(id)sender {if(self.busy && self.git.readsCancellable){self.git.cancelledReads=YES;self.cancelReadButton.enabled=NO;[self status:@"正在取消检查；等待当前安全读取结束…"];} }
- (void)status:(NSString *)message { if(self.busy)self.operationPhase=message; self.statuses[self.statusFork ?: self.selectedFork ?: @"all"] = message ?: @""; [self refreshPresentation]; }
- (void)showError:(NSError *)error { if (error) {self.errorDetails[self.statusFork ?: self.selectedFork ?: @"all"]=SSRedactedText(error.userInfo[@"SSDetail"] ?: error.localizedDescription);[self status:[@"⚠ " stringByAppendingString:error.localizedDescription]];} }
- (void)work:(NSString *)message operation:(id (^)(NSError **))operation completion:(void (^)(id, NSError *))completion {
    [self work:message forCourse:[self course] operation:operation completion:completion];
}
- (void)work:(NSString *)message forCourse:(NSDictionary *)course operation:(id (^)(NSError **))operation completion:(void (^)(id, NSError *))completion {
    if (self.preview) { [self status:@"模拟预览不会操作真实账户或仓库"]; return; }
    if (self.busy || (self.operationsPaused && !self.allowingExitSubmission)) return;
    NSDate *started=NSDate.date;self.git.cancelledReads=NO;self.git.readsCancellable=[message containsString:@"扫描"] || [message containsString:@"准备中"] || [message containsString:@"核验中"] || [message containsString:@"读取个人"] || [message containsString:@"读取冲突"];self.cancelReadButton.enabled=YES;SSDiagnostic(@"operation",@"started",0);
    self.busy = YES;self.operationKind=message;self.operationPhase=message; self.workGeneration++; NSUInteger generation = self.workGeneration; NSString *target = course[@"fork"]; self.operationFork = target; self.statusFork = target; [self.progress startAnimation:nil]; [self status:message];
    dispatch_async(self.queue, ^{
        NSError *error = nil; id value = operation(&error);
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL cancelled=self.git.cancelledReads;self.git.readsCancellable=NO;self.git.cancelledReads=NO;SSDiagnostic(@"operation",cancelled ? @"cancelled":(error ? @"failed":@"success"),-started.timeIntervalSinceNow);
            self.busy = NO; [self.progress stopAnimation:nil]; self.statusFork = target;
            completion(value, error); if (self.workGeneration == generation) { self.statusFork = nil; self.operationFork = nil; } [self refreshPresentation];
            if (self.operationStateChanged) self.operationStateChanged();
        });
    });
}
- (void)setClientID:(id)sender {
    if (self.busy || self.preview || self.operationsPaused) return;
    NSAlert *alert = [NSAlert new]; alert.messageText = @"GitHub App Client ID";
    alert.informativeText = @"填写开发者注册的 GitHub App 公开 Client ID 和安装链接。注册说明位于 docs/GITHUB_APP_SETUP.md。不要填写密钥或个人令牌。";
    NSTextField *field = [[PastelTextField alloc] initWithFrame:NSMakeRect(0, 42, 440, 28)]; field.stringValue = self.github.clientID ?: @"";
    NSTextField *install = [[PastelTextField alloc] initWithFrame:NSMakeRect(0, 0, 440, 28)]; install.stringValue = self.github.installationURL ?: @""; install.placeholderString = @"https://github.com/apps/应用名称/installations/new";
    NSView *settings = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 440, 70)]; [settings addSubview:field]; [settings addSubview:install];
    alert.accessoryView = settings; [alert addButtonWithTitle:@"保存"]; [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSString *identifier = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([identifier rangeOfString:@"^Iv[A-Za-z0-9.]{10,80}$" options:NSRegularExpressionSearch].location == NSNotFound) { [self status:@"Client ID 格式无效"]; return; }
    NSString *installationURL = [install.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (installationURL.length && [installationURL rangeOfString:@"^https://github\\.com/apps/[a-z0-9-]+/installations/new$" options:NSRegularExpressionSearch].location == NSNotFound) { [self status:@"安装页面链接格式无效。"]; return; }
    NSError *error = nil;
    NSMutableDictionary *next=[SSReadPlist(@"settings.plist") mutableCopy] ?: NSMutableDictionary.dictionary;next[@"clientID"]=identifier;next[@"installationURL"]=installationURL;next[@"authType"]=@"githubApp";next[@"authSelectionVersion"]=@2;
    if (!SSWritePlist(@"settings.plist", next, &error)) { [self showError:error]; return; }
    self.github.authType=@"githubApp";self.github.clientID = identifier; self.github.installationURL = installationURL;[self configureCredentialAccess];self.connected=self.github.hasCredentials; [self status:@"已保存公开应用信息。请先安装授权，再登录。"];
}
- (void)login:(id)sender {
    if(self.busy || self.operationsPaused)return;
    self.setupStep=0;self.loginChallenge=nil;[self presentCourseSetup];self.loginActive=YES;
    [self work:@"正在连接内置 GitHub 官方登录工具…" operation:^id(NSError **error) { return [self.github beginDeviceLogin:error]; } completion:^(NSDictionary *challenge, NSError *error) {
        if (!challenge) {self.loginActive=NO;[self updateCourseSetup:error.localizedDescription ?: @"连接暂缓，可以稍后重试。"];return;}
        if(self.operationsPaused || !self.setupWindow)[self.github cancelDeviceLogin];
        self.loginChallenge=challenge;[self updateCourseSetup:@"请复制验证码并打开 GitHub。完成网页授权后自动继续。"];
        [self work:@"等待浏览器登录并核验账户…" operation:^id(NSError **innerError) { return @([self.github completeDeviceLogin:challenge error:innerError]); } completion:^(NSNumber *ok, NSError *innerError) {
            self.loginActive=NO;self.loginChallenge=nil;
            if(!ok.boolValue){[self updateCourseSetup:innerError.localizedDescription ?: @"登录未完成，请重试。"];return;}
            self.connected=YES;[self configureCredentialAccess];[self refreshPresentation];
            if(!self.operationsPaused && self.setupWindow)[self addFork:nil];
        }];[self updateCourseSetup:@"等待你在 GitHub 完成登录…"];
    }];[self updateCourseSetup:@"正在获取验证码…"];
}
- (void)cancelLogin:(id)sender { if (self.loginActive) { [self.github cancelDeviceLogin]; [self status:@"正在取消登录…"]; } }
- (void)signOut:(id)sender { if (self.busy || self.preview || self.operationsPaused) return; [self.github signOut]; self.connected = NO; [self refreshPresentation]; [self status:@"已退出登录；本地课程和 DDL 已保留。"] ; }
- (void)addFork:(id)sender {
    if(!self.connected){[self setup:nil];return;}
    [self work:@"正在读取个人课程 fork…" forCourse:nil operation:^id(NSError **error){return [self.github accessibleForks:error];} completion:^(NSArray *forks,NSError *error){
        if(!forks){[self updateCourseSetup:error.localizedDescription];return;}self.availableForks=forks;self.setupStep=1;self.setupRecords=NSMutableArray.array;
        for(NSDictionary *repo in forks){NSMutableDictionary *row=[@{@"fork":repo[@"full_name"],@"existing":@([self courseExists:repo[@"full_name"]])} mutableCopy];[self.setupRecords addObject:row];}
        [self presentCourseSetup];NSMutableArray *selected=NSMutableArray.array;for(NSDictionary *row in self.setupRecords)if(self.setupSelection ? [self.setupSelection containsObject:row[@"fork"]]:[row[@"existing"] boolValue])[selected addObject:row[@"fork"]];self.setupSelection=selected;[self.setupWorkspace updateContext:@{@"selected":selected}];[self updateCourseSetup:@"已添加课程默认选中；选择需要管理的其他个人 fork。"];
    }];
}
- (BOOL)courseExists:(NSString *)fork { for (NSDictionary *course in self.courses) if ([course[@"fork"] caseInsensitiveCompare:fork] == NSOrderedSame) return YES; return NO; }
- (void)linkFolder:(id)sender {
    NSDictionary *current = [self course]; if (!current) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = YES; panel.canChooseFiles = NO; panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK) return;
    NSMutableDictionary *course = [current mutableCopy]; course[@"path"] = panel.URL.path;
    [self work:@"正在检查仓库和私有上游读取权限…" operation:^id(NSError **error) { return @([self.git linkCourse:course error:error]); } completion:^(NSNumber *ok, NSError *error) {
        if (!ok.boolValue) { [self showError:error]; return; }
        NSMutableDictionary *saved = [self savedCourse:current]; [saved setDictionary:course]; [self saveCourses]; [self refreshCourses];
        [self status:@"本地仓库已关联，上游读取权限正常。"];
    }];
}
- (void)cloneFork:(id)sender {
    NSDictionary *current = [self course]; if (!current) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories = YES; panel.canChooseFiles = NO; panel.message = @"选择存放课程仓库的父文件夹";
    if ([panel runModal] != NSModalResponseOK) return;
    NSString *destination = [panel.URL.path stringByAppendingPathComponent:[current[@"fork"] lastPathComponent]];
    NSMutableDictionary *course = [current mutableCopy]; course[@"path"] = destination;
    if([self.github.authType isEqual:@"oauth"])course[@"upstreamURL"]=[NSString stringWithFormat:@"https://github.com/%@.git",course[@"upstream"]];
    else {NSAlert *transport = [NSAlert new]; transport.messageText = @"使用哪种本机凭据读取老师上游？";
    transport.informativeText = @"私有上游需要这台 Mac 已配置的访问权限。公开上游可直接用 HTTPS。";
    [transport addButtonWithTitle:@"HTTPS · Git 钥匙串"]; [transport addButtonWithTitle:@"SSH · 本机密钥"]; [transport addButtonWithTitle:@"取消"];
    NSModalResponse response = [transport runModal]; if (response == NSAlertThirdButtonReturn) return;
    course[@"upstreamURL"] = response == NSAlertSecondButtonReturn ? [NSString stringWithFormat:@"git@github.com:%@.git", course[@"upstream"]] : [NSString stringWithFormat:@"https://github.com/%@.git", course[@"upstream"]];}
    [self work:@"正在克隆自己的 fork 并验证老师上游…" operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return nil;
        if (![self.git cloneFork:course into:destination token:token error:error]) return @{@"cloned":@NO};
        return @{@"cloned":@YES, @"linked":@([self.git linkCourse:course error:error])};
    } completion:^(NSDictionary *result, NSError *error) {
        if ([result[@"cloned"] boolValue]) { [[self savedCourse:current] setDictionary:course]; [self saveCourses]; [self refreshCourses]; }
        if (![result[@"linked"] boolValue]) { [self showError:error]; return; }
        [self status:@"克隆成功，上游读取权限正常。"];
    }];
}
- (void)removeCourse:(id)sender {
    NSUInteger index = [self.courses indexOfObject:[self savedCourse:[self course]]]; if (index == NSNotFound) return;
    NSAlert *alert = [NSAlert new]; alert.messageText = @"移除课程关联？"; alert.informativeText = @"不会删除本地仓库或已导入的 DDL。";
    [alert addButtonWithTitle:@"移除"]; [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [self.courses removeObjectAtIndex:index]; [self saveCourses]; [self refreshCourses];
}
- (void)scan:(id)sender { if (![self course]) [self scanAll:nil]; else if ([self course]) [self scanCourses:@[[[self course] copy]]]; }
- (void)toggleCourse:(id)sender {
    NSMutableDictionary *course = [self savedCourse:[self course]]; if (!course) return;
    course[@"enabled"] = @(course[@"enabled"] ? ![course[@"enabled"] boolValue] : NO); [self saveCourses]; [self refreshCourses];
}
- (void)installApp:(id)sender {
    NSURL *url = [NSURL URLWithString:self.github.installationURL];
    if ([url.scheme isEqual:@"https"] && [url.host isEqual:@"github.com"] && [url.path hasPrefix:@"/apps/"]) [NSWorkspace.sharedWorkspace openURL:url];
    else [self status:@"尚未配置安装页面。开发者请按仓库 docs/GITHUB_APP_SETUP.md 注册后填写公开安装链接。"];
}
- (void)scanAll:(id)sender {
    if(!self.connected || self.setupWindow.sheetParent)return;
    NSMutableArray *enabled = NSMutableArray.array;
    for (NSDictionary *course in self.courses) if (!course[@"enabled"] || [course[@"enabled"] boolValue]) [enabled addObject:[course copy]];
    [self scanCourses:enabled];
}
- (void)scanCourses:(NSArray *)courses {
    if (!courses.count) return;
    courses = [[NSArray alloc] initWithArray:courses copyItems:YES];
    NSDictionary *recognitionSettings = self.preview ? @{@"mode":@"rules",@"automaticImport":@NO} : SSRecognitionSettings();
    [self work:@"正在扫描老师仓库…" forCourse:courses.count == 1 ? courses.firstObject : nil operation:^id(NSError **error) {
        self.git.recognitionSettings = @{@"mode":@"rules"};
        NSMutableDictionary *cache = [SSReadPlist(@"scan-cache.plist") isKindOfClass:NSDictionary.class] ? [SSReadPlist(@"scan-cache.plist") mutableCopy] : NSMutableDictionary.dictionary;
        NSMutableDictionary *result = NSMutableDictionary.dictionary;
        for (NSDictionary *course in courses) {
            if (![course[@"path"] length]){result[course[@"fork"]]=@{@"error":@"尚未关联目录，请先关联文件夹。"};continue;}
            dispatch_async(dispatch_get_main_queue(),^{self.operationFork=course[@"fork"];self.statusFork=course[@"fork"];[self status:@"获取老师内容并进行规则识别…"];});
            NSError *scanError = nil;
            NSDictionary *scan = [self.git scanCourse:course cache:cache error:&scanError];
            if(scan){NSDictionary *rules=scan;dispatch_async(dispatch_get_main_queue(),^{if(self.hasUnsavedReview)return;self.candidates[course[@"fork"]]=[self retainingSkill:self.candidates[course[@"fork"]] current:rules[@"candidates"] documents:rules[@"documents"]];self.materials[course[@"fork"]]=[self retainingSkill:self.materials[course[@"fork"]] current:rules[@"materials"] documents:rules[@"documents"]];[self status:[SSCourseRecognitionSettings(recognitionSettings,course)[@"mode"] isEqual:@"rules"] ? @"规则结果已显示，正在整理结果…":@"规则结果已显示，正在补充模型分析…"];});
                scan=[self.git enhanceScan:scan course:course settings:recognitionSettings paths:nil cache:cache];}
            result[course[@"fork"]] = scan ?: @{@"error":scanError.localizedDescription ?: @"扫描失败",@"detail":scanError.userInfo[@"SSDetail"] ?: scanError.localizedDescription ?: @"",@"issue":scanError.userInfo[@"SSIssue"] ?: @"git"};
        }
        SSWritePlist(@"scan-cache.plist", cache, NULL);
        return result;
    } completion:^(NSDictionary *result, NSError *error) {
        if (!result) { [self showError:error]; return; }
        NSMutableArray *messages = NSMutableArray.array;
        NSMutableDictionary *reports = [self.reports mutableCopy] ?: NSMutableDictionary.dictionary; [reports addEntriesFromDictionary:result]; self.reports = reports;
        for (NSMutableDictionary *course in self.courses) {
            NSDictionary *scan = result[course[@"fork"]]; if (!scan) continue;
            if (scan[@"error"]) { self.errorDetails[course[@"fork"]]=scan[@"detail"] ?: scan[@"error"];self.statuses[course[@"fork"]] = [@"未完成检查：" stringByAppendingString:scan[@"error"]]; [messages addObject:[NSString stringWithFormat:@"%@: %@", course[@"fork"], scan[@"error"]]]; continue; }
            if(self.hasUnsavedReview){if(!self.deferredScans)self.deferredScans=NSMutableDictionary.dictionary;self.deferredScans[course[@"fork"]]=scan;}else {self.candidates[course[@"fork"]] = [self retainingSkill:self.candidates[course[@"fork"]] current:scan[@"candidates"] documents:scan[@"documents"]]; self.materials[course[@"fork"]] = [self retainingSkill:self.materials[course[@"fork"]] current:scan[@"materials"] ?: @[] documents:scan[@"documents"]];}
            NSUInteger exams=0,classroom=0,unknown=0;for(NSDictionary *material in scan[@"materials"]){if([material[@"kind"] isEqual:@"exam"])exams++;else if([material[@"kind"] isEqual:@"classroom"])classroom++;else unknown++;}
            self.statuses[course[@"fork"]]=[NSString stringWithFormat:@"%@；%lu 组考试，%lu 项课上任务，%lu 项待确认类型，%lu 个文件跳过",[scan[@"candidates"] count] ? [NSString stringWithFormat:@"发现 %lu 项课后作业",[scan[@"candidates"] count]]:@"未发现课后作业",(unsigned long)exams,(unsigned long)classroom,(unsigned long)unknown,[scan[@"skipped"] count]];
            if([recognitionSettings[@"mode"] isEqual:@"local"] && scan[@"modelCompleted"]){SSWritePlist(@"recognition-last-result.plist",@{@"course":course[@"fork"],@"date":NSDate.date,@"model":recognitionSettings[@"model"] ?: @"",@"success":scan[@"modelCompleted"]},NULL);}
            if([recognitionSettings[@"mode"] isEqual:@"local"] && [scan[@"modelCompleted"] boolValue])self.statuses[course[@"fork"]]=[self.statuses[course[@"fork"]] stringByAppendingString:@" · 本地模型分析完成"];
            if ([scan[@"recognitionMessages"] count]) self.statuses[course[@"fork"]] = [self.statuses[course[@"fork"]] stringByAppendingFormat:@" · %@",[scan[@"recognitionMessages"] firstObject]];
            course[@"lastScan"] = scan[@"date"];
            if (scan[@"branch"]) course[@"upstreamBranch"] = scan[@"branch"];
            [messages addObject:[NSString stringWithFormat:@"%@：%lu 项建议，%lu 个文件跳过", course[@"fork"], [scan[@"candidates"] count], [scan[@"skipped"] count]]];
        }
        if (!self.preview) SSWritePlist(@"discoveries.plist", [self discoveryEnvelope], NULL);
        if ([recognitionSettings[@"automaticImport"] boolValue] && self.saveReviewItems && !self.hasUnsavedReview && !self.operationsPaused) {
            NSMutableArray *items = NSMutableArray.array;
            for (NSDictionary *course in courses) for (NSDictionary *record in [self discoveriesForFork:course[@"fork"]]) if (SSCanAutomaticallyImport(record,self.tasksProvider ? self.tasksProvider() : @[],NSDate.date)) [items addObject:@{@"record":record,@"draft":@{}}];
            if (items.count) {NSUInteger before=self.tasksProvider ? self.tasksProvider().count : 0;NSString *message=self.saveReviewItems(items,YES); if (message.length) [messages addObject:message]; else {NSString *notice=[NSString stringWithFormat:@"自动加入 %lu 项完整日期作业；可在“任务”菜单撤销本次加入。",(unsigned long)MAX((NSInteger)0,(NSInteger)(self.tasksProvider ? self.tasksProvider().count : 0)-(NSInteger)before)];[messages addObject:notice];for(NSDictionary *course in courses)self.statuses[course[@"fork"]]=[self.statuses[course[@"fork"]] stringByAppendingFormat:@" · %@",notice];} }
        }
        [self saveCourses]; [self refreshCourses];
        if(self.firstCheckRunning){self.firstCheckRunning=NO;for(NSMutableDictionary *row in self.setupRecords){NSDictionary *scan=result[row[@"fork"]];if(!scan)continue;row[@"status"]=self.statuses[row[@"fork"]] ?: @"检查已完成";row[@"detail"]=scan[@"detail"] ?: @"";row[@"invalid"]=@([scan[@"error"] length]>0);}[self updateCourseSetup:@"首次检查结束。可重试失败课程，或完成并查看使用提示。"];}
        if (courses.count > 1) self.statuses[@"all"] = messages.count ? [messages componentsJoinedByString:@"；"] : @"尚未关联可扫描的仓库。"; else if (!messages.count) [self status:@"请先关联本地课程文件夹，再检查作业。"];
    }];
}
- (void)sync:(id)sender {
    NSDictionary *course = [[self course] copy]; if (!course) return;
    [self work:@"正在安全合并上游，并更新自己的 fork…" forCourse:course operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return nil;
        return [self.git syncCourse:course token:token error:error];
    } completion:^(NSDictionary *result, NSError *error) {
        if (result[@"conflicts"]) {
            NSMutableDictionary *saved = [self savedCourse:course]; saved[@"pendingMergeTip"] = result[@"mergeHead"]; saved[@"pendingConflicts"] = result[@"conflicts"]; [self saveCourses];
            [self showError:error]; if (!self.operationsPaused && [self.selectedFork isEqual:course[@"fork"]] && !self.window.attachedSheet) [self conflictGuide:course];
        }
        else if (!result) { if ([error.userInfo[@"SSPendingPush"] boolValue]) { [self savedCourse:course][@"pushFailed"] = @YES; [self saveCourses]; } [self showError:error]; }
        else { [[self savedCourse:course] removeObjectForKey:@"pushFailed"]; [self saveCourses]; [self status:@"课程文件已同步到本地与个人仓库，正在检查新作业"]; [self scanCourses:@[course.copy]]; }
    }];
}
- (void)continueMerge:(id)sender { NSDictionary *course = [[self course] copy]; if (course) [self conflictGuide:course]; }
- (void)finishMerge:(NSDictionary *)course {
    [self work:@"正在完成合并并更新自己的 fork…" forCourse:course operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return @NO;
        return @([self.git continueMergeForCourse:course token:token error:error]);
    } completion:^(NSNumber *ok, NSError *error) { if (ok.boolValue || [error.userInfo[@"SSPendingPush"] boolValue]) { NSMutableDictionary *saved = [self savedCourse:course]; [saved removeObjectForKey:@"pendingMergeTip"]; [saved removeObjectForKey:@"pendingConflicts"]; [self saveCourses]; if (ok.boolValue) [self status:@"冲突合并已完成，并已推送到自己的 fork。"]; else { saved[@"pushFailed"] = @YES; [self saveCourses]; [self showError:error]; } } else [self showError:error]; }];
}
- (void)openFolder:(id)sender { NSString *path = [self course][@"path"]; if (path.length) [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:path]]; }
- (void)report:(id)sender {
    NSDictionary *course = [self course], *report = course ? self.reports[course[@"fork"]] : nil;
    NSMutableArray *parts = NSMutableArray.array;
    if (course) [parts addObject:[NSString stringWithFormat:@"老师：%@ / %@\n个人 fork：%@ / %@\n本地：%@\n时区：%@", course[@"upstream"], course[@"upstreamBranch"], course[@"fork"], course[@"branch"], course[@"path"] ?: @"未关联", course[@"timeZone"] ?: NSTimeZone.localTimeZone.name]];
    if (report[@"error"]) [parts addObject:report[@"error"]];
    if ([report[@"skipped"] count]) [parts addObject:[@"跳过的文件：\n" stringByAppendingString:[report[@"skipped"] componentsJoinedByString:@"\n"]]];
    self.detail.string = parts.count ? [parts componentsJoinedByString:@"\n\n"] : @"还没有检查结果。";
}
- (void)push:(id)sender {
    NSDictionary *course = [[self course] copy]; if (!course) return;
    [self work:@"正在检查待推送历史和 fork 身份…" forCourse:course operation:^id(NSError **error) {
        NSString *token = [self.github accessToken:error]; if (!token) return @NO;
        return @([self.git pushCourse:course token:token error:error]);
    } completion:^(NSNumber *ok, NSError *error) { if (ok.boolValue) { [[self savedCourse:course] removeObjectForKey:@"pushFailed"]; [self saveCourses]; [self status:@"本地提交已推送到自己的仓库"]; } else [self showError:error]; }];
}
- (void)conflictGuide:(NSDictionary *)course {
    [self work:@"正在读取冲突状态…" forCourse:course operation:^id(NSError **error) { return [self.git conflicts:course error:error]; } completion:^(NSArray *files, NSError *error) {
        if (self.operationsPaused) return;
        if (!files) { [self showError:error]; return; }
        if (![course[@"pendingMergeTip"] length]) { [self status:@"没有本应用记录的上游合并。请自行处理现有 Git 状态。"] ; return; }
        NSAlert *alert = NSAlert.new; alert.messageText = @"上游合并冲突引导";
        alert.informativeText = files.count ? @"在编辑器中打开文件，保留需要的内容并删除冲突标记。保存后勾选文件，点击“标记已解决”；全部解决后再完成合并。" : @"冲突文件已经标记解决。可以完成合并，然后检查并推送到自己的 fork。";
        NSView *list = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 550, MAX(30, files.count * 26))];
        NSMutableArray<NSButton *> *checks = NSMutableArray.array;
        for (NSUInteger i = 0; i < files.count; i++) {
            NSButton *check = [NSButton checkboxWithTitle:files[i] target:nil action:NULL]; check.frame = NSMakeRect(0, NSHeight(list.frame) - (i + 1) * 26, 545, 24); [list addSubview:check]; [checks addObject:check];
        }
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 570, MIN(260, NSHeight(list.frame)))]; scroll.hasVerticalScroller = YES; scroll.documentView = list; alert.accessoryView = scroll;
        [alert addButtonWithTitle:files.count ? @"标记已解决" : @"完成合并并推送"]; [alert addButtonWithTitle:@"打开仓库文件夹"]; [alert addButtonWithTitle:@"撤销本次合并"]; [alert addButtonWithTitle:@"关闭"];
        NSModalResponse answer = [alert runModal];
        if (answer == NSAlertSecondButtonReturn) { [NSWorkspace.sharedWorkspace openURL:[NSURL fileURLWithPath:course[@"path"]]]; return; }
        if (answer == NSAlertThirdButtonReturn) {
            NSAlert *confirm = NSAlert.new; confirm.messageText = @"撤销此次上游合并？"; confirm.informativeText = @"本次冲突解决中的编辑可能被撤销。Git 会回到合并前的状态。";
            [confirm addButtonWithTitle:@"撤销合并"]; [confirm addButtonWithTitle:@"保留"];
            if ([confirm runModal] != NSAlertFirstButtonReturn) return;
            [self work:@"正在撤销此次合并…" forCourse:course operation:^id(NSError **innerError) { return @([self.git abortMerge:course error:innerError]); } completion:^(NSNumber *ok, NSError *innerError) {
                if (!ok.boolValue) { [self showError:innerError]; return; }
                NSMutableDictionary *saved = [self savedCourse:course]; [saved removeObjectForKey:@"pendingMergeTip"]; [saved removeObjectForKey:@"pendingConflicts"]; [self saveCourses]; [self status:@"已撤销此次上游合并。"];
            }]; return;
        }
        if (answer != NSAlertFirstButtonReturn) return;
        if (!files.count) { [self finishMerge:course]; return; }
        NSMutableArray *selected = NSMutableArray.array;
        for (NSUInteger i = 0; i < checks.count; i++) if (checks[i].state == NSControlStateValueOn) [selected addObject:files[i]];
        if (!selected.count) { [self status:@"请选择已经编辑并保存的冲突文件。"] ; return; }
        [self work:@"正在检查并标记冲突文件…" forCourse:course operation:^id(NSError **innerError) { return @([self.git stageResolvedFiles:course paths:selected error:innerError]); } completion:^(NSNumber *ok, NSError *innerError) { if (!ok.boolValue) [self showError:innerError]; else [self conflictGuide:course]; }];
    }];
}
- (void)commit:(id)sender {
    NSDictionary *course = [[self course] copy]; if (!course) return;
    [self work:@"正在读取本地修改…" forCourse:course operation:^id(NSError **error) { return [self.git changesForCourse:course error:error]; } completion:^(NSArray *changes, NSError *error) {
        if (!changes) { [self showError:error]; return; }
        if (self.operationsPaused) return;
        if (!changes.count) { [self status:@"没有需要提交的改动。"] ; return; }
        if (self.window.attachedSheet) { [self status:@"请先关闭当前编辑弹窗，再打开“提交作业”。"]; return; }
        self.submission = [[SSSubmissionController alloc] initWithCourse:course changes:changes];
        __weak typeof(self) weakSelf = self;
        self.submission.readPreview = ^(NSString *file, void (^ready)(NSString *)) {
            dispatch_async(weakSelf.queue, ^{ NSError *previewError = nil; NSString *text = [weakSelf.git previewForCourse:course path:file error:&previewError]; dispatch_async(dispatch_get_main_queue(), ^{ ready(text ?: previewError.localizedDescription); }); });
        };
        self.submission.submit = ^(NSArray *paths, NSString *message) {
            SSCourseController *self = weakSelf; if (!self) return;
        [self work:@"正在检查、提交并推送到自己的 fork…" forCourse:course operation:^id(NSError **innerError) {
            NSDictionary *user = [self.github user:innerError]; if (!user) return @NO;
            NSString *token = [self.github accessToken:innerError]; if (!token) return @NO;
            return @([self.git commitCourse:course paths:paths message:message login:user[@"login"] userID:user[@"id"] token:token error:innerError]);
        } completion:^(NSNumber *ok, NSError *innerError) {
            if (self.exitSubmissionInFlight) { self.submissionFailedDuringExit = !ok.boolValue; self.exitSubmissionInFlight = NO; }
            if (ok.boolValue) { [[self savedCourse:course] removeObjectForKey:@"pushFailed"]; [self saveCourses]; [self status:@"所选文件已提交到自己的仓库"]; }
            else {
                if ([innerError.userInfo[@"SSPendingPush"] boolValue]) { [self savedCourse:course][@"pushFailed"] = @YES; [self saveCourses]; }
                else if (!self.window.attachedSheet) {
                    self.submission.validation.stringValue = innerError.localizedDescription ?: @"提交未完成，请检查后重试。";
                    self.submission.validation.textColor = NSColor.systemRedColor;
                    [self.window beginSheet:self.submission.window completionHandler:nil];
                }
                [self showError:innerError];
            }
        }];
        };
        [self.window beginSheet:self.submission.window completionHandler:nil];
    }];
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.visible.count; }
- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSDictionary *candidate = self.visible[row]; NSString *key = column.identifier;
    NSString *value = @"";
    if ([key isEqual:@"title"]) value = candidate[@"title"];
    else if ([key isEqual:@"due"]) value = candidate[@"deadlineText"] ? [candidate[@"deadlineText"] stringByAppendingString:@" · 待确认"] : (candidate[@"dateOnly"] && [candidate[@"needsTime"] boolValue] ? [candidate[@"dateOnly"] stringByAppendingString:@" · 待补时间"] : (!candidate[@"due"] ? @"未说明时间" : ([candidate[@"needsDate"] boolValue] ? @"日期待确认" : DDLFormatDate(candidate[@"due"], @"yyyy-MM-dd HH:mm"))));
    else if ([key isEqual:@"source"]) value = [NSString stringWithFormat:@"%@:%@", candidate[@"path"], candidate[@"line"]];
    else if ([key isEqual:@"state"]) { NSString *state = [self stateForCandidate:candidate]; value = [candidate[@"confirmed"] boolValue] ? ([candidate[@"completed"] boolValue] ? @"✓ 已完成" : @"○ 待完成") : [NSString stringWithFormat:@"%@ %@", [state isEqual:@"已导入"] ? @"✓" : ([state isEqual:@"有更新"] ? @"↻" : @"○"), state]; }
    NSTextField *label = Text(value ?: @"", 13, NSFontWeightRegular, Ink()); label.lineBreakMode = NSLineBreakByTruncatingMiddle; label.toolTip = value; return label;
}
- (NSString *)stateForCandidate:(NSDictionary *)candidate {
    if (candidate[@"kind"] && ![candidate[@"kind"] isEqual:@"assignment"]) return SSActivityKindLabel(candidate[@"kind"]);
    for (NSDictionary *task in self.tasksProvider ? self.tasksProvider() : @[]) if ([task[@"sourceID"] isEqual:candidate[@"id"]])
        return [task[@"sourceBlobSHA"] isEqual:candidate[@"blobSHA"]] ? @"已导入" : @"有更新";
    return @"待审核";
}
- (void)tableViewSelectionDidChange:(NSNotification *)notification { if (!self.refreshing) [self candidateSelected:nil]; }
- (void)candidateSelected:(id)sender {
    NSInteger row = self.table.selectedRow;
    NSDictionary *candidate = row >= 0 && row < (NSInteger)self.visible.count ? self.visible[row] : nil;
    BOOL assignment = !candidate[@"kind"] || [candidate[@"kind"] isEqual:@"assignment"];
    if(candidate)self.selectedCandidateID = candidate[@"id"]; BOOL canStart = self.inbox && !candidate && self.pendingReviewCandidates.count > 0;
    self.reviewButton.enabled = canStart || (candidate != nil && (assignment || [candidate[@"confirmed"] boolValue])); self.reviewButton.title = canStart ? @"开始审核…" : ([candidate[@"confirmed"] boolValue] ? @"编辑任务…" : @"审核作业…");
    self.reviewButton.toolTip = @"按当前课程和搜索筛选逐项审核；Return 保存并下一项";
    self.typeButton.enabled = candidate != nil && ![candidate[@"confirmed"] boolValue] && !self.busy && !self.operationsPaused;
    NSMutableString *preview = NSMutableString.string;
    if (candidate) {
        [preview appendFormat:@"%@ · %@ · %@\n%@\n", SSActivityKindLabel(candidate[@"kind"] ?: @"assignment"), candidate[@"repository"] ?: candidate[@"sourceRepository"], candidate[@"kindReason"] ?: @"", [candidate[@"warnings"] componentsJoinedByString:@"；"] ?: @""];
        NSArray *documents = candidate[@"documents"] ?: @[candidate];
        for (NSDictionary *document in documents) [preview appendFormat:@"%@:%@\n%@\n\n", document[@"path"], document[@"line"], document[@"snippet"] ?: document[@"notes"] ?: @""];
    }
    self.detail.string = candidate ? preview : @"选择课程内容，查看类型、老师原文与位置。";
}
- (void)review:(id)sender {
    if(self.busy || self.operationsPaused)return;
    NSDictionary *candidate=nil;
    for(NSDictionary *record in self.visible)if([record[@"id"] isEqual:self.selectedCandidateID]){candidate=record;break;}
    if(!candidate && self.inbox)candidate=self.pendingReviewCandidates.firstObject;
    if(!candidate || (candidate[@"kind"] && ![candidate[@"kind"] isEqual:@"assignment"] && ![candidate[@"confirmed"] boolValue]))return;
    // Both entry points select the inline form, never an AppKit review sheet.
    BOOL selected=self.inbox ? [self.reviewWorkspace selectRecordWithID:candidate[@"id"]] : [self.courseWorkspace selectRecordWithID:candidate[@"id"]];
    if(!selected)[self status:@"请先处理当前未保存修改，再选择作业。"];
}

@end
