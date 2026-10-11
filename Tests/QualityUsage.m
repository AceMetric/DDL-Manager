#import "QuietUI.h"
#define main DDLApplicationMain
#import "../Sources/App.m"
#undef main
#import "../Sources/SSCourseWindow.m"
static NSUInteger checks;
static void Check(BOOL ok,NSString *text){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",text.UTF8String);exit(1);}}
@interface QualityApp:AppDelegate @end
@implementation QualityApp
- (void)loadPreview {
    for(NSUInteger i=0;i<2000;i++)[self.tasks addObject:[@{@"id":[NSString stringWithFormat:@"task-%lu",(unsigned long)i],@"title":@"模拟任务与长标题",@"due":[NSDate dateWithTimeIntervalSinceNow:3600+i*20],@"subject":@"模拟课程",@"notes":[@"长备注\n" stringByPaddingToLength:4000 withString:@"备注文本\n" startingAtIndex:0],@"completed":@NO,@"archived":@NO,@"reminderOffsets":@[]} mutableCopy]];
}
- (void)refreshReminders {}
@end
int main(void){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"].length>0,@"quality UI isolated storage");
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];NSDate *start=NSDate.date;QualityApp *app=QualityApp.new;[app applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:NSApp]];NSTimeInterval startup=-start.timeIntervalSinceNow;
    Check(app.tasks.count==2000,@"two thousand task startup fixture");Check(startup<2,@"offline usable startup below two seconds");Check(app.document.subviews.count<40,@"overview creates only viewport task rows");
    NSMutableArray *courses=NSMutableArray.array;for(NSUInteger i=0;i<20;i++)[courses addObject:@{@"fork":[NSString stringWithFormat:@"student/course-%lu",(unsigned long)i],@"upstream":[NSString stringWithFormat:@"teacher/course-%lu",(unsigned long)i]}];app.courseWindow.courses=courses;
    NSButton *route=NSButton.new;route.tag=2;[app navigate:route];start=NSDate.date;[app renderContent];NSTimeInterval render=-start.timeIntervalSinceNow;Check(render<0.1,@"task page render below one hundred milliseconds");Check(app.document.subviews.count<30,@"task list row creation bounded");
    [app.scroll.contentView scrollToPoint:NSMakePoint(0,40000)];[app taskScrolled:nil];Check(app.document.subviews.count>1 && app.document.subviews.count<30,@"virtual list rebuilds rows after scrolling");
    start=NSDate.date;app.query=@"模拟";[app renderContent];NSTimeInterval search=-start.timeIntervalSinceNow;Check(search<0.1,@"two thousand task search below one hundred milliseconds");
    NSButton *selection=NSButton.new;selection.identifier=app.tasks[450][@"id"];start=NSDate.date;[app selectTask:selection];NSTimeInterval select=-start.timeIntervalSinceNow;Check(select<0.1,@"selected long-note detail below one hundred milliseconds");Check([app.selectedTaskID isEqual:selection.identifier],@"stable selected identity");
    for(NSString *appearance in @[NSAppearanceNameAqua,NSAppearanceNameDarkAqua]){app.window.appearance=[NSAppearance appearanceNamed:appearance];[app.window setContentSize:NSMakeSize(960,640)];[app layout];Check(app.selectedTaskID.length>0,@"appearance and compact layout preserve selection");}
    [app.window makeFirstResponder:app.search];[app render];Check(app.window.firstResponder!=nil,@"background presentation retains input responder");
    app.taskStoreBlocked=YES;app.preview=NO;NSError *error=nil;Check(![app replaceTasks:@[] action:@"不应覆盖" error:&error] && error,@"corrupt-store state blocks replacement");app.preview=YES;app.taskStoreBlocked=NO;
    SSCourseController *controller=app.courseWindow;[controller showSkillJobs:nil];Check(controller.showingSkillJobs && !controller.skillJobsController.view.hidden,@"Skill status opens embedded page");[controller skillJobAction:@"close" batch:@""];Check(!controller.showingSkillJobs,@"Skill page closes without new window");
    controller.preview=NO;NSString *done=NSUUID.UUID.UUIDString,*pending=NSUUID.UUID.UUIDString;controller.skillJobs[done]=@{@"state":@"已接回",@"date":[NSDate dateWithTimeIntervalSinceNow:-31*86400],@"count":@1};controller.skillJobs[pending]=@{@"state":@"等待助手",@"date":[NSDate dateWithTimeIntervalSinceNow:-31*86400],@"count":@1};controller.skillProgress[@"retained"]=@"version";
    for(NSString *key in @[done,pending])[NSFileManager.defaultManager createDirectoryAtURL:[controller skillFolder:key] withIntermediateDirectories:YES attributes:nil error:NULL];[controller cleanSkillJobs:NO];Check(![NSFileManager.defaultManager fileExistsAtPath:[controller skillFolder:done].path] && [NSFileManager.defaultManager fileExistsAtPath:[controller skillFolder:pending].path],@"cleanup removes only old completed materials");Check([controller.skillProgress[@"retained"] isEqual:@"version"],@"cleanup retains incremental progress");
    [app.ticker invalidate];[app.window orderOut:nil];[NSStatusBar.systemStatusBar removeStatusItem:app.statusItem];
    printf("TIMING: offline startup %.4fs; render %.4fs; search %.4fs; selection %.4fs; 2000 tasks, 20 courses\n",startup,render,search,select);
    printf("PASS: %lu quality UI and performance assertions\n",(unsigned long)checks);
}return 0;}
