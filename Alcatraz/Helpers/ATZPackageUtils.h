#import <Foundation/Foundation.h>

@class ATZPackage;

@interface ATZPackageUtils : NSObject

/*
 * Getters
 */
+ (NSArray *)localPackages;
+ (NSArray *)remotePackages;
+ (NSArray *)allPackages;

+ (NSSet *)addedLocalPackages;
+ (NSSet *)addedRemotePackages;

/*
 * Reloaders
 */
+ (void)reloadPackages;

/*
 * User Notification Methods
 */
+ (void)postUserNotificationForInstalledPackage:(ATZPackage *)package;
+ (void)postUserNotificationForUpdatedPackage:(ATZPackage *)package;

@end
