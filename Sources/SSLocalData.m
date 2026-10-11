#import "SSLocalData.h"
#import <Security/Security.h>

NSURL *SSDataDirectory(void) {
#ifdef DDL_TESTING
    // Compiled only into isolated test applications, never into a distributable build.
    NSString *testPath = [NSBundle.mainBundle objectForInfoDictionaryKey:@"DDLTestDataDirectory"] ?: NSProcessInfo.processInfo.environment[@"AM_TEST_DATA"];
    if (testPath) return [NSURL fileURLWithPath:testPath isDirectory:YES];
#endif
    // This historical directory is a compatibility identifier, not the product name.
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [base URLByAppendingPathComponent:@"SS Homework Manager" isDirectory:YES];
}

id SSReadPlist(NSString *name) {
    if ([name containsString:@"/"]) return nil;
    NSData *data = [NSData dataWithContentsOfURL:[SSDataDirectory() URLByAppendingPathComponent:name]];
    return data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
}

BOOL SSWritePlist(NSString *name, id value, NSError **error) {
    if ([name containsString:@"/"]) return NO;
    NSURL *directory = SSDataDirectory();
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    NSURL *target = [directory URLByAppendingPathComponent:name];
    BOOL ok = [data writeToURL:target options:NSDataWritingAtomic error:error];
    if (ok) [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:target.path error:NULL];
    return ok;
}

static NSMutableDictionary *KeychainQuery(NSString *account) {
    // This service identifier is persistent data, not the public product name.
    NSString *service = @"io.github.acemetric.sshomeworkmanager.github";
#ifdef DDL_TESTING
    service = [NSBundle.mainBundle objectForInfoDictionaryKey:@"DDLTestKeychainService"] ?: @"io.github.ddl-manager.unit-tests";
#endif
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:service,
              (__bridge id)kSecAttrAccount:account} mutableCopy];
}

NSDictionary *SSReadSecret(NSString *account) {
    NSMutableDictionary *query = KeychainQuery(account);
#ifdef DDL_TESTING
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    query[(__bridge id)kSecUseAuthenticationUI]=(__bridge id)kSecUseAuthenticationUIFail;
#pragma clang diagnostic pop
#endif
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef item = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &item) != errSecSuccess) return nil;
    NSData *data = CFBridgingRelease(item);
    id decoded = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    return [decoded isKindOfClass:NSDictionary.class] ? decoded : nil;
}

BOOL SSWriteSecret(NSString *account, NSDictionary *value) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if (!data) return NO;
    NSMutableDictionary *query = KeychainQuery(account);
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if (status == errSecItemNotFound) {
        query[(__bridge id)kSecValueData] = data;
        query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
    return status == errSecSuccess;
}

void SSDeleteSecret(NSString *account) { SecItemDelete((__bridge CFDictionaryRef)KeychainQuery(account)); }

#import "SSTaskStore.inc"
