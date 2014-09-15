#import "ATZPackageUtils.h"

#import "Alcatraz.h"
#import "ATZConstants.h"
#import "ATZDownloader.h"
#import "ATZPackage.h"
#import "ATZPackageFactory.h"
#import "ATZPBXProjParser.h"
#import "ATZUtils.h"

static NSArray *__localPackages;
static NSArray *__remotePackages;

static NSMutableSet *__addedRemotePackageNames;
static NSMutableSet *__addedLocalPackageNames;

static NSDictionary *__cachedPackages;

@interface ATZPackageUtils () <NSUserNotificationCenterDelegate>
@end

@implementation ATZPackageUtils

#pragma mark -
#pragma mark Private Methods

+ (ATZPackageUtils *)shared
{
  static ATZPackageUtils *shared;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    shared = [[ATZPackageUtils alloc] init];

    __addedRemotePackageNames = [NSMutableSet set];
    __addedLocalPackageNames = [NSMutableSet set];
  });
  return shared;
}

#pragma mark -
#pragma mark Public Getters

+ (NSArray *)localPackages
{
  return __localPackages;
}

+ (NSArray *)remotePackages
{
  return __remotePackages;
}

+ (NSArray *)allPackages
{
  return [__localPackages arrayByAddingObjectsFromArray:__remotePackages];
}

#pragma mark -
#pragma mark Public Methods

+ (void)reloadPackages
{
  [self reloadLocalPackages];

  ATZDownloader *downloader = [ATZDownloader new];
  [downloader downloadPackageListWithCompletion:^(NSDictionary *packageList, NSError *error) {
    if (error) {
      NSLog(@"[Alcatraz][ATZPackageUtils] Error while downloading packages! %@", error);
    } else {
      __remotePackages = [ATZPackageFactory createPackagesFromDicts:packageList];
      [[NSNotificationCenter defaultCenter] postNotificationName:kATZListOfPackagesWasUpdatedNotification object:nil];
      [self updatePackages:__remotePackages];

      // get added local package names and inform people about them
      [__addedRemotePackageNames addObjectsFromArray:[self addedPackageNamesTo:packageList forCachedListKey:kATZCachedRemotePackagesListKey]];
      if ([__addedRemotePackageNames count] && [[self cachedPackageLists][kATZCachedRemotePackagesListKey] count]) {
        [self postUserNotificationForAddedPackages:__addedRemotePackageNames];
      }

      // cache package list
      [self cachePackageList:packageList forCachedListKey:kATZCachedRemotePackagesListKey];
    }
  }];
}

+ (void)reloadLocalPackages
{
  NSDictionary *localPackagesRaw = [self _localPackageListInRawFormat];
  __localPackages = [ATZPackageFactory createPackagesFromDicts:localPackagesRaw];
  [[NSNotificationCenter defaultCenter] postNotificationName:kATZListOfPackagesWasUpdatedNotification object:nil];
  [self updatePackages:__localPackages];

  // get added local package names and inform people about them
  [__addedLocalPackageNames addObjectsFromArray:[self addedPackageNamesTo:localPackagesRaw forCachedListKey:kATZCachedLocalPackagesListKey]];
  if ([__addedLocalPackageNames count]) {
    [self postUserNotificationForAddedPackages:__addedLocalPackageNames];
  }

  // cache package list
  [self cachePackageList:localPackagesRaw forCachedListKey:kATZCachedLocalPackagesListKey];
}

#pragma mark -
#pragma mark Methods to update packages

+ (void)updatePackages:(NSArray *)packages
{
  for (ATZPackage *package in packages) {
    if ([package isInstalled]) {
      [self enqueuePackageUpdate:package];
    }
  }
}

+ (void)enqueuePackageUpdate:(ATZPackage *)package
{
  if (!package.isInstalled) {
    return;
  }

  NSOperation *updateOperation = [NSBlockOperation blockOperationWithBlock:^{
    [package updateWithProgress:^(NSString *progressMessage, CGFloat progress){}
                     completion:^(NSError *failure, BOOL updated) {
      if (failure) {
        NSLog(@"[Alcatraz][ATZPackageUtils] Error while updating package %@! %@", package.name, failure);
        return;
      } else if (updated) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kATZPackageWasUpdatedNotification object:package];
        [self postUserNotificationForUpdatedPackage:package];
      }
    }];
  }];
  if ([[NSOperationQueue mainQueue] operations].lastObject) {
    [updateOperation addDependency:[[NSOperationQueue mainQueue] operations].lastObject];
  }
  [[NSOperationQueue mainQueue] addOperation:updateOperation];
}

