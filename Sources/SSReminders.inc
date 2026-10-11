@interface AMReminderScheduler:NSObject
@property NSInteger generation;
@property NSInteger scheduled;
@property NSString *error;
@property NSString *notice;
@property(copy) void (^changed)(NSInteger,NSString *,NSString *);
- (void)schedule:(NSArray *)tasks;
@end
@implementation AMReminderScheduler
- (void)publish {if(self.changed)self.changed(self.scheduled,self.error,self.notice);}
- (void)schedule:(NSArray *)tasks {
    self.error = nil;self.notice=nil;
    NSInteger generation = ++self.generation;
    NSDate *now = NSDate.date; NSMutableArray *plans = [NSMutableArray array];
    for (NSDictionary *task in tasks) [plans addObjectsFromArray:DDLReminderPlan(task, now, Cal())];
    [plans sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"date"] compare:b[@"date"]]; }];
    // Keep the nearest reminders queued. Refill while running, on wake, and on launch.
    NSArray *queue = [plans subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)60, plans.count))];
    UNUserNotificationCenter *center = UNUserNotificationCenter.currentNotificationCenter;
    [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *pending) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) return;
            NSMutableDictionary *existing = [NSMutableDictionary dictionary]; for (UNNotificationRequest *r in pending) existing[r.identifier] = r;
            NSMutableSet *desired = [NSMutableSet set];
            dispatch_group_t scheduled = dispatch_group_create();
            for (NSDictionary *plan in queue) {
                NSString *identifier = plan[@"id"]; [desired addObject:identifier]; NSDictionary *task = plan[@"task"];
                NSString *body = [NSString stringWithFormat:@"%@：%@\n截止 %@", plan[@"message"], task[@"title"], DDLFormatDate(task[@"due"], @"M月d日 HH:mm")];
                UNNotificationRequest *old = existing[identifier]; NSDate *oldDate = [old.trigger isKindOfClass:UNCalendarNotificationTrigger.class] ? [(UNCalendarNotificationTrigger *)old.trigger nextTriggerDate] : nil;
                if (oldDate && fabs([oldDate timeIntervalSinceDate:plan[@"date"]]) < 1 && [old.content.body isEqual:body] && [old.content.title isEqual:task[@"subject"]]) continue;
                UNMutableNotificationContent *content = [UNMutableNotificationContent new]; content.title = task[@"subject"]; content.body = body; content.sound = UNNotificationSound.defaultSound; content.threadIdentifier = task[@"id"]; content.userInfo = @{@"taskID":task[@"id"]};
                NSDateComponents *parts = [Cal() components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond) fromDate:plan[@"date"]]; parts.timeZone = NSTimeZone.localTimeZone;
                UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:parts repeats:NO];
                UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:identifier content:content trigger:trigger];
                dispatch_group_enter(scheduled);
                [center addNotificationRequest:request withCompletionHandler:^(NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (error && generation == self.generation) { self.error = error.localizedDescription; self.notice = @"任务已保存，但提醒安排失败。请在设置中查看通知权限并重试。"; [self publish]; }
                        dispatch_group_leave(scheduled);
                    });
                }];
            }
            NSMutableArray *stale = [NSMutableArray array];
            for (UNNotificationRequest *request in pending) if (![desired containsObject:request.identifier] && ![request.identifier isEqual:@"ddl.test"]) [stale addObject:request.identifier];
            if (stale.count) [center removePendingNotificationRequestsWithIdentifiers:stale];
            if (plans.count > 60) self.notice = @"已优先安排最近 60 条提醒；保持应用运行以继续补充后续提醒。";
            dispatch_group_notify(scheduled, dispatch_get_main_queue(), ^{
                [center getPendingNotificationRequestsWithCompletionHandler:^(NSArray<UNNotificationRequest *> *actual) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (generation != self.generation) return;
                        NSInteger count = 0; for (UNNotificationRequest *r in actual) if ([desired containsObject:r.identifier]) count++;
                        self.scheduled = count;SSDiagnostic(@"reminder",self.error ? @"failed":@"success",0); [self publish];
                    });
                }];
            });
            NSMutableSet *activeIDs = [NSMutableSet set]; for (NSDictionary *task in tasks) if (![task[@"completed"] boolValue] && ![task[@"archived"] boolValue]) [activeIDs addObject:task[@"id"]];
            [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> *notifications) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (generation != self.generation) return;
                    NSMutableArray *finished = [NSMutableArray array]; for (UNNotification *n in notifications) { NSString *taskID = n.request.content.userInfo[@"taskID"]; if (taskID && ![activeIDs containsObject:taskID]) [finished addObject:n.request.identifier]; }
                    if (finished.count) [center removeDeliveredNotificationsWithIdentifiers:finished];
                });
            }];
        });
    }];
}
@end
