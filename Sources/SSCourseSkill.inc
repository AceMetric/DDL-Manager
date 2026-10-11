// Only application-created exchange folders are watched. Course text never leaves
// this Mac until the user explicitly hands the instruction to an assistant.
- (NSDictionary *)discoveryEnvelope:(NSDictionary *)candidates materials:(NSDictionary *)materials progress:(NSDictionary *)progress batches:(NSDictionary *)batches {
    return @{@"candidates":candidates,@"materials":materials,@"skillProgress":progress,@"skillBatches":batches,@"skillJobs":self.skillJobs ?: @{}};
}
- (NSDictionary *)discoveryEnvelope {return [self discoveryEnvelope:self.candidates materials:self.materials progress:self.skillProgress batches:self.skillBatches];}
- (NSArray *)chooseSkillCourses:(BOOL *)all {
    NSAlert *alert=NSAlert.new;alert.messageText=@"选择助手识别的课程";alert.informativeText=@"只准备老师文档，不含个人答案、任务或凭据。将指令交给云端助手后，所选文档会由该服务处理。所有课程共用一个 Skill。";
    NSStackView *rows=NSStackView.new;rows.orientation=NSUserInterfaceLayoutOrientationVertical;rows.alignment=NSLayoutAttributeLeading;rows.spacing=8;
    NSArray *remembered=SSReadPlist(@"skill-selection.plist");if(![remembered isKindOfClass:NSArray.class])remembered=nil;NSMutableArray *checks=NSMutableArray.array;
    for(NSDictionary *course in self.courses){NSButton *check=[NSButton checkboxWithTitle:[course[@"fork"] lastPathComponent] target:nil action:nil];check.identifier=course[@"fork"];check.enabled=[course[@"path"] length]>0;check.state=check.enabled && (remembered ? [remembered containsObject:course[@"fork"]]:![course[@"enabled"] isEqual:@NO]) ? NSControlStateValueOn:NSControlStateValueOff;check.toolTip=check.enabled ? course[@"fork"] : @"先关联本地文件夹";[rows addArrangedSubview:check];[checks addObject:check];}
    rows.frame=NSMakeRect(0,0,440,MAX(100,rows.arrangedSubviews.count*32));NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,460,MIN(260,NSHeight(rows.frame)))];scroll.hasVerticalScroller=YES;scroll.documentView=rows;alert.accessoryView=scroll;
    [alert addButtonWithTitle:@"使用这些课程"];[alert addButtonWithTitle:@"取消"];if([alert runModal]!=NSAlertFirstButtonReturn)return nil;
    NSMutableArray *selected=NSMutableArray.array,*identifiers=NSMutableArray.array;for(NSButton *check in checks)if(check.enabled && check.state==NSControlStateValueOn)for(NSDictionary *course in self.courses)if([course[@"fork"] isEqual:check.identifier]){[selected addObject:course.copy];[identifiers addObject:course[@"fork"]];}
    NSError *error=nil;if(!SSWritePlist(@"skill-selection.plist",identifiers,&error)){[self showError:error];return nil;}*all=NO;return selected;
}
- (NSArray *)selectedSkillCourses {
    id remembered=SSReadPlist(@"skill-selection.plist");if(![remembered isKindOfClass:NSArray.class]){BOOL all=NO;NSArray *selected=[self chooseSkillCourses:&all];if(!selected)return nil;NSDictionary *course=[self course];if(!course)return selected;for(NSDictionary *row in selected)if([row[@"fork"] isEqual:course[@"fork"]])return @[row];return @[];}
    NSMutableArray *courses=NSMutableArray.array;NSDictionary *current=[self course];
    // In a course, the button always refers to that explicit course. The global
    // selection is only changed through Adjust Courses.
    for(NSDictionary *course in self.courses)if((current ? [course[@"fork"] isEqual:current[@"fork"]]:[remembered containsObject:course[@"fork"]]) && [course[@"path"] length])[courses addObject:course.copy];return courses;
}
- (void)adjustSkillCourses:(id)sender {if(self.preview || self.busy || self.operationsPaused)return;BOOL all=NO;[self chooseSkillCourses:&all];}
- (NSArray *)retainingSkill:(NSArray *)previous current:(NSArray *)current documents:(NSArray *)documents {
    NSMutableDictionary *byID=NSMutableDictionary.dictionary;for(NSDictionary *record in current)if(record[@"id"])byID[record[@"id"]]=record;
    for(NSDictionary *record in previous)if([record[@"recognizer"] isEqual:@"skill-v1"])for(NSDictionary *document in documents)if([record[@"path"] isEqual:document[@"path"]] && [record[@"repository"] isEqual:document[@"repository"]] && [record[@"blobSHA"] isEqual:document[@"blobSHA"]]){byID[record[@"id"]]=record;break;}
    return [byID.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [a[@"id"] compare:b[@"id"]];}];
}
- (NSDictionary *)readSkillCourses:(NSArray *)courses result:(NSDictionary *)result {
    id cached=SSReadPlist(@"scan-cache.plist");NSMutableDictionary *cache=[cached isKindOfClass:NSDictionary.class] ? [cached mutableCopy]:NSMutableDictionary.dictionary;
    NSMutableDictionary *scans=NSMutableDictionary.dictionary;
    for(NSDictionary *course in courses){
        NSMutableArray *paths=result ? NSMutableArray.array:nil;
        for(id document in result[@"documents"])if([document isKindOfClass:NSDictionary.class] && ([result[@"format"] isEqual:@"am-course-results-v1"] || [document[@"courseID"] isEqual:course[@"fork"]]) && [document[@"repository"] isEqual:course[@"upstream"]] && [document[@"path"] isKindOfClass:NSString.class])[paths addObject:document[@"path"]];
        if(result && !paths.count)continue;
        NSError *failure=nil;NSDictionary *snapshot=self.reports[course[@"fork"]];
        BOOL reuse=!result && snapshot[@"commit"] && [snapshot[@"date"] isKindOfClass:NSDate.class] && [NSDate.date timeIntervalSinceDate:snapshot[@"date"]]<300;
        NSString *zone=course[@"timeZone"] ?: NSTimeZone.localTimeZone.name;
        for(NSDictionary *document in snapshot[@"documents"])if(![document[@"repository"] isEqual:course[@"upstream"]] || ![document[@"timeZone"] isEqual:zone])reuse=NO;
        NSDictionary *scan=reuse ? snapshot:[self.git readCourseDocuments:course paths:paths fetch:YES cache:cache error:&failure];
        if(scan){NSMutableDictionary *withReferences=scan.mutableCopy;withReferences[@"candidates"]=self.candidates[course[@"fork"]] ?: @[];withReferences[@"materials"]=self.materials[course[@"fork"]] ?: @[];scan=withReferences;}
        scans[course[@"fork"]]=scan ?: @{@"error":failure.localizedDescription ?: @"无法读取老师内容"};
    }
    SSWritePlist(@"scan-cache.plist",cache,NULL);return scans;
}
- (NSURL *)skillFolder:(NSString *)batch {
    if(![[NSUUID alloc] initWithUUIDString:batch])return nil;
    NSURL *root=[SSDataDirectory().URLByResolvingSymlinksInPath URLByAppendingPathComponent:@"AssistantExchange" isDirectory:YES];
    NSURL *folder=[root URLByAppendingPathComponent:batch isDirectory:YES];
    // Do not follow substituted exchange roots or job folders into other data.
    if(![folder.path.stringByStandardizingPath isEqual:folder.path.stringByResolvingSymlinksInPath])return nil;return folder;
}
- (BOOL)writeSkillState:(NSError **)error {return SSWritePlist(@"discoveries.plist",self.discoveryEnvelope,error);}
- (void)setSkillJob:(NSString *)batch state:(NSString *)state message:(NSString *)message {
    NSMutableDictionary *job=[self.skillJobs[batch] mutableCopy];if(!job)return;job[@"state"]=state;job[@"message"]=message ?: @"";self.skillJobs[batch]=job;[self writeSkillState:NULL];
}
- (void)watchSkillBatch:(NSString *)batch {
    NSURL *folder=[self skillFolder:batch];if(!folder)return;int descriptor=open(folder.fileSystemRepresentation,O_EVTONLY|O_NOFOLLOW);if(descriptor<0)return;
    dispatch_source_t source=dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE,(uintptr_t)descriptor,DISPATCH_VNODE_WRITE|DISPATCH_VNODE_RENAME|DISPATCH_VNODE_DELETE,dispatch_get_main_queue());if(!source){close(descriptor);return;}
    __weak typeof(self) owner=self;dispatch_source_set_event_handler(source,^{[owner pollSkillResults:nil];});dispatch_source_set_cancel_handler(source,^{close(descriptor);});[self.skillWatchers addObject:source];dispatch_resume(source);
}
- (void)startSkillReception {
    if(self.preview || self.skillTimer)return;[self cleanSkillJobs:NO];for(NSString *batch in self.skillJobs)[self watchSkillBatch:batch];
    __weak typeof(self) owner=self;self.skillTimer=[NSTimer scheduledTimerWithTimeInterval:3 repeats:YES block:^(NSTimer *timer){[owner pollSkillResults:nil];}];[self pollSkillResults:nil];
}
- (void)exportSkillContext:(id)sender {[self prepareSkill:NO];}
- (void)exportAllSkillContext:(id)sender {[self prepareSkill:YES];}
- (void)prepareSkill:(BOOL)all {
    if(self.preview || self.busy || self.operationsPaused)return;NSArray *courses=[self selectedSkillCourses];if(!courses)return;if(!courses.count){[self status:@"没有已就绪课程，请在“更多 → 调整助手课程”中选择。"];return;}
    [self prepareSkillCourses:courses all:all manifest:nil];
}
- (void)prepareSkillCourses:(NSArray *)courses all:(BOOL)all manifest:(NSDictionary *)manifest {
    if(!courses.count || self.busy || self.operationsPaused)return;
    NSDictionary *progress=self.skillProgress.copy;NSDate *started=NSDate.date;
    [self work:@"准备中 · 正在读取新增老师材料…" forCourse:nil operation:^id(NSError **error){NSDictionary *scans=[self readSkillCourses:courses result:nil];if(manifest){NSMutableDictionary *limited=NSMutableDictionary.dictionary;for(NSDictionary *course in courses){NSString *fork=course[@"fork"];NSMutableDictionary *scan=[scans[fork] mutableCopy];NSMutableArray *documents=NSMutableArray.array;for(NSDictionary *doc in scan[@"documents"])if(manifest[SSSkillProgressKey(fork,doc)])[documents addObject:doc];scan[@"documents"]=documents;if(scan)limited[fork]=scan;}scans=limited;}NSMutableDictionary *exported=[SSSkillExport(courses,scans,progress,all) mutableCopy];exported[@"scans"]=scans;return exported;} completion:^(NSDictionary *exported,NSError *error){
        if(!exported){[self showError:error];return;}NSMutableArray *issues=NSMutableArray.array;for(NSDictionary *course in courses)if(exported[@"scans"][course[@"fork"]][@"error"])[issues addObject:[NSString stringWithFormat:@"%@：%@",[course[@"fork"] lastPathComponent],exported[@"scans"][course[@"fork"]][@"error"]]];
        if(![exported[@"context"][@"documents"] count]){[self status:issues.count ? [issues componentsJoinedByString:@"；"]:@"没有尚未识别的新增材料，无需交给助手。可在“更多”重新分析全部。"];return;}
        NSMutableDictionary *reports=self.reports.mutableCopy ?: NSMutableDictionary.dictionary;[reports addEntriesFromDictionary:exported[@"scans"]];self.reports=reports;
        for(NSString *pending in self.skillJobs)if(![self.skillJobs[pending][@"state"] isEqual:@"已接回"] && [self.skillBatches[pending] isEqual:exported[@"manifest"]] && [NSFileManager.defaultManager fileExistsAtPath:[[self skillFolder:pending] URLByAppendingPathComponent:@"materials.local.json"].path]){[self copySkillBatch:pending];[self status:@"相同材料已在等待识别，已复制原批次指令，无需重新分析。"];return;}
        NSError *failure=nil;NSString *batch=exported[@"context"][@"batchID"];NSURL *folder=[self skillFolder:batch];
        NSString *skill=[NSString stringWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"am-homework-extract" ofType:@"md"] encoding:NSUTF8StringEncoding error:&failure];
        BOOL ok=folder && skill && [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&failure];
        if(ok)[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0700} ofItemAtPath:folder.URLByDeletingLastPathComponent.path error:&failure];
        NSData *json=[NSJSONSerialization dataWithJSONObject:exported[@"context"] options:0 error:&failure];
        if(ok)ok=[json writeToURL:[folder URLByAppendingPathComponent:@"materials.local.json"] options:NSDataWritingAtomic error:&failure];
        if(ok)ok=[skill writeToURL:[folder URLByAppendingPathComponent:@"SKILL.md"] atomically:YES encoding:NSUTF8StringEncoding error:&failure];
        if(ok)ok=[@"复制应用提供的指令交给助手。助手写入 results.local.json 后，AM Helper 会自动接回并核验，作业进入待审核。不要将本目录上传到公开仓库。\n" writeToURL:[folder URLByAppendingPathComponent:@"使用说明.txt"] atomically:YES encoding:NSUTF8StringEncoding error:&failure];
        for(NSString *file in @[@"materials.local.json",@"SKILL.md",@"使用说明.txt"])if(ok)ok=[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:[folder URLByAppendingPathComponent:file].path error:&failure];
        if(!ok){[self showError:failure ?: [NSError errorWithDomain:@"AMSkill" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法创建安全的材料目录。"}]];return;}
        NSMutableDictionary *batches=self.skillBatches.mutableCopy;batches[batch]=exported[@"manifest"];
        NSMutableDictionary *jobs=self.skillJobs.mutableCopy;NSMutableArray *ids=NSMutableArray.array;for(NSDictionary *course in courses)[ids addObject:course[@"fork"]];
        jobs[batch]=@{@"state":@"等待助手",@"date":NSDate.date,@"courses":ids,@"count":@([exported[@"context"][@"documents"] count]),@"prepareSeconds":@(-started.timeIntervalSinceNow),@"message":[issues componentsJoinedByString:@"；"]};
        NSMutableDictionary *envelope=self.discoveryEnvelope.mutableCopy;envelope[@"skillBatches"]=batches;envelope[@"skillJobs"]=jobs;
        if(!SSWritePlist(@"discoveries.plist",envelope,&failure)){[self showError:failure];return;}self.skillBatches=batches;self.skillJobs=jobs;
        [self startSkillReception];[self watchSkillBatch:batch];[self status:[NSString stringWithFormat:@"已准备 %lu 份文档（%.1f 秒）· 等待助手识别；结果会自动接回。",(unsigned long)[exported[@"context"][@"documents"] count],-started.timeIntervalSinceNow]];
        NSAlert *ready=NSAlert.new;ready.messageText=@"材料已就绪";ready.informativeText=@"复制指令交给助手即可。结果会自动接回，无需选择文件导入；可在“更多 → 识别批次与进度”查看。";[ready addButtonWithTitle:@"复制指令"];[ready addButtonWithTitle:@"稍后"];if([ready runModal]==NSAlertFirstButtonReturn)[self copySkillBatch:batch];
    }];
}
- (void)copySkillBatch:(NSString *)batch {
    NSURL *folder=[self skillFolder:batch];if(!folder)return;NSString *prompt=[NSString stringWithFormat:@"读取 %@ 中的 SKILL.md 和 materials.local.json，分析本批所有课程，将结果先写入 results.local.json.tmp，完成后原子重命名为同目录 results.local.json。应用会自动接回。只生成识别建议，不修改应用任务库或执行课程 Git 操作。",folder.path];[NSPasteboard.generalPasteboard clearContents];[NSPasteboard.generalPasteboard setString:prompt forType:NSPasteboardTypeString];
}
- (void)showSkillJobs:(id)sender {if(self.hasUnsavedReview && ![self resolveUnsavedReview])return;self.showingSkillJobs=YES;[self refreshPresentation];}
- (void)cleanSkillJobs:(BOOL)all {
    NSDate *cutoff=[NSDate dateWithTimeIntervalSinceNow:-30*86400];BOOL changed=NO;
    for(NSString *batch in self.skillJobs.allKeys){NSDictionary *old=self.skillJobs[batch];if(![old[@"state"] isEqual:@"已接回"] || [old[@"cleaned"] boolValue] || (!all && [old[@"date"] compare:cutoff]!=NSOrderedAscending))continue;NSURL *folder=[self skillFolder:batch];NSError *error=nil;if(folder && (![NSFileManager.defaultManager fileExistsAtPath:folder.path] || [NSFileManager.defaultManager removeItemAtURL:folder error:&error])){NSMutableDictionary *job=old.mutableCopy;job[@"cleaned"]=@YES;self.skillJobs[batch]=job;changed=YES;}}
    if(changed)[self writeSkillState:NULL];
}
- (void)skillJobAction:(NSString *)action batch:(NSString *)batch {
    if([action isEqual:@"close"]){self.showingSkillJobs=NO;[self refreshPresentation];return;}if(self.busy || self.operationsPaused)return;
    if([action isEqual:@"copy"])[self copySkillBatch:batch];
    else if([action isEqual:@"reveal"]){NSURL *folder=[self skillFolder:batch];if(folder)[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[folder]];}
    else if([action isEqual:@"clean"]){[self cleanSkillJobs:YES];[self refreshPresentation];}
    else if([action isEqual:@"retry"]){NSMutableDictionary *job=[self.skillJobs[batch] mutableCopy];if(job){[job removeObjectForKey:@"fingerprint"];job[@"state"]=@"等待助手";self.skillJobs[batch]=job;[self writeSkillState:NULL];[self pollSkillResults:nil];}}
    else if([action isEqual:@"prepare-failed"]){NSMutableArray *courses=NSMutableArray.array;for(NSDictionary *course in self.courses)if([self.skillJobs[batch][@"courses"] containsObject:course[@"fork"]])[courses addObject:course.copy];[self prepareSkillCourses:courses all:NO manifest:self.skillBatches[batch]];}
    else if([action isEqual:@"prepare"])[self prepareSkill:NO];
}
- (void)pollSkillResults:(id)sender {
    if(self.preview || self.busy || self.operationsPaused || self.hasUnsavedReview || self.hasSubmissionSheet)return;
    for(NSString *batch in self.skillJobs.allKeys){NSDictionary *job=self.skillJobs[batch];if([job[@"state"] isEqual:@"已接回"])continue;NSURL *folder=[self skillFolder:batch];if(!folder || ![NSFileManager.defaultManager fileExistsAtPath:folder.path]){if(![job[@"state"] isEqual:@"需处理"])[self setSkillJob:batch state:@"需处理" message:@"材料目录已移除或不安全，请重新准备材料。"];continue;}
        NSURL *url=[folder URLByAppendingPathComponent:@"results.local.json"];if(![NSFileManager.defaultManager fileExistsAtPath:url.path])continue;
        NSError *failure=nil;NSDictionary *read=SSSkillReadResult(url,&failure);
        if(!read){if(![job[@"state"] isEqual:@"需处理"])[self setSkillJob:batch state:@"需处理" message:failure.localizedDescription];continue;}
        if([job[@"fingerprint"] isEqual:read[@"fingerprint"]])continue;
        if(![read[@"result"][@"batchID"] isEqual:batch]){[self setSkillJob:batch state:@"需处理" message:@"结果不属于这个批次，请让助手保留输入中的 batchID。"];continue;}
        [self receiveSkillResult:read[@"result"] batch:batch fingerprint:read[@"fingerprint"] legacy:nil automatic:YES];break;
    }
}
- (void)receiveSkillResult:(NSDictionary *)result batch:(NSString *)batch fingerprint:(NSString *)fingerprint legacy:(NSString *)legacy automatic:(BOOL)automatic {
    if(self.busy || self.operationsPaused)return;NSMutableArray *courses=NSMutableArray.array;
    for(NSDictionary *course in self.courses){BOOL relevant=NO;for(id document in result[@"documents"])if([document isKindOfClass:NSDictionary.class] && (legacy ? [course[@"fork"] isEqual:legacy]:[document[@"courseID"] isEqual:course[@"fork"]]))relevant=YES;if(relevant)[courses addObject:course.copy];}
    NSDictionary *batches=self.skillBatches.copy;NSDate *started=NSDate.date;if(batch)[self setSkillJob:batch state:@"核验中" message:@"正在核对本批来源与版本…"];
    [self work:@"核验中 · 正在接回助手结果…" forCourse:nil operation:^id(NSError **error){NSDictionary *scans=[self readSkillCourses:courses result:result];NSDictionary *validated=SSSkillValidateBatch(result,courses,scans,batches,legacy,error);return validated ? [self.git resolveSkillDates:validated scans:scans courses:courses]:nil;} completion:^(NSDictionary *validated,NSError *error){
        // A verification read is scoped to returned files. Invalidate old full
        // preparation snapshots rather than replacing them with a partial scan.
        NSMutableDictionary *reports=self.reports.mutableCopy ?: NSMutableDictionary.dictionary;for(NSDictionary *course in courses)[reports removeObjectForKey:course[@"fork"]];self.reports=reports;
        if(!validated){if(batch){NSMutableDictionary *job=[self.skillJobs[batch] mutableCopy];if(job && fingerprint){job[@"fingerprint"]=fingerprint;self.skillJobs[batch]=job;}[self setSkillJob:batch state:@"需处理" message:error.localizedDescription];}[self status:error.localizedDescription ?: @"助手结果核验失败，可在批次进度重试。"];return;}
        if(!automatic){NSAlert *preview=NSAlert.new;preview.messageText=@"接回助手识别建议";preview.informativeText=[NSString stringWithFormat:@"可接回 %lu 份文档。%@",(unsigned long)[validated[@"progress"] count],[validated[@"issues"] componentsJoinedByString:@"；"]];[preview addButtonWithTitle:@"接回有效建议"];[preview addButtonWithTitle:@"取消"];if([preview runModal]!=NSAlertFirstButtonReturn){if(batch)[self setSkillJob:batch state:@"等待助手" message:@"已取消手动接回。"];return;}}
        NSMutableDictionary *candidates=self.candidates.mutableCopy,*materials=self.materials.mutableCopy,*progress=self.skillProgress.mutableCopy;[progress addEntriesFromDictionary:validated[@"progress"]];
        for(NSString *fork in validated[@"records"]){NSMutableDictionary *byID=NSMutableDictionary.dictionary;for(NSDictionary *record in [(candidates[fork] ?: @[]) arrayByAddingObjectsFromArray:materials[fork] ?: @[]])byID[record[@"id"]]=record;for(NSDictionary *record in validated[@"records"][fork])byID[record[@"id"]]=record;NSMutableArray *assignments=NSMutableArray.array,*other=NSMutableArray.array;for(NSDictionary *record in byID.allValues){if([record[@"kind"] isEqual:@"assignment"])[assignments addObject:record];else[other addObject:record];}candidates[fork]=SSConsolidateAssignments(assignments);materials[fork]=SSGroupMaterials(other);}
        NSMutableDictionary *jobs=self.skillJobs.mutableCopy;NSString *message=[NSString stringWithFormat:@"接回 %lu 份文档（%.1f 秒核验）%@",(unsigned long)[validated[@"progress"] count],-started.timeIntervalSinceNow,[validated[@"issues"] count] ? [@"；" stringByAppendingString:[validated[@"issues"] componentsJoinedByString:@"；"]]:@"；作业已进入待审核。"];
        if(batch && jobs[batch]){NSMutableDictionary *job=[jobs[batch] mutableCopy];job[@"state"]=[validated[@"issues"] count] ? @"需处理":@"已接回";job[@"message"]=message;job[@"verifySeconds"]=@(-started.timeIntervalSinceNow);job[@"waitSeconds"]=@([started timeIntervalSinceDate:job[@"date"]]);if(fingerprint)job[@"fingerprint"]=fingerprint;jobs[batch]=job;}
        NSMutableDictionary *envelope=[[self discoveryEnvelope:candidates materials:materials progress:progress batches:self.skillBatches] mutableCopy];envelope[@"skillJobs"]=jobs;NSError *failure=nil;
        if(!SSWritePlist(@"discoveries.plist",envelope,&failure)){if(batch){NSMutableDictionary *job=[self.skillJobs[batch] mutableCopy];if(job && fingerprint){job[@"fingerprint"]=fingerprint;self.skillJobs[batch]=job;}[self setSkillJob:batch state:@"需处理" message:@"保存失败，未推进进度；请重试。"];}[self status:@"助手结果保存失败，未推进进度；请重试。"];return;}
        self.candidates=candidates;self.materials=materials;self.skillProgress=progress;self.skillJobs=jobs;for(NSString *fork in validated[@"counts"])self.statuses[fork]=[NSString stringWithFormat:@"助手已接回 %@ 份文档、%lu 项建议；作业需审核后加入安排。",validated[@"counts"][fork],(unsigned long)[validated[@"records"][fork] count]];[self status:message];
    }];
}
- (void)importSkillResults:(id)sender {
    if(self.preview || self.busy || self.operationsPaused)return;if(self.hasUnsavedReview && ![self resolveUnsavedReview])return;
    NSOpenPanel *panel=NSOpenPanel.openPanel;panel.title=@"手动导入助手结果";panel.canChooseDirectories=NO;panel.allowsMultipleSelection=NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse answer){if(answer!=NSModalResponseOK)return;NSError *error=nil;NSDictionary *read=SSSkillReadResult(panel.URL,&error),*result=read[@"result"];if(!result){[self showError:error];return;}NSString *legacy=nil;
        if([result[@"format"] isEqual:@"am-course-results-v1"]){NSMutableArray *matches=NSMutableArray.array;for(NSDictionary *course in self.courses){BOOL compatible=[result[@"documents"] count]>0;for(id doc in result[@"documents"])if(![doc isKindOfClass:NSDictionary.class] || ![doc[@"repository"] isEqual:course[@"upstream"]])compatible=NO;if(compatible && [course[@"path"] length])[matches addObject:course[@"fork"]];}
            if(matches.count==1)legacy=matches.firstObject;else if(matches.count>1){NSAlert *pick=NSAlert.new;pick.messageText=@"选择旧版结果所属课程";NSPopUpButton *menu=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,340,32)];[menu addItemsWithTitles:matches];pick.accessoryView=menu;[pick addButtonWithTitle:@"核验"];[pick addButtonWithTitle:@"取消"];if([pick runModal]!=NSAlertFirstButtonReturn)return;legacy=menu.titleOfSelectedItem;}}
        [self receiveSkillResult:result batch:result[@"batchID"] fingerprint:read[@"fingerprint"] legacy:legacy automatic:NO];
    }];
}
