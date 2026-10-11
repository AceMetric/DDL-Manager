#import "SSGit.h"
#import "SSAssignments.h"
#import "SSRecognition.h"
#import "SSSecurity.h"
#import <signal.h>
#include <math.h>

static NSError *GitError(NSString *message) {
    NSString *detail=SSRedactedText(message ?: @"Git 操作失败"),*issue=@"git",*friendly=detail;
    if([detail containsString:@"Permission denied (publickey)"]){friendly=@"本机 SSH 身份验证失败。推荐切换到统一浏览器登录，无需配置 SSH。";issue=@"ssh";}
    else if([detail containsString:@"Authentication failed"] || [detail containsString:@"could not read Username"] || [detail containsString:@"Invalid username or token"]){friendly=@"GitHub 登录或凭据失效，请重新登录。";issue=@"login";}
    else if([detail containsString:@"Repository not found"]){friendly=@"无法读取课程仓库，请核对账户权限或学校授权。";issue=@"permission";}
    else if([detail containsString:@"Could not resolve host"] || [detail containsString:@"Failed to connect"] || [detail containsString:@"timed out"]){friendly=@"无法连接 GitHub，请检查网络后重试。";issue=@"network";}
    return [NSError errorWithDomain:@"SSGit" code:1 userInfo:@{NSLocalizedDescriptionKey:friendly,@"SSDetail":detail,@"SSIssue":issue}];
}
static NSError *PendingPushError(NSError *error) { return [NSError errorWithDomain:@"SSGit" code:2 userInfo:@{NSLocalizedDescriptionKey:[@"本地更新已保留，尚未推送。修复原因后选择“重试推送”：\n" stringByAppendingString:error.localizedDescription ?: @"网络或权限错误"], @"SSPendingPush":@YES}]; }
static NSString *Trim(NSString *value) { return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
static NSArray *NonemptyParts(NSString *value, NSString *separator) {
    NSMutableArray *parts = NSMutableArray.array;
    for (NSString *part in [value componentsSeparatedByString:separator]) if (part.length) [parts addObject:part];
    return parts;
}

@interface SSGitResult : NSObject
@property int status;
@property NSData *data;
@property NSString *diagnostic;
@end
@implementation SSGitResult @end

@interface SSGit ()
@property NSString *temporaryIndex;
@end
@implementation SSGit
- (SSGitResult *)run:(NSArray<NSString *> *)arguments in:(NSString *)path token:(NSString *)token error:(NSError **)error {
    NSDictionary *phases = @{@"fetch":@"正在获取仓库更新…", @"clone":@"正在下载课程仓库…", @"ls-tree":@"正在读取作业文档…", @"merge":@"正在合并老师更新…", @"commit":@"正在保存所选文件的提交…", @"push":@"正在推送到个人仓库…"};
    NSUInteger commandIndex = 0; while (commandIndex + 1 < arguments.count && [arguments[commandIndex] isEqual:@"-c"]) commandIndex += 2;
    NSString *phase = commandIndex < arguments.count ? phases[arguments[commandIndex]] : nil; if (self.progress && phase) self.progress(phase);
    if(self.readsCancellable && self.cancelledReads){if(error)*error=GitError(@"检查已取消，已有结果保留。");return nil;}
    NSTask *task = NSTask.new;
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/git"];
    NSMutableArray *args = [@[@"-c", @"core.hooksPath=/dev/null", @"-c", @"protocol.ext.allow=never", @"-c", @"http.followRedirects=false", @"-c", @"core.askPass=/usr/bin/false", @"-c", @"commit.gpgSign=false", @"-c", @"tag.gpgSign=false", @"-c", @"credential.helper=", @"-c", @"credential.useHttpPath=true"] mutableCopy];
    if (!token.length) [args addObjectsFromArray:@[@"-c", @"credential.helper=osxkeychain"]];
    [args addObjectsFromArray:arguments]; task.arguments = args;
    if (path.length) task.currentDirectoryURL = [NSURL fileURLWithPath:path isDirectory:YES];
    NSMutableDictionary *environment = NSProcessInfo.processInfo.environment.mutableCopy;
    for (NSString *key in environment.allKeys) if ([key hasPrefix:@"GIT_"] || [key hasPrefix:@"SS_GIT_"]) [environment removeObjectForKey:key];
    environment[@"GIT_CONFIG_GLOBAL"] = @"/dev/null";
    environment[@"GIT_CONFIG_NOSYSTEM"] = @"1";
    environment[@"GIT_TERMINAL_PROMPT"] = @"0";
    environment[@"GIT_OPTIONAL_LOCKS"] = @"0";
    environment[@"GIT_LITERAL_PATHSPECS"] = @"1";
    environment[@"GIT_SSH_COMMAND"] = @"/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=10 -o ServerAliveCountMax=3";
    if (self.temporaryIndex.length) environment[@"GIT_INDEX_FILE"] = self.temporaryIndex;
    if (token.length) {
        NSString *askpass = [NSBundle.mainBundle pathForResource:@"SSAskPass" ofType:@"sh"];
        if (!askpass.length) { if (error) *error = GitError(@"应用缺少 Git 授权辅助程序"); return nil; }
        NSString *destination=nil;for(NSString *argument in arguments)if([argument hasPrefix:@"https://"]){if(destination || !SSCanonicalRepository(argument)){if(error)*error=GitError(@"拒绝向未经核验的地址提供凭据");return nil;}destination=argument;}
        if(!destination || ![@[@"clone",@"fetch",@"push",@"ls-remote"] containsObject:arguments.firstObject]){if(error)*error=GitError(@"此操作不可使用网络凭据");return nil;}
        environment[@"GIT_ASKPASS"] = askpass; environment[@"SS_GIT_TOKEN"] = token;environment[@"SS_GIT_REPOSITORY"] = [@"github.com/" stringByAppendingString:SSCanonicalRepository(destination)];
    }
    task.environment = environment;
    NSPipe *output = NSPipe.pipe, *diagnostic = NSPipe.pipe;
    task.standardOutput = output; task.standardError = diagnostic;
    if (![task launchAndReturnError:error]) return nil;
    dispatch_group_t reading = dispatch_group_create();
    __block NSData *errorData;
    dispatch_group_async(reading, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{ errorData = [diagnostic.fileHandleForReading readDataToEndOfFile]; });
    dispatch_source_t timeout = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    BOOL safeToStop=[@[@"fetch",@"ls-tree",@"show",@"blame",@"log",@"cat-file",@"rev-parse",@"status",@"diff",@"ls-files",@"ls-remote",@"check-ref-format"] containsObject:arguments[commandIndex]];
    NSDate *launched=NSDate.date;
    dispatch_source_set_timer(timeout,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,0);
    dispatch_source_set_event_handler(timeout, ^{ if(safeToStop && task.running && (-launched.timeIntervalSinceNow>90 || (self.readsCancellable && self.cancelledReads))){[task terminate];kill(task.processIdentifier,SIGKILL);} });
    dispatch_resume(timeout);
    NSData *data = [output.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit]; dispatch_source_cancel(timeout);
    dispatch_group_wait(reading, DISPATCH_TIME_FOREVER);
    SSGitResult *result = SSGitResult.new;
    result.status = task.terminationStatus; result.data = data ?: NSData.data;
    NSString *text = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding] ?: @"";
    if (token.length) text = [text stringByReplacingOccurrencesOfString:token withString:@"[已隐藏凭据]"];
    result.diagnostic = SSRedactedText(text); return result;
}
- (NSString *)string:(SSGitResult *)result { return [[NSString alloc] initWithData:result.data encoding:NSUTF8StringEncoding] ?: @""; }
- (SSGitResult *)checked:(NSArray *)args in:(NSString *)path token:(NSString *)token error:(NSError **)error {
    SSGitResult *result = [self run:args in:path token:token error:error];
    if (!result) return nil;
    if (result.status != 0) { if (error) *error = GitError(Trim(result.diagnostic).length ? Trim(result.diagnostic) : @"Git 操作未成功；请检查仓库状态与本机访问权限。"); return nil; }
    return result;
}
- (BOOL)safeConfiguration:(NSString *)path error:(NSError **)error {
    SSGitResult *config = [self checked:@[@"config", @"--local", @"--no-includes", @"--name-only", @"--list"] in:path token:nil error:error]; if (!config) return NO;
    for (NSString *raw in [[self string:config] componentsSeparatedByString:@"\n"]) {
        NSString *key = raw.lowercaseString;
        BOOL unsafe = [key hasPrefix:@"url."] || [key hasPrefix:@"include."] || [key hasPrefix:@"includeif."] || [key hasPrefix:@"http."] || [key hasPrefix:@"filter."] || [key hasPrefix:@"credential."] || [key isEqual:@"core.askpass"] || [key isEqual:@"core.sshcommand"] || [key isEqual:@"core.gitproxy"] || [key isEqual:@"core.fsmonitor"] || [key isEqual:@"extensions.worktreeconfig"] || ([key hasPrefix:@"merge."] && [key hasSuffix:@".driver"]) || ([key hasPrefix:@"remote."] && ([key hasSuffix:@".vcs"] || [key hasSuffix:@".proxy"]));
        if (unsafe) { if (error) *error = GitError([NSString stringWithFormat:@"仓库含有会改变网络或执行行为的本地 Git 配置 %@，请先人工检查。", key]); return NO; }
    }
    return YES;
}
- (BOOL)validateCourse:(NSDictionary *)course error:(NSError **)error {
    NSString *path = course[@"path"], *fork = course[@"fork"], *teacher = course[@"upstream"];
    if (![path isKindOfClass:NSString.class] || !path.length || ![fork isKindOfClass:NSString.class] || ![teacher isKindOfClass:NSString.class] || ![SSCanonicalRepository([NSString stringWithFormat:@"https://github.com/%@.git", fork]) isEqual:fork.lowercaseString] || ![SSCanonicalRepository([NSString stringWithFormat:@"https://github.com/%@.git", teacher]) isEqual:teacher.lowercaseString] || !SSValidBranch(course[@"branch"] ?: @"") || !SSValidBranch(course[@"upstreamBranch"] ?: @"") || [fork caseInsensitiveCompare:teacher] == NSOrderedSame) {
        if (error) *error = GitError(@"课程配置无效，老师上游与自己的 fork 必须是两个不同的仓库。"); return NO;
    }
    if (![self safeConfiguration:path error:error]) return NO;
    SSGitResult *root = [self checked:@[@"rev-parse", @"--show-toplevel"] in:path token:nil error:error]; if (!root) return NO;
    if (![[Trim([self string:root]) stringByResolvingSymlinksInPath] isEqual:path.stringByResolvingSymlinksInPath]) { if (error) *error = GitError(@"请选择 Git 仓库的根文件夹。"); return NO; }
    for (NSString *remote in @[@"origin", @"upstream"]) {
        SSGitResult *url = [self checked:@[@"remote", @"get-url", remote] in:path token:nil error:error]; if (!url) return NO;
        NSString *expected = [remote isEqual:@"origin"] ? fork : teacher;
        if (![SSCanonicalRepository([self string:url]) isEqual:expected.lowercaseString]) { if (error) *error = GitError([NSString stringWithFormat:@"%@ 不是经过验证的%@，已阻止操作。", remote, [remote isEqual:@"origin"] ? @"个人 fork" : @"老师上游"]); return NO; }
    }
    return YES;
}
- (BOOL)submissionBranch:(NSDictionary *)course error:(NSError **)error {
    SSGitResult *branch = [self checked:@[@"symbolic-ref", @"--quiet", @"--short", @"HEAD"] in:course[@"path"] token:nil error:error]; if (!branch) return NO;
    if (![Trim([self string:branch]) isEqual:course[@"branch"]]) { if (error) *error = GitError([NSString stringWithFormat:@"请先切换到课程提交分支 %@。扫描老师作业不需要切换分支。", course[@"branch"]]); return NO; }
    return YES;
}
- (NSDictionary *)authorize:(NSDictionary *)course error:(NSError **)error {
    if (!self.identityVerifier) { if (error) *error = GitError(@"缺少 GitHub 身份核验，已阻止写操作。"); return nil; }
    NSDictionary *user = self.identityVerifier(course, error);
    NSString *login = user[@"login"];
    NSString *owner = [course[@"fork"] componentsSeparatedByString:@"/"].firstObject;
    if (!user || ![login isKindOfClass:NSString.class] || [login caseInsensitiveCompare:owner] != NSOrderedSame || ![user[@"id"] isEqual:course[@"ownerID"]]) { if (error && !*error) *error = GitError(@"目标 fork 不属于当前 GitHub 账户，已阻止写操作。"); return nil; }
    return user;
}
- (NSArray *)authorArguments:(NSDictionary *)user {
    NSString *login = user[@"login"], *email = [NSString stringWithFormat:@"%@+%@@users.noreply.github.com", user[@"id"], login];
    return @[@"-c", [@"user.name=" stringByAppendingString:login], @"-c", [@"user.email=" stringByAppendingString:email]];
}
- (NSArray *)remoteArguments:(NSArray *)arguments course:(NSDictionary *)course role:(NSString *)role error:(NSError **)error {
    BOOL teacher=[role isEqual:@"teacherRead"], read=[role isEqual:@"personalRead"], write=[role isEqual:@"personalPush"];
    NSString *repository=teacher ? course[@"upstream"] : course[@"fork"], *command=arguments.firstObject;
    NSArray *allowed=teacher ? @[@"fetch",@"ls-remote"] : (read ? @[@"fetch",@"clone",@"ls-remote"] : @[@"push"]);
    if((!teacher && !read && !write) || ![allowed containsObject:command] || !repository.length || [course[@"fork"] caseInsensitiveCompare:course[@"upstream"]]==NSOrderedSame){if(error)*error=GitError(@"操作与课程访问权限不符，已拒绝执行。");return nil;}
    NSString *expected=[NSString stringWithFormat:@"https://github.com/%@.git",repository];NSUInteger destinations=0;
    for(NSString *argument in arguments)if([argument containsString:@"://"] || [argument hasPrefix:@"git@"]){destinations++;if(![argument isEqual:expected]){if(error)*error=GitError(@"操作目标不是已核验的课程仓库，已停止。");return nil;}}
    if(destinations!=1){if(error)*error=GitError(@"课程网络操作必须指定唯一仓库。");return nil;}
    return arguments;
}
- (NSString *)teacherURL:(NSDictionary *)course path:(NSString *)path error:(NSError **)error {
    if(self.teacherCredentialProvider)return [NSString stringWithFormat:@"https://github.com/%@.git",course[@"upstream"]];
    SSGitResult *remote=[self checked:@[@"remote",@"get-url",@"upstream"] in:path token:nil error:error];return remote ? Trim([self string:remote]) : nil;
}
- (SSGitResult *)teacherRequest:(NSArray *)arguments course:(NSDictionary *)course error:(NSError **)error {
    NSString *token=nil;
    if(self.teacherCredentialProvider){
        if(![self remoteArguments:arguments course:course role:@"teacherRead" error:error])return nil;
        token=self.teacherCredentialProvider(course,error);if(!token.length)return nil;
    }
    return [self checked:arguments in:course[@"path"] token:token error:error];
}
- (NSDictionary *)matchingDirectories:(NSString *)root courses:(NSArray *)courses {
    NSMutableDictionary *result=NSMutableDictionary.dictionary;for(NSDictionary *course in courses)result[course[@"fork"]]=NSMutableArray.array;
    NSMutableArray *level=[NSMutableArray arrayWithObject:root];NSFileManager *manager=NSFileManager.defaultManager;
    for(NSUInteger depth=0;depth<=2;depth++){
        NSMutableArray *next=NSMutableArray.array;
        for(NSString *path in level){
            NSURL *url=[NSURL fileURLWithPath:path];NSNumber *symlink=nil;[url getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:NULL];if(symlink.boolValue)continue;
            if([manager fileExistsAtPath:[path stringByAppendingPathComponent:@".git"]]){
                SSGitResult *remote=[self run:@[@"config",@"--local",@"--no-includes",@"--get",@"remote.origin.url"] in:path token:nil error:NULL];NSString *identity=remote.status==0 ? SSCanonicalRepository([self string:remote]) : nil;
                for(NSDictionary *course in courses)if([identity isEqual:[course[@"fork"] lowercaseString]])[result[course[@"fork"]] addObject:path];continue;
            }
            if(depth<2)for(NSURL *child in [manager contentsOfDirectoryAtURL:url includingPropertiesForKeys:@[NSURLIsDirectoryKey,NSURLIsSymbolicLinkKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL]){NSNumber *directory=nil,*link=nil;[child getResourceValue:&directory forKey:NSURLIsDirectoryKey error:NULL];[child getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:NULL];if(directory.boolValue && !link.boolValue)[next addObject:child.path];}
        }level=next;
    }return result;
}
- (BOOL)linkCourse:(NSDictionary *)course error:(NSError **)error {
    NSString *path = course[@"path"];
    if (![self safeConfiguration:path error:error]) return NO;
    SSGitResult *origin = [self checked:@[@"remote", @"get-url", @"origin"] in:path token:nil error:error]; if (!origin) return NO;
    if (![SSCanonicalRepository([self string:origin]) isEqual:[course[@"fork"] lowercaseString]]) { if (error) *error = GitError(@"所选目录的 origin 不是自己的课程 fork。"); return NO; }
    SSGitResult *remote = [self run:@[@"remote", @"get-url", @"upstream"] in:path token:nil error:NULL];
    if (!remote || remote.status != 0) {
        NSString *url = course[@"upstreamURL"];
        if (!self.teacherCredentialProvider && ([Trim([self string:origin]) hasPrefix:@"git@"] || [Trim([self string:origin]) hasPrefix:@"ssh://"])) url = [NSString stringWithFormat:@"git@github.com:%@.git", course[@"upstream"]];
        if (![SSCanonicalRepository(url ?: @"") isEqual:[course[@"upstream"] lowercaseString]]) { if (error) *error = GitError(@"老师上游地址无效。"); return NO; }
        if (![self checked:@[@"remote", @"add", @"upstream", url] in:path token:nil error:error]) return NO;
    }
    if (![self validateCourse:course error:error]) return NO;
    NSString *url=[self teacherURL:course path:path error:error];if(!url)return NO;
    SSGitResult *heads = [self teacherRequest:@[@"ls-remote", @"--heads", @"--", url, [@"refs/heads/" stringByAppendingString:course[@"upstreamBranch"]]] course:course error:error];
    if (!heads || !Trim([self string:heads]).length) { if (error && !*error) *error = GitError(@"无法读取老师主分支。请在本机配置可用的 SSH 或 Git 钥匙串凭据。"); return NO; }
    return YES;
}
- (BOOL)cloneFork:(NSDictionary *)course into:(NSString *)destination token:(NSString *)token error:(NSError **)error {
    if (![self authorize:course error:error]) return NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:destination]) { if (error) *error = GitError(@"目标文件夹已存在；可以直接关联已克隆的仓库。"); return NO; }
    NSString *url = [NSString stringWithFormat:@"https://github.com/%@.git", course[@"fork"]];
    NSArray *clone=[self remoteArguments:@[@"clone",@"--origin",@"origin",@"--",url,destination] course:course role:@"personalRead" error:error];
    if(!clone || ![self checked:clone in:destination.stringByDeletingLastPathComponent token:token error:error])return NO;
    NSString *teacherURL = course[@"upstreamURL"];
    if (![SSCanonicalRepository(teacherURL ?: @"") isEqual:[course[@"upstream"] lowercaseString]]) { if (error) *error = GitError(@"老师上游地址无效。"); return NO; }
    if([self checked:@[@"remote",@"get-url",@"upstream"] in:destination token:nil error:NULL])return YES;
    return [self checked:@[@"remote", @"add", @"upstream", teacherURL] in:destination token:nil error:error] != nil;
}
- (NSString *)fetch:(NSString *)url branch:(NSString *)branch path:(NSString *)path token:(NSString *)token error:(NSError **)error {
    if (![self checked:@[@"fetch", @"--no-tags", @"--", url, [@"refs/heads/" stringByAppendingString:branch]] in:path token:token error:error]) return nil;
    SSGitResult *head = [self checked:@[@"rev-parse", @"FETCH_HEAD"] in:path token:nil error:error];
    return head ? Trim([self string:head]) : nil;
}
- (NSString *)teacherBranch:(NSString *)url course:(NSDictionary *)course error:(NSError **)error {
    SSGitResult *refs = [self teacherRequest:@[@"ls-remote", @"--symref", @"--", url, @"HEAD"] course:course error:error];
    if (!refs) return nil;
    for (NSString *line in [[self string:refs] componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"ref: refs/heads/"]) {
            NSString *ref = [[line componentsSeparatedByString:@"\t"] firstObject];
            NSString *branch = [ref substringFromIndex:@"ref: refs/heads/".length];
            if (SSValidBranch(branch)) return branch;
        }
    }
    if (error) *error = GitError(@"无法确认老师仓库的默认分支，已停止读取。"); return nil;
}
- (NSDictionary *)dateReferenceForCandidate:(NSDictionary *)candidate head:(NSString *)head path:(NSString *)path {
    if (![candidate[@"relative"] boolValue] || [candidate[@"needsTime"] boolValue]) return candidate;
    NSUInteger line = [candidate[@"line"] unsignedIntegerValue]; if (!line) return candidate;
    SSGitResult *blame = [self checked:@[@"blame", @"--no-textconv", @"--line-porcelain", @"-L", [NSString stringWithFormat:@"%lu,%lu", (unsigned long)line, (unsigned long)line], head, @"--", candidate[@"path"]] in:path token:nil error:nil];
    if (!blame) return candidate;
    NSArray *lines = [[self string:blame] componentsSeparatedByString:@"\n"];
    NSString *commit = [lines.firstObject componentsSeparatedByString:@" "].firstObject;
    if ([commit rangeOfString:@"^[a-f0-9]{40,64}$" options:NSRegularExpressionSearch].location == NSNotFound) return candidate;
    // A shallow boundary cannot establish when this line was introduced.
    SSGitResult *shallowFile = [self checked:@[@"rev-parse", @"--git-path", @"shallow"] in:path token:nil error:nil];
    if (!shallowFile) return candidate;
    NSString *boundaryPath = Trim([self string:shallowFile]); if (!boundaryPath.isAbsolutePath) boundaryPath = [path stringByAppendingPathComponent:boundaryPath];
    NSString *boundaries = [NSString stringWithContentsOfFile:boundaryPath encoding:NSUTF8StringEncoding error:nil];
    if ([[boundaries componentsSeparatedByString:@"\n"] containsObject:commit]) return candidate;
    NSTimeInterval timestamp = 0;
    for (NSString *entry in lines) if ([entry hasPrefix:@"committer-time "]) timestamp = [[entry substringFromIndex:15] doubleValue];
    if (timestamp <= 0 || !isfinite(timestamp)) return candidate;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = [NSTimeZone timeZoneWithName:candidate[@"timeZone"] ?: @""] ?: NSTimeZone.localTimeZone;
    return SSApplyDateReference(candidate, [NSDate dateWithTimeIntervalSince1970:timestamp], commit, calendar);
}
- (NSDictionary *)readCourseDocuments:(NSDictionary *)course paths:(NSArray *)paths fetch:(BOOL)fetch cache:(NSMutableDictionary *)cache error:(NSError **)error {
    if (![self validateCourse:course error:error]) return nil;
    NSString *path = course[@"path"];
    NSString *url=[self teacherURL:course path:path error:error];if(!url)return nil;
    NSString *branch=[self teacherBranch:url course:course error:error];if(!branch)return nil;
    if(fetch && ![self teacherRequest:@[@"fetch",@"--no-tags",@"--",url,[@"refs/heads/" stringByAppendingString:branch]] course:course error:error])return nil;
    SSGitResult *tip=[self checked:@[@"rev-parse",@"FETCH_HEAD"] in:path token:nil error:error];NSString *head=tip ? Trim([self string:tip]) : nil;if(!head)return nil;
    SSGitResult *tree = [self checked:@[@"ls-tree", @"-r", @"-l", @"-z", head] in:path token:nil error:error]; if (!tree) return nil;
    NSMutableArray *skipped = NSMutableArray.array;
    NSMutableArray *documents = NSMutableArray.array;
    NSUInteger total = 0;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:course[@"timeZone"] ?: NSTimeZone.localTimeZone.name] ?: NSTimeZone.localTimeZone;
    for (NSString *entry in NonemptyParts([self string:tree], @"\0")) {
        NSRange tab = [entry rangeOfString:@"\t"]; if (tab.location == NSNotFound) continue;
        NSString *file = [entry substringFromIndex:NSMaxRange(tab)]; if (!SSIsSupportedDocument(file) || (paths && ![paths containsObject:file])) continue;
        if (SSSensitivePath(file)) { [skipped addObject:[file stringByAppendingString:@"：敏感文件名，未读取"]]; continue; }
        NSArray *fields = NonemptyParts([entry substringToIndex:tab.location], @" ");
        if (fields.count < 4 || ![fields[1] isEqual:@"blob"]) continue;
        if ([fields[0] isEqual:@"120000"]) { [skipped addObject:[file stringByAppendingString:@"：符号链接，未读取外部文件"]]; continue; }
        NSUInteger size = [fields[3] integerValue];
        if (size > 1024 * 1024 || total + size > 30 * 1024 * 1024) { [skipped addObject:[file stringByAppendingString:@"：超出扫描大小限制"]]; continue; } total += size;
        NSString *key = [NSString stringWithFormat:@"document-v5|%@|%@|%@", course[@"upstream"], file, fields[2]];
        NSString *text = [cache[key] isKindOfClass:NSString.class] ? cache[key] : nil;
        if (!text) {
            SSGitResult *blob = [self checked:@[@"cat-file", @"blob", fields[2]] in:path token:nil error:error]; if (!blob) return nil;
            text = [[NSString alloc] initWithData:blob.data encoding:NSUTF8StringEncoding];
            if (!text && blob.data.length >= 2) { const unsigned char *bytes = blob.data.bytes; if ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff)) text = [[NSString alloc] initWithData:blob.data encoding:NSUTF16StringEncoding]; }
            if (!text || [text rangeOfString:@"\0"].location != NSNotFound) { [skipped addObject:[file stringByAppendingString:@"：不是支持的文本编码"]]; continue; }
            if (SSContainsSecret(blob.data)) { [skipped addObject:[file stringByAppendingString:@"：含疑似凭据，未导入原文"]]; continue; }
            cache[key] = text;
        }
        [documents addObject:@{@"repository":course[@"upstream"],@"path":file,@"blobSHA":fields[2],@"text":text,@"timeZone":calendar.timeZone.name}];
    }
    return @{@"documents":documents,@"skipped":skipped,@"commit":head,@"branch":branch,@"date":NSDate.date};
}
- (NSDictionary *)scanCourse:(NSDictionary *)course cache:(NSMutableDictionary *)cache error:(NSError **)error {
    NSDictionary *snapshot=[self readCourseDocuments:course paths:nil fetch:YES cache:cache error:error];if(!snapshot)return nil;
    NSArray *documents=snapshot[@"documents"],*skipped=snapshot[@"skipped"];NSString *head=snapshot[@"commit"],*branch=snapshot[@"branch"],*path=course[@"path"];
    NSDictionary *settings=SSCourseRecognitionSettings(self.recognitionSettings ?: @{@"mode":@"rules"},course);
    NSMutableArray *candidates=NSMutableArray.array,*materials=NSMutableArray.array,*recognitionMessages=NSMutableArray.array;
    NSMutableSet *dedup=NSMutableSet.set;NSCalendar *calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone=[NSTimeZone timeZoneWithName:course[@"timeZone"] ?: NSTimeZone.localTimeZone.name] ?: NSTimeZone.localTimeZone;
    for(NSDictionary *document in documents){NSString *text=document[@"text"],*file=document[@"path"],*blob=document[@"blobSHA"];
        NSError *recognitionError = nil;
        if (self.progress) self.progress([NSString stringWithFormat:@"正在识别老师文档：%@",file]);
        NSArray *found = SSRecognizeDocument(text, course[@"upstream"], file, blob, calendar, settings, cache, &recognitionError);
        if (recognitionError) [recognitionMessages addObject:[NSString stringWithFormat:@"%@：%@",file,recognitionError.localizedDescription]];
        for (NSDictionary *candidate in found) {
            if (![candidate[@"kind"] isEqual:@"assignment"]) { [materials addObject:candidate]; continue; }
            NSString *fingerprint = [NSString stringWithFormat:@"%@|%@|%@", [candidate[@"title"] lowercaseString], candidate[@"due"], candidate[@"deadlineText"] ?: @""];
            if ([dedup containsObject:fingerprint]) continue; [dedup addObject:fingerprint];
            NSString *referenceKey = [NSString stringWithFormat:@"reference-v4|%@|%@|%@|%@|%@|%@", course[@"upstream"], head, file, blob, candidate[@"line"], calendar.timeZone.name];
            NSDictionary *referenced = [cache[referenceKey] isKindOfClass:NSArray.class] ? [cache[referenceKey] firstObject] : nil;
            if (!referenced) { referenced = [self dateReferenceForCandidate:candidate head:head path:path]; if ([candidate[@"relative"] boolValue]) cache[referenceKey] = @[referenced]; }
            NSMutableDictionary *copy = candidate.mutableCopy;for(NSString *field in @[@"suggestedDue",@"dateBasis"])if(referenced[field])copy[field]=referenced[field]; if (!copy[@"timeZone"]) copy[@"timeZone"] = calendar.timeZone.name; [candidates addObject:copy];
        }
    }
    return @{@"candidates":SSAttachLinkedDocuments(SSConsolidateAssignments(candidates),documents), @"materials":SSGroupMaterials(materials), @"documents":documents, @"recognitionMessages":recognitionMessages, @"skipped":skipped, @"commit":head, @"branch":branch, @"date":NSDate.date};
}
- (NSDictionary *)resolveSkillDates:(NSDictionary *)validated scans:(NSDictionary *)scans courses:(NSArray *)courses {
    NSMutableDictionary *result=validated.mutableCopy,*records=NSMutableDictionary.dictionary;
    for(NSString *fork in validated[@"records"]){NSDictionary *course=nil;for(NSDictionary *item in courses)if([item[@"fork"] isEqual:fork]){course=item;break;}NSMutableArray *resolved=NSMutableArray.array;
        for(NSDictionary *record in validated[@"records"][fork]){NSMutableDictionary *copy=record.mutableCopy;
            if([record[@"relative"] boolValue] && course && [scans[fork][@"commit"] length]){NSDictionary *basis=[self dateReferenceForCandidate:record head:scans[fork][@"commit"] path:course[@"path"]];for(NSString *key in @[@"dateBasis",@"suggestedDue"])if(basis[key])copy[key]=basis[key];}
            [resolved addObject:copy];}records[fork]=resolved;
    }result[@"records"]=records;return result;
}
- (NSDictionary *)enhanceScan:(NSDictionary *)scan course:(NSDictionary *)course settings:(NSDictionary *)settings paths:(NSArray *)paths cache:(NSMutableDictionary *)cache {
    NSDictionary *scoped=SSCourseRecognitionSettings(settings,course);if([scoped[@"mode"] isEqual:@"rules"])return scan;
    NSMutableDictionary *byID=NSMutableDictionary.dictionary;for(NSDictionary *record in scan[@"candidates"])byID[record[@"id"]]=record;
    for(NSDictionary *group in scan[@"materials"])for(NSDictionary *record in group[@"documents"] ?: @[group])byID[record[@"id"]]=record;
    NSMutableArray *messages=NSMutableArray.array;NSUInteger processed=0;
    for(NSDictionary *document in scan[@"documents"]){if(paths && ![paths containsObject:document[@"path"]])continue;processed++;
        if(self.progress)self.progress([NSString stringWithFormat:@"本地或模型分析 %lu：%@",(unsigned long)processed,document[@"path"]]);
        NSCalendar *calendar=[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];calendar.timeZone=[NSTimeZone timeZoneWithName:document[@"timeZone"]] ?: NSTimeZone.localTimeZone;
        NSError *failure=nil;NSArray *found=SSRecognizeDocument(document[@"text"],document[@"repository"],document[@"path"],document[@"blobSHA"],calendar,scoped,cache,&failure);
        if(failure){[messages addObject:[NSString stringWithFormat:@"%@：%@",document[@"path"],failure.localizedDescription]];if([scoped[@"mode"] isEqual:@"local"] && ([failure.localizedDescription containsString:@"连接失败"] || [failure.localizedDescription containsString:@"超时"] || [failure.localizedDescription containsString:@"服务返回 HTTP"])){[messages addObject:@"其余文档暂用规则结果，可恢复服务后重试。"];break;}continue;}
        for(NSDictionary *record in found){NSMutableDictionary *copy=record.mutableCopy;NSDictionary *old=byID[record[@"id"]];
            if([record[@"relative"] boolValue]){NSDictionary *basis=old[@"dateBasis"] ? old : [self dateReferenceForCandidate:record head:scan[@"commit"] path:course[@"path"]];for(NSString *field in @[@"dateBasis",@"suggestedDue"])if(basis[field])copy[field]=basis[field];}
            byID[record[@"id"]]=copy;
        }
    }
    NSMutableArray *assignments=NSMutableArray.array,*materials=NSMutableArray.array;for(NSDictionary *record in byID.allValues)if([record[@"kind"] isEqual:@"assignment"])[assignments addObject:record];else[materials addObject:record];
    NSMutableDictionary *result=scan.mutableCopy;result[@"candidates"]=SSAttachLinkedDocuments(SSConsolidateAssignments(assignments),scan[@"documents"]);result[@"materials"]=SSGroupMaterials(materials);result[@"recognitionMessages"]=messages;result[@"modelCompleted"]=@(messages.count==0);return result;
}
- (BOOL)cleanWorktree:(NSString *)path error:(NSError **)error {
    SSGitResult *status = [self checked:@[@"status", @"--porcelain=v1", @"-z", @"--untracked-files=all"] in:path token:nil error:error]; if (!status) return NO;
    if (status.data.length) { if (error) *error = GitError(@"本地有未提交修改；请先提交或自行处理，再拉取上游。"); return NO; } return YES;
}
- (NSArray<NSDictionary *> *)changesForCourse:(NSDictionary *)course error:(NSError **)error {
    if (![self validateCourse:course error:error]) return nil;
    SSGitResult *status = [self checked:@[@"status", @"--porcelain=v1", @"-z", @"--untracked-files=all"] in:course[@"path"] token:nil error:error]; if (!status) return nil;
    NSArray *entries = [[self string:status] componentsSeparatedByString:@"\0"]; NSMutableArray *changes = NSMutableArray.array;
    for (NSUInteger i = 0; i < entries.count; i++) {
        NSString *entry = entries[i]; if (entry.length < 4) continue;
        NSString *code = [entry substringToIndex:2], *file = [entry substringFromIndex:3];
        if ([code containsString:@"R"] || [code containsString:@"C"]) i++;
        [changes addObject:@{@"path":file, @"status":code, @"sensitive":@(SSSensitivePath(file))}];
    }
    return changes;
}
- (NSString *)previewForCourse:(NSDictionary *)course path:(NSString *)file error:(NSError **)error {
    NSArray *changes = [self changesForCourse:course error:error]; if (!changes) return nil;
    NSDictionary *change = nil; for (NSDictionary *item in changes) if ([item[@"path"] isEqual:file]) { change = item; break; }
    if (!change) { if (error) *error = GitError(@"文件已不在变更列表，请重新打开提交窗口。"); return nil; }
    if ([change[@"sensitive"] boolValue]) return @"此文件可能包含凭据或无法检查的内容，不能通过应用提交。请先排除或修复。";
    NSString *root = [course[@"path"] stringByResolvingSymlinksInPath]; NSString *absolute = [[root stringByAppendingPathComponent:file] stringByResolvingSymlinksInPath];
    if (![absolute hasPrefix:[root stringByAppendingString:@"/"]]) { if (error) *error = GitError(@"文件指向仓库之外，已阻止预览。"); return nil; }
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:absolute error:NULL];
    if ([attributes[NSFileSize] unsignedLongLongValue] > 512 * 1024) return @"文件较大，请在编辑器中查看。提交时仍会完整检查所选文件与待推送历史。";
    NSData *data = nil;
    if (![change[@"status"] isEqual:@"??"]) {
        SSGitResult *size = [self run:@[@"cat-file", @"-s", [@"HEAD:" stringByAppendingString:file]] in:root token:nil error:NULL];
        if (size && size.status == 0 && [Trim([self string:size]) longLongValue] > 512 * 1024) return @"原文件较大，请在编辑器中查看。提交检查仍会覆盖完整内容。";
    }
    if ([change[@"status"] isEqual:@"??"]) data = [NSData dataWithContentsOfFile:absolute];
    else {
        SSGitResult *result = [self checked:@[@"diff", @"--no-ext-diff", @"--no-textconv", @"--no-color", @"HEAD", @"--", file] in:root token:nil error:error]; if (!result) return nil; data = result.data;
    }
    if (!data) { if (error) *error = GitError(@"文件在读取期间发生变化，请重新打开提交窗口。"); return nil; }
    if (SSContainsSecret(data)) return @"检测到疑似凭据，预览已隐藏。请移除敏感内容，并轮换真实凭据后再提交。";
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return @"这是非 UTF-8 文本或二进制文件，请在对应应用中查看。";
    NSString *preview = SSRedactedText(text.length ? text : @"没有文本差异，可能仅修改了文件属性。"); return text.length > 1600 ? [preview stringByAppendingString:@"\n…预览已截断；提交检查会覆盖完整内容。"] : preview;
}
- (BOOL)checkObjects:(NSString *)range path:(NSString *)path error:(NSError **)error {
    SSGitResult *objects = [self checked:@[@"rev-list", @"--objects", @"--no-object-names", range] in:path token:nil error:error]; if (!objects) return NO;
    NSArray *shas = NonemptyParts([self string:objects], @"\n");
    if (shas.count > 4000) { if (error) *error = GitError(@"待推送范围过大，无法完整检查；请先人工检查历史。"); return NO; }
    NSUInteger total = 0;
    for (NSString *sha in shas) {
        SSGitResult *type = [self checked:@[@"cat-file", @"-t", sha] in:path token:nil error:error]; if (!type) return NO;
        NSString *kind = Trim([self string:type]);
        if ([kind isEqual:@"tree"]) {
            SSGitResult *tree = [self checked:@[@"ls-tree", @"-z", sha] in:path token:nil error:error]; if (!tree) return NO;
            for (NSString *entry in NonemptyParts([self string:tree], @"\0")) {
                NSRange tab = [entry rangeOfString:@"\t"];
                if (tab.location != NSNotFound && SSSensitivePath([entry substringFromIndex:NSMaxRange(tab)])) { if (error) *error = GitError(@"待推送历史包含凭据文件或压缩包；请排除敏感文件，压缩包请改为可检查的源文件。"); return NO; }
            }
        } else if ([kind isEqual:@"blob"] || [kind isEqual:@"commit"] || [kind isEqual:@"tag"]) {
            SSGitResult *size = [self checked:@[@"cat-file", @"-s", sha] in:path token:nil error:error]; if (!size) return NO;
            NSUInteger bytes = [Trim([self string:size]) integerValue]; total += bytes;
            if (bytes > 5 * 1024 * 1024 || total > 50 * 1024 * 1024) { if (error) *error = GitError(@"待推送文件或历史超出安全检查上限；已停止推送。"); return NO; }
            SSGitResult *data = [self checked:@[@"cat-file", kind, sha] in:path token:nil error:error]; if (!data) return NO;
            if (SSContainsSecret(data.data)) { if (error) *error = GitError(@"待推送提交历史含疑似凭据；已停止推送，请先移除并轮换真实凭据。"); return NO; }
        }
    }
    return YES;
}
- (BOOL)pushCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error {
    if (![self authorize:course error:error] || ![self validateCourse:course error:error] || ![self submissionBranch:course error:error]) return NO;
    NSString *path = course[@"path"], *url = [NSString stringWithFormat:@"https://github.com/%@.git", course[@"fork"]];
    NSString *base = [self fetch:url branch:course[@"branch"] path:path token:token error:error]; if (!base) return NO;
    SSGitResult *tip = [self checked:@[@"rev-parse", @"HEAD"] in:path token:nil error:error]; if (!tip) return NO;
    NSString *head = Trim([self string:tip]);
    SSGitResult *ancestor = [self run:@[@"merge-base", @"--is-ancestor", base, head] in:path token:nil error:error];
    if (!ancestor || ancestor.status != 0) { if (error) *error = GitError(@"个人 fork 有新提交或已经分歧；当前推送不是快进，已停止。"); return NO; }
    if (![self checkObjects:[NSString stringWithFormat:@"%@..%@", base, head] path:path error:error]) return NO;
    if (![self authorize:course error:error] || ![self validateCourse:course error:error] || ![self submissionBranch:course error:error]) return NO;
    NSString *ref = [NSString stringWithFormat:@"%@:refs/heads/%@", head, course[@"branch"]];
    // Immutable commit + a freshly verified, explicit HTTPS fork URL. Never use push.default/pushurl.
    NSArray *push=[self remoteArguments:@[@"push",@"--",url,ref] course:course role:@"personalPush" error:error];return push && [self checked:push in:path token:token error:error] != nil;
}
- (NSDictionary *)syncCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error {
    NSDictionary *user = [self authorize:course error:error];
    if (!user || ![self validateCourse:course error:error] || ![self submissionBranch:course error:error] || ![self cleanWorktree:course[@"path"] error:error]) return nil;
    NSString *path = course[@"path"], *url = [NSString stringWithFormat:@"https://github.com/%@.git", course[@"fork"]];
    NSString *base = [self fetch:url branch:course[@"branch"] path:path token:token error:error]; if (!base) return nil;
    if (![self checked:[[self authorArguments:user] arrayByAddingObjectsFromArray:@[@"merge", @"--ff-only", base]] in:path token:nil error:error]) return nil;
    NSString *teacherURL=[self teacherURL:course path:path error:error];if(!teacherURL)return nil;
    NSString *teacherBranch=[self teacherBranch:teacherURL course:course error:error];if(!teacherBranch)return nil;
    if(![self teacherRequest:@[@"fetch",@"--no-tags",@"--",teacherURL,[@"refs/heads/" stringByAppendingString:teacherBranch]] course:course error:error])return nil;
    SSGitResult *teacherTip=[self checked:@[@"rev-parse",@"FETCH_HEAD"] in:path token:nil error:error];NSString *teacher=teacherTip ? Trim([self string:teacherTip]) : nil;if(!teacher)return nil;
    SSGitResult *merge = [self run:[[self authorArguments:user] arrayByAddingObjectsFromArray:@[@"merge", @"--no-edit", teacher]] in:path token:nil error:error]; if (!merge) return nil;
    if (merge.status != 0) {
        NSArray *files = [self conflicts:course error:NULL];
        if (!files.count) { if (error) *error = GitError(merge.diagnostic); return nil; }
        if (error) *error = GitError(@"合并产生冲突。请打开冲突引导，编辑文件、标记解决后再继续。");
        return @{@"conflicts":files, @"mergeHead":teacher};
    }
    if (![self pushCourse:course token:token error:error]) { if (error) *error = PendingPushError(*error); return nil; }
    return @{@"success":@YES};
}
- (BOOL)commitCourse:(NSDictionary *)course paths:(NSArray<NSString *> *)paths message:(NSString *)message login:(NSString *)login userID:(NSNumber *)userID token:(NSString *)token error:(NSError **)error {
    NSDictionary *user = [self authorize:course error:error];
    if (!user || ![user[@"id"] isEqual:userID] || ![user[@"login"] isEqual:login] || ![self validateCourse:course error:error] || ![self submissionBranch:course error:error]) return NO;
    NSString *path = course[@"path"], *commitMessage = Trim(message);
    if (!paths.count || !commitMessage.length || SSContainsSecret([commitMessage dataUsingEncoding:NSUTF8StringEncoding])) { if (error) *error = GitError(@"请选择文件并填写不含凭据的提交说明。"); return NO; }
    SSGitResult *pendingMerge = [self run:@[@"rev-parse", @"-q", @"--verify", @"MERGE_HEAD"] in:path token:nil error:NULL];
    if (!pendingMerge) { if (error) *error = GitError(@"无法读取合并状态，已停止提交。"); return NO; }
    if (pendingMerge.status == 0) { if (error) *error = GitError(@"有待完成的合并；请先使用冲突引导处理。"); return NO; }
    SSGitResult *staged = [self checked:@[@"diff", @"--cached", @"--name-only", @"-z"] in:path token:nil error:error]; if (!staged) return NO;
    if (staged.data.length) { if (error) *error = GitError(@"仓库已有暂存内容，请先处理，避免混入本次作业。"); return NO; }
    NSArray *changes = [self changesForCourse:course error:error]; if (!changes) return NO;
    NSMutableSet *available = NSMutableSet.set; for (NSDictionary *change in changes) [available addObject:change[@"path"]];
    for (NSString *file in paths) if (![available containsObject:file] || SSSensitivePath(file)) { if (error) *error = GitError(@"所选文件不在变更列表，或包含敏感文件／不能检查的压缩包。"); return NO; }
    NSString *index = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"ss-index-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    self.temporaryIndex = index;
    BOOL committed = NO;
    @try {
        if (![self checked:@[@"read-tree", @"HEAD"] in:path token:nil error:error]) return NO;
        NSMutableArray *add = [@[@"add", @"-A", @"--"] mutableCopy]; [add addObjectsFromArray:paths];
        if (![self checked:add in:path token:nil error:error]) return NO;
        SSGitResult *names = [self checked:@[@"diff", @"--cached", @"--name-only", @"-z"] in:path token:nil error:error]; if (!names) return NO;
        NSArray *actual = NonemptyParts([self string:names], @"\0");
        if (!actual.count || ![[NSSet setWithArray:actual] isSubsetOfSet:[NSSet setWithArray:paths]]) { if (error) *error = GitError(@"文件在检查期间发生变化，或没有实际变更；请重新选择。"); return NO; }
        for (NSString *file in actual) {
            SSGitResult *entry = [self checked:@[@"ls-files", @"--stage", @"-z", @"--", file] in:path token:nil error:error]; if (!entry) return NO;
            for (NSString *record in NonemptyParts([self string:entry], @"\0")) {
                NSRange tab = [record rangeOfString:@"\t"]; if (tab.location == NSNotFound) return NO;
                NSArray *fields = NonemptyParts([record substringToIndex:tab.location], @" "); if (fields.count < 3) return NO;
                SSGitResult *size = [self checked:@[@"cat-file", @"-s", fields[1]] in:path token:nil error:error]; if (!size) return NO;
                if ([Trim([self string:size]) integerValue] > 5 * 1024 * 1024) { if (error) *error = GitError(@"所选文件超过 5 MB，无法完成安全检查。"); return NO; }
                SSGitResult *blob = [self checked:@[@"cat-file", @"blob", fields[1]] in:path token:nil error:error]; if (!blob) return NO;
                if (SSContainsSecret(blob.data)) { if (error) *error = GitError(@"所选文件含疑似凭据，已停止提交。"); return NO; }
            }
        }
        committed = [self checked:[[self authorArguments:user] arrayByAddingObjectsFromArray:@[@"commit", @"-m", commitMessage]] in:path token:nil error:error] != nil;
    } @finally {
        self.temporaryIndex = nil; [NSFileManager.defaultManager removeItemAtPath:index error:NULL];
        [NSFileManager.defaultManager removeItemAtPath:[index stringByAppendingString:@".lock"] error:NULL];
    }
    if (!committed) return NO;
    NSMutableArray *reset = [@[@"reset", @"--quiet", @"HEAD", @"--"] mutableCopy]; [reset addObjectsFromArray:paths];
    if (![self checked:reset in:path token:nil error:error]) return NO;
    if (![self pushCourse:course token:token error:error]) {
        if (error) *error = PendingPushError(*error); return NO;
    }
    return YES;
}
- (NSArray<NSString *> *)conflicts:(NSDictionary *)course error:(NSError **)error {
    if (![self validateCourse:course error:error]) return nil;
    SSGitResult *files = [self checked:@[@"diff", @"--name-only", @"--diff-filter=U", @"-z"] in:course[@"path"] token:nil error:error];
    return files ? NonemptyParts([self string:files], @"\0") : nil;
}
- (BOOL)ownedMerge:(NSDictionary *)course error:(NSError **)error {
    SSGitResult *head = [self checked:@[@"rev-parse", @"-q", @"--verify", @"MERGE_HEAD"] in:course[@"path"] token:nil error:error];
    if (!head || ![Trim([self string:head]) isEqual:course[@"pendingMergeTip"]]) { if (error) *error = GitError(@"当前合并不是由该课程的拉取操作创建；请自行处理仓库状态。"); return NO; } return YES;
}
- (BOOL)stageResolvedFiles:(NSDictionary *)course paths:(NSArray<NSString *> *)paths error:(NSError **)error {
    if (![self validateCourse:course error:error] || ![self ownedMerge:course error:error]) return NO;
    for (NSString *file in paths) {
        if (![course[@"pendingConflicts"] containsObject:file] || SSSensitivePath(file)) { if (error) *error = GitError(@"所选文件不属于当前冲突。"); return NO; }
        NSData *data = [NSData dataWithContentsOfFile:[course[@"path"] stringByAppendingPathComponent:file]];
        NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
        if (SSContainsSecret(data) || (text && [text rangeOfString:@"(?m)^(?:<<<<<<< |=======|>>>>>>> )" options:NSRegularExpressionSearch].location != NSNotFound)) { if (error) *error = GitError(@"文件仍有冲突标记或疑似凭据，请先编辑。"); return NO; }
    }
    NSMutableArray *args = [@[@"add", @"-A", @"--"] mutableCopy]; [args addObjectsFromArray:paths];
    return paths.count && [self checked:args in:course[@"path"] token:nil error:error] != nil;
}
- (BOOL)continueMergeForCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error {
    NSDictionary *user = [self authorize:course error:error];
    if (!user || ![self validateCourse:course error:error] || ![self submissionBranch:course error:error] || ![self ownedMerge:course error:error]) return NO;
    NSArray *files = [self conflicts:course error:error]; if (!files) return NO;
    if (files.count) { if (error) *error = GitError(@"仍有未解决的冲突，请编辑文件并标记解决。"); return NO; }
    if (![self checked:[[self authorArguments:user] arrayByAddingObjectsFromArray:@[@"commit", @"--no-edit"]] in:course[@"path"] token:nil error:error]) return NO;
    if (![self pushCourse:course token:token error:error]) { if (error) *error = PendingPushError(*error); return NO; } return YES;
}
- (BOOL)abortMerge:(NSDictionary *)course error:(NSError **)error {
    if (![self validateCourse:course error:error] || ![self ownedMerge:course error:error]) return NO;
    return [self checked:@[@"merge", @"--abort"] in:course[@"path"] token:nil error:error] != nil;
}
@end