#pragma mark -
#pragma mark Methods to work with cached package lists

+ (NSArray *)addedPackageNamesTo:(NSDictionary *)latestPackages forCachedListKey:(NSString *)listKey
{
  NSMutableArray *addedPackages = [NSMutableArray array];
  NSDictionary *cachedPackages = [self cachedPackageLists][listKey];
  for (NSString *key in latestPackages) {
    NSArray *cachedArray = [cachedPackages[key] valueForKeyPath:kATZPackageNameKey];
    NSArray *latestArray = [latestPackages[key] valueForKeyPath:kATZPackageNameKey];
    for (NSString *latestPackage in latestArray) {
      if (![cachedArray containsObject:latestPackage]) {
        [addedPackages addObject:latestPackage];
      }
    }
  }
  return addedPackages;
}

+ (void)cachePackageList:(NSDictionary *)packages forCachedListKey:(NSString *)listKey
{
  NSString *path = [ATZPluginsDataDirectoryPath() stringByAppendingPathComponent:kATZCachedPackagesFile];
  NSDictionary *cachedPackageLists = [self cachedPackageLists];

  NSMutableDictionary *updatedPackageLists = [NSMutableDictionary dictionaryWithDictionary:cachedPackageLists];
  updatedPackageLists[listKey] = packages ?: @{};

  __cachedPackages = [updatedPackageLists copy];
  [__cachedPackages writeToFile:path atomically:YES];
}

+ (NSDictionary *)cachedPackageLists
{
  if (!__cachedPackages) {
    NSString *path = [ATZPluginsDataDirectoryPath() stringByAppendingPathComponent:kATZCachedPackagesFile];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
      __cachedPackages = @{kATZCachedRemotePackagesListKey:@{}, kATZCachedLocalPackagesListKey:@{}};
    } else {
      __cachedPackages = [NSDictionary dictionaryWithContentsOfFile:path];
      if (!__cachedPackages) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        __cachedPackages = @{kATZCachedRemotePackagesListKey:@{}, kATZCachedLocalPackagesListKey:@{}};
      }
    }
  }
  return __cachedPackages;
}

#pragma mark -
#pragma mark Private methods to get local packages info

+ (NSDictionary *)_localPackageListInRawFormat
{
  NSDictionary *localPackageList = @{
    kATZPluginsKey: [NSMutableArray array],
    kATZColorSchemesKey: [NSMutableArray array],
    kATZProjectTemplatesKey: [NSMutableArray array],
    kATZFileTemplatesKey: [NSMutableArray array],
  };
  for (NSDictionary *package in [self _findLocalPackages]) {
    if (!package[kATZPackageCategoryKey]) {
      NSLog(@"[Alcatraz.ATZPackageUtils][ERROR] Package %@ hasn't specified its category. Skipping...", package);
      continue;
    }
    [localPackageList[package[kATZPackageCategoryKey]] addObject:package];
  }
  return localPackageList;
}

+ (NSArray *)_findLocalPackages
{
  NSString *pluginsDirectory = ATZPluginsSettings()[kATZSettingsPackageSourcesPathKey];
  if (!pluginsDirectory) {
    return nil;
  }

  NSFileManager *manager = [NSFileManager defaultManager];
  NSArray *contents = [manager contentsOfDirectoryAtPath:pluginsDirectory error:nil];
  NSMutableArray *directories = [NSMutableArray array];
  for (NSString *path in contents) {
    BOOL isDirectory = NO;
    NSString *fullpath = [pluginsDirectory stringByAppendingPathComponent:path];
    if ([manager fileExistsAtPath:fullpath isDirectory:&isDirectory] && isDirectory) {
      [directories addObject:fullpath];
    }
  }

  NSMutableArray *projects = [NSMutableArray array];
  for (NSString *pluginDir in directories) {
    NSArray *files = [manager contentsOfDirectoryAtPath:pluginDir error:nil];
    for (NSString *filePath in files) {
      if ([[filePath pathExtension] isEqualToString:kATZXcodeProjExtension]) {
        [projects addObject:[pluginDir stringByAppendingPathComponent:filePath]];
      }
    }
  }

  NSMutableArray *packages = [NSMutableArray array];
  for (NSString *projectPath in projects) {
    NSDictionary *packageInfo = [self _packageAtPath:projectPath];
    if (packageInfo) {
      [packages addObject:packageInfo];
    }
  }

  return packages;
}

