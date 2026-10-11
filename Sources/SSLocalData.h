#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
NSURL *SSDataDirectory(void);
id _Nullable SSReadPlist(NSString *name);
BOOL SSWritePlist(NSString *name, id value, NSError **error);
NSDictionary * _Nullable SSReadSecret(NSString *account);
BOOL SSWriteSecret(NSString *account, NSDictionary *value);
void SSDeleteSecret(NSString *account);
NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN
// Task-only recovery points; credentials and course directories are never backed up.
NSArray * _Nullable SSLoadTasks(NSError **error);
BOOL SSSaveTasks(NSArray *previous, NSArray *tasks, NSError **error);
NSArray<NSDictionary *> *SSRecoveryPoints(void);
NSArray * _Nullable SSRecoveryTasks(NSString *identifier, NSError **error);
void SSDiagnostic(NSString *stage, NSString *outcome, NSTimeInterval seconds);
NSArray<NSDictionary *> *SSDiagnostics(void);

NS_ASSUME_NONNULL_END
