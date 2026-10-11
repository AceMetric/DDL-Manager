#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface SSGit : NSObject
@property(atomic) BOOL readsCancellable;
@property(atomic) BOOL cancelledReads;
/// Required before cloning, committing, merging or pushing. Rechecks GitHub ownership.
@property (copy, nullable) void (^progress)(NSString *phase);
/// Non-nil only for OAuth. Called after target validation; never used for legacy SSH.
@property (copy, nullable) NSString * _Nullable (^teacherCredentialProvider)(NSDictionary *course, NSError **error);
- (NSArray<NSString *> * _Nullable)remoteArguments:(NSArray<NSString *> *)arguments course:(NSDictionary *)course role:(NSString *)role error:(NSError **)error;
- (NSDictionary<NSString *, NSArray<NSString *> *> *)matchingDirectories:(NSString *)root courses:(NSArray<NSDictionary *> *)courses;
@property (copy, nullable) NSDictionary *recognitionSettings;
@property (copy) NSDictionary * _Nullable (^identityVerifier)(NSDictionary *course, NSError **error);
/// Course keys: fork, upstream, branch, upstreamBranch, path, upstreamURL.
- (BOOL)validateCourse:(NSDictionary *)course error:(NSError **)error;
- (BOOL)linkCourse:(NSDictionary *)course error:(NSError **)error;
- (BOOL)cloneFork:(NSDictionary *)course into:(NSString *)destination token:(NSString *)token error:(NSError **)error;
/// Read teacher documents without running recognition; optional paths bound result verification.
- (NSDictionary * _Nullable)readCourseDocuments:(NSDictionary *)course paths:(nullable NSArray<NSString *> *)paths fetch:(BOOL)fetch cache:(NSMutableDictionary *)cache error:(NSError **)error;
- (NSDictionary * _Nullable)scanCourse:(NSDictionary *)course cache:(NSMutableDictionary *)cache error:(NSError **)error;
- (NSDictionary *)resolveSkillDates:(NSDictionary *)validated scans:(NSDictionary *)scans courses:(NSArray *)courses;
- (NSDictionary *)enhanceScan:(NSDictionary *)scan course:(NSDictionary *)course settings:(NSDictionary *)settings paths:(nullable NSArray *)paths cache:(NSMutableDictionary *)cache;
- (NSDictionary * _Nullable)syncCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error;
- (NSArray<NSDictionary *> * _Nullable)changesForCourse:(NSDictionary *)course error:(NSError **)error;
/// Read-only, bounded, credential-redacted preview; never executes diff drivers.
- (NSString * _Nullable)previewForCourse:(NSDictionary *)course path:(NSString *)path error:(NSError **)error;
- (BOOL)commitCourse:(NSDictionary *)course paths:(NSArray<NSString *> *)paths message:(NSString *)message
      login:(NSString *)login userID:(NSNumber *)userID token:(NSString *)token error:(NSError **)error;
- (BOOL)continueMergeForCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error;
- (BOOL)pushCourse:(NSDictionary *)course token:(NSString *)token error:(NSError **)error;
- (BOOL)stageResolvedFiles:(NSDictionary *)course paths:(NSArray<NSString *> *)paths error:(NSError **)error;
- (BOOL)abortMerge:(NSDictionary *)course error:(NSError **)error;
- (NSArray<NSString *> * _Nullable)conflicts:(NSDictionary *)course error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