+ (NSDictionary *)_packageAtPath:(NSString *)projectPath
{
  NSString *pluginName = [ATZPbxprojParser xcpluginNameFromPbxproj:[projectPath stringByAppendingPathComponent:KATZProjectPbxprojFileName]];

  if (!pluginName) {
    return nil;
  }

  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  dictionary[kATZPackageNameKey] = pluginName;

  NSString *commonPath = [ATZPluginsSettings()[kATZSettingsPackageSourcesPathKey] commonPrefixWithString:projectPath options:0];
  NSString *projectRelativePath = [projectPath substringFromIndex:[commonPath length]];
  dictionary[kATZPackageLocalRelativePathKey] = [projectRelativePath stringByDeletingLastPathComponent];

  // read plist file
  NSFileManager *manager = [NSFileManager defaultManager];
  NSDirectoryEnumerator *dirEnum = [manager enumeratorAtPath:[projectPath stringByDeletingLastPathComponent]];
  NSString *file;
  NSString *infoPlistFile = [[[projectPath lastPathComponent] stringByDeletingPathExtension] stringByAppendingString:@"-Info.plist"];
  while ((file = [dirEnum nextObject])) {
    if ([file hasSuffix:infoPlistFile]) {
      NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[[projectPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:file]];
      if (info[kATZPackageVersionKey]) {
        dictionary[kATZPackageVersionKey] = info[kATZPackageVersionKey];
      }
      if (info[kATZPackageDescriptionKey]) {
        dictionary[@"description"] = info[kATZPackageDescriptionKey];
      }
      if (info[kATZPackageCategoryKey]) {
        dictionary[kATZPackageCategoryKey] = info[kATZPackageCategoryKey];
      }
      break;
    }
  }

  return dictionary;
}

#pragma mark -
#pragma mark User Notification Methods

+ (void)_becomeUserNotificationCenterDelegate
{
  [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:[self shared]];
}

+ (void)postUserNotificationForInstalledPackage:(ATZPackage *)package
{
  [self _becomeUserNotificationCenterDelegate];

  NSUserNotification *notification = [NSUserNotification new];
  notification.title = [NSString stringWithFormat:@"%@ installed", package.type];
  NSString *restartText = package.requiresRestart ? @" Please restart Xcode to use it." : @"";
  notification.informativeText = [NSString stringWithFormat:@"%@ was installed successfully!\n%@", package.name, restartText];

  [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

+ (void)postUserNotificationForUpdatedPackage:(ATZPackage *)package
{
  [self _becomeUserNotificationCenterDelegate];

  NSUserNotification *notification = [NSUserNotification new];
  notification.title = [NSString stringWithFormat:@"%@ updated", package.type];
  NSString *restartText = package.requiresRestart ? @"Please restart Xcode to use it." : @"";
  notification.informativeText = [NSString stringWithFormat:@"%@ was successfully updated!\n%@", package.name, restartText];

  [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

+ (void)postUserNotificationForAddedPackages:(NSSet *)packages
{
  [self _becomeUserNotificationCenterDelegate];

  NSUserNotification *notification = [NSUserNotification new];
  notification.title = [NSString stringWithFormat:@"New Packages Added"];
  if ([packages count] == 1) {
    notification.informativeText = [NSString stringWithFormat:@"Package %@ is now available.\nOpen Package Manager to install it.", [packages anyObject]];
  } else {
    notification.informativeText = [NSString stringWithFormat:@"%lu new packages are available!\nOpen Package Manager to install.", (unsigned long)[packages count]];
  }

  [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
  [[Alcatraz sharedPlugin] checkForCMDLineToolsAndOpenWindow];
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
  return YES;
}

@end
