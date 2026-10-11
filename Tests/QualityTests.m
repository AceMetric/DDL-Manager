#import "../Sources/SSLocalData.h"
#import "../Sources/DDLCore.h"
#include <stdio.h>
static NSUInteger checks;
static void Check(BOOL ok,NSString *message){checks++;if(!ok){fprintf(stderr,"FAIL: %s\n",message.UTF8String);exit(1);}}
int main(void){@autoreleasepool{
    Check(NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"].length>0,@"test storage is isolated");
    NSError *error=nil;Check([SSLoadTasks(&error) isEqual:@[]] && !error,@"missing store starts empty");
    NSDictionary *task=@{@"id":@"stable",@"title":@"模拟作业",@"due":[NSDate dateWithTimeIntervalSinceNow:86400],@"notes":@"可恢复备注",@"sourceID":@"source",@"sourceBlob":@"fixed"};
    Check(SSSaveTasks(@[],@[task],&error),@"first task persisted");Check([SSLoadTasks(NULL) isEqual:@[task]],@"saved task reloads exactly");
    for(NSUInteger i=0;i<15;i++){NSMutableDictionary *next=task.mutableCopy;next[@"notes"]=[NSString stringWithFormat:@"修改%lu",(unsigned long)i];NSArray *before=SSLoadTasks(NULL);Check(SSSaveTasks(before,@[next],&error),@"rolling save succeeds");}
    NSUInteger changes=0,daily=0;for(NSDictionary *point in SSRecoveryPoints()){if([point[@"kind"] isEqual:@"daily"])daily++;else changes++;}
    Check(changes==10 && daily==1,@"ten operation backups and today's single daily backup retained");
    NSDictionary *point=SSRecoveryPoints().firstObject;Check([SSRecoveryTasks(point[@"id"],NULL) count]==1,@"preview recovery without modifying current store");
    Check(!SSRecoveryTasks(@"../tasks.plist",NULL),@"path traversal recovery rejected");
    NSArray *before=SSLoadTasks(NULL);Check(!SSSaveTasks(before,@[@{@"id":@"invalid"}],NULL),@"invalid replacement rejected");Check([SSLoadTasks(NULL) isEqual:before],@"invalid replacement preserves tasks");
    NSURL *primary=[SSDataDirectory() URLByAppendingPathComponent:@"tasks.plist"];NSData *damaged=[@"not a plist" dataUsingEncoding:NSUTF8StringEncoding];[damaged writeToURL:primary atomically:YES];
    error=nil;Check(!SSLoadTasks(&error) && error,@"corrupt file is not interpreted as empty task list");Check([[NSData dataWithContentsOfURL:primary] isEqual:damaged],@"corrupt original bytes preserved");
    BOOL preserved=NO;for(NSURL *url in [NSFileManager.defaultManager contentsOfDirectoryAtURL:[SSDataDirectory() URLByAppendingPathComponent:@"TaskRecovery"] includingPropertiesForKeys:nil options:0 error:NULL])if([url.pathExtension isEqual:@"bin"] && [[NSData dataWithContentsOfURL:url] isEqual:damaged])preserved=YES;Check(preserved,@"raw damaged bytes have separate recovery copy");
    Check(SSSaveTasks(@[],before,NULL),@"explicit recovery can persist valid task snapshot");
    NSURL *backup=[SSDataDirectory() URLByAppendingPathComponent:@"tasks.previous.plist"];[NSFileManager.defaultManager removeItemAtURL:backup error:NULL];[NSFileManager.defaultManager createDirectoryAtURL:backup withIntermediateDirectories:NO attributes:nil error:NULL];
    Check(!SSSaveTasks(before,@[],NULL),@"backup failure prevents replacement");Check([SSLoadTasks(NULL) isEqual:before],@"backup failure preserves primary task file");
    SSDiagnostic(@"scan",@"success",1.25);SSDiagnostic(@"private-content",@"secret-value",2);
    Check(SSDiagnostics().count==1 && [SSDiagnostics()[0][@"stage"] isEqual:@"scan"],@"diagnostics allow categories only");
    for(NSUInteger i=0;i<220;i++)SSDiagnostic(@"save",@"success",0);Check(SSDiagnostics().count==200,@"diagnostic history bounded");
    printf("PASS: %lu quality storage assertions\n",(unsigned long)checks);
}return 0;}
