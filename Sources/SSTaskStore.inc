// Included by the local-data module so every executable shares the same persistence path.
static NSError *StoreError(NSString *text) {return [NSError errorWithDomain:@"AMTaskStore" code:1 userInfo:@{NSLocalizedDescriptionKey:text}];}
static BOOL ValidTasks(id value) {
    if(![value isKindOfClass:NSArray.class])return NO;
    NSMutableSet *ids=NSMutableSet.set;
    for(id task in value){if(![task isKindOfClass:NSDictionary.class] || ![task[@"title"] isKindOfClass:NSString.class] || ![task[@"due"] isKindOfClass:NSDate.class])return NO;NSString *key=task[@"id"];if(![key isKindOfClass:NSString.class] || !key.length || [ids containsObject:key])return NO;[ids addObject:key];}return YES;
}
static NSURL *RecoveryRoot(void) {return [SSDataDirectory().URLByResolvingSymlinksInPath URLByAppendingPathComponent:@"TaskRecovery" isDirectory:YES];}
NSArray *SSLoadTasks(NSError **error) {
    NSURL *url=[SSDataDirectory() URLByAppendingPathComponent:@"tasks.plist"];if(![NSFileManager.defaultManager fileExistsAtPath:url.path])return @[];
    NSData *data=[NSData dataWithContentsOfURL:url options:0 error:error];id decoded=data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error]:nil;
    // Legacy missing IDs are normalized by the caller, but malformed records must not silently disappear.
    BOOL valid=[decoded isKindOfClass:NSArray.class];if(valid)for(id task in decoded)if(![task isKindOfClass:NSDictionary.class] || ![task[@"title"] isKindOfClass:NSString.class] || ![task[@"due"] isKindOfClass:NSDate.class]){valid=NO;break;}
    if(!valid){if(data){NSURL *copy=[RecoveryRoot() URLByAppendingPathComponent:[NSString stringWithFormat:@"damaged-%@.bin",NSUUID.UUID.UUIDString]];[NSFileManager.defaultManager createDirectoryAtURL:RecoveryRoot() withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];[data writeToURL:copy options:NSDataWritingAtomic error:NULL];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:copy.path error:NULL];}if(error)*error=StoreError(@"任务文件无法完整读取，已保留原文件。请先在“文件 → 恢复任务…”预览恢复点；不会用空任务覆盖原数据。");return nil;}return decoded;
}
NSArray<NSDictionary *> *SSRecoveryPoints(void) {
    NSMutableArray *points=NSMutableArray.array;for(NSURL *url in [NSFileManager.defaultManager contentsOfDirectoryAtURL:RecoveryRoot() includingPropertiesForKeys:nil options:0 error:NULL]){if(![url.pathExtension isEqual:@"plist"])continue;NSDictionary *point=[NSDictionary dictionaryWithContentsOfURL:url];if(!ValidTasks(point[@"tasks"]) || ![point[@"date"] isKindOfClass:NSDate.class])continue;[points addObject:@{@"id":url.lastPathComponent,@"date":point[@"date"],@"kind":point[@"kind"] ?: @"change",@"count":@([point[@"tasks"] count])}];}return [points sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return [b[@"date"] compare:a[@"date"]];}];
}
NSArray *SSRecoveryTasks(NSString *identifier,NSError **error) {
    if(![identifier isEqual:identifier.lastPathComponent] || ![identifier hasSuffix:@".plist"]){if(error)*error=StoreError(@"恢复点标识无效。");return nil;}
    NSURL *root=RecoveryRoot().URLByResolvingSymlinksInPath,*url=[root URLByAppendingPathComponent:identifier];if(![url.path isEqual:url.URLByResolvingSymlinksInPath.path]){if(error)*error=StoreError(@"恢复点路径不安全。");return nil;}
    NSDictionary *point=[NSDictionary dictionaryWithContentsOfURL:url];if(!ValidTasks(point[@"tasks"])){if(error)*error=StoreError(@"恢复点损坏，未修改任务。");return nil;}return point[@"tasks"];
}
BOOL SSSaveTasks(NSArray *previous,NSArray *tasks,NSError **error) {
    if(!ValidTasks(previous) || !ValidTasks(tasks)){if(error)*error=StoreError(@"任务校验失败，未写入任何修改。");return NO;}
    NSFileManager *fm=NSFileManager.defaultManager;NSURL *root=RecoveryRoot();if(![root.path isEqual:root.URLByResolvingSymlinksInPath.path]){if(error)*error=StoreError(@"恢复目录路径不安全，未保存任务。请检查数据目录。");return NO;}if(![fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return NO;
    NSDate *now=NSDate.date;NSDateFormatter *fmt=NSDateFormatter.new;fmt.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];fmt.dateFormat=@"yyyy-MM-dd";
    NSURL *daily=[root URLByAppendingPathComponent:[NSString stringWithFormat:@"daily-%@.plist",[fmt stringFromDate:now]]];
    NSMutableArray *created=NSMutableArray.array;NSArray *names=[fm fileExistsAtPath:daily.path] ? @[[NSString stringWithFormat:@"change-%@.plist",NSUUID.UUID.UUIDString]]:@[daily.lastPathComponent,[NSString stringWithFormat:@"change-%@.plist",NSUUID.UUID.UUIDString]];
    for(NSString *name in names){NSDictionary *point=@{@"tasks":previous,@"date":now,@"kind":[name hasPrefix:@"daily"] ? @"daily":@"change"};NSData *data=[NSPropertyListSerialization dataWithPropertyList:point format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];NSURL *url=[root URLByAppendingPathComponent:name];if(!data || ![data writeToURL:url options:NSDataWritingAtomic error:error]){for(NSURL *item in created)[fm removeItemAtURL:item error:NULL];return NO;}[created addObject:url];[fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:url.path error:NULL];}
    if(!SSWritePlist(@"tasks.previous.plist",previous,error) || !SSWritePlist(@"tasks.plist",tasks,error)){for(NSURL *url in created)[fm removeItemAtURL:url error:NULL];return NO;}
    NSUInteger changes=0;NSDate *cutoff=[NSCalendar.currentCalendar dateByAddingUnit:NSCalendarUnitDay value:-6 toDate:[NSCalendar.currentCalendar startOfDayForDate:now] options:0];
    for(NSDictionary *point in SSRecoveryPoints()){BOOL dailyPoint=[point[@"kind"] isEqual:@"daily"];if((dailyPoint && [point[@"date"] compare:cutoff]==NSOrderedAscending) || (!dailyPoint && ++changes>10))[fm removeItemAtURL:[root URLByAppendingPathComponent:point[@"id"]] error:NULL];}return YES;
}
void SSDiagnostic(NSString *stage,NSString *outcome,NSTimeInterval seconds) {
    // Allowlisted categories only: underlying error text and identifiers are deliberately excluded.
    if(![@[@"load",@"save",@"review",@"scan",@"skill",@"operation",@"reminder",@"render",@"search",@"startup"] containsObject:stage] || ![@[@"started",@"success",@"failed",@"cancelled",@"timeout"] containsObject:outcome])return;
    @synchronized(NSFileManager.defaultManager){NSMutableArray *events=[SSDiagnostics() mutableCopy];[events addObject:@{@"date":NSDate.date,@"stage":stage,@"outcome":outcome,@"seconds":@(MAX(0,MIN(86400,seconds)))}];while(events.count>200)[events removeObjectAtIndex:0];SSWritePlist(@"quality-diagnostics.plist",events,NULL);}
}
NSArray<NSDictionary *> *SSDiagnostics(void) {id stored=SSReadPlist(@"quality-diagnostics.plist");NSMutableArray *result=NSMutableArray.array;if([stored isKindOfClass:NSArray.class])for(id row in stored)if([row isKindOfClass:NSDictionary.class] && [row[@"date"] isKindOfClass:NSDate.class] && [row[@"stage"] isKindOfClass:NSString.class] && [row[@"outcome"] isKindOfClass:NSString.class] && [row[@"seconds"] isKindOfClass:NSNumber.class] && [@[@"load",@"save",@"review",@"scan",@"skill",@"operation",@"reminder",@"render",@"search",@"startup"] containsObject:row[@"stage"]] && [@[@"started",@"success",@"failed",@"cancelled",@"timeout"] containsObject:row[@"outcome"]])[result addObject:@{@"date":row[@"date"],@"stage":row[@"stage"],@"outcome":row[@"outcome"],@"seconds":row[@"seconds"]}];return result;}
