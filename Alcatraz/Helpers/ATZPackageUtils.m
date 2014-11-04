#import "ATZPackageUtils.h"

#import "Alcatraz.h"
#import "ATZConstants.h"
#import "ATZDownloader.h"
#import "ATZPackage.h"
#import "ATZPackageFactory.h"
#import "ATZPlugin.h"
#import "ATZPBXProjParser.h"
#import "ATZUtils.h"

static NSArray *__localPackages;
static NSArray *__remotePackages;

static NSMutableSet *__addedRemotePackageNames;
static NSMutableSet *__addedLocalPackageNames;

static NSDictionary *__cachedPackages;

static NSOperationQueue *__installationQueue;

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
  });
  return shared;
}

+ (void)initialize
{
  __installationQueue = [[NSOperationQueue alloc] init];
  __installationQueue.qualityOfService = NSQualityOfServiceBackground;
  __installationQueue.maxConcurrentOperationCount = 1;
  __installationQueue.name = @"Alcatraz Package Installation Queue";
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

+ (NSSet *)addedLocalPackages
{
  return __addedLocalPackageNames;
}

+ (NSSet *)addedRemotePackages
{
  return __addedRemotePackageNames;
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
      if (!__addedRemotePackageNames) {
        __addedRemotePackageNames = [NSMutableSet set];
      }
      NSArray *justAddedPackages = [self addedPackageNamesTo:packageList forCachedListKey:kATZCachedRemotePackagesListKey];
      [__addedRemotePackageNames addObjectsFromArray:justAddedPackages];
      if ([justAddedPackages count] && [[self cachedPackageLists][kATZCachedRemotePackagesListKey] count]) {
        [self postUserNotificationForAddedPackages:justAddedPackages];
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
  if (!__addedLocalPackageNames) {
    __addedLocalPackageNames = [NSMutableSet set];
  }
  NSArray *justAddedPackages = [self addedPackageNamesTo:localPackagesRaw forCachedListKey:kATZCachedLocalPackagesListKey];
  [__addedLocalPackageNames addObjectsFromArray:justAddedPackages];
  if ([justAddedPackages count]) {
    [self postUserNotificationForAddedPackages:justAddedPackages];
  }

  // cache package list
  [self cachePackageList:localPackagesRaw forCachedListKey:kATZCachedLocalPackagesListKey];
}

#pragma mark -
#pragma mark Methods to update packages

+ (void)updatePackages:(NSArray *)packages
{
  NSDictionary *packagesToBeInstalled = ATZPluginsSettings()[kATZSettingsPackagesToBeInstalledKey];
  NSArray *localPackagesToBeInstalled = [packagesToBeInstalled[kATZCachedLocalPackagesListKey] valueForKeyPath:@"name"];
  NSArray *remotePackagesToBeInstalled = [packagesToBeInstalled[kATZCachedRemotePackagesListKey] valueForKeyPath:@"name"];
  for (ATZPackage *package in packages) {
    if ([package isInstalled]) {
      [self enqueuePackageUpdate:package];
    } else {
      if (package.localPath && [localPackagesToBeInstalled containsObject:package.name]) {
        [self enqueuePackageInstallation:package];
      } else if (!package.localPath && [remotePackagesToBeInstalled containsObject:package.name]) {
        [self enqueuePackageInstallation:package];
      }
    }
  }
}

+ (void)enqueuePackageUpdate:(ATZPackage *)package
{
  if (!package.isInstalled) {
    return;
  }

  // update local packages only on Xcode start up
  if ([package isKindOfClass:[ATZPlugin class]] && [(ATZPlugin *)package localPath]) {
    if ([Alcatraz sharedPlugin]) {
      return;
    }
    // cache installed plugin version
    [(ATZPlugin *)package installedVersion];
  }

  NSOperation *updateOperation = [NSBlockOperation blockOperationWithBlock:^{
    CFRunLoopRef currentRunLoop = CFRunLoopGetCurrent();
    __block BOOL running = YES;
    [package updateWithProgress:^(NSString *progressMessage, CGFloat progress){}
                     completion:^(NSError *failure, BOOL updated) {
      if (failure) {
        NSLog(@"[Alcatraz][ATZPackageUtils] Package \"%@\" update failed with error: %@", package.name, failure);
      } else if (updated) {
        BOOL notifyUser = YES;
        if ([package isKindOfClass:[ATZPlugin class]]) {
          // we will notify user about local package update only when version was changed
          if ([(ATZPlugin *)package localPath]) {
            notifyUser = [(ATZPlugin *)package isOutdated];
          }
          [(ATZPlugin *)package reloadInstalledVersion];
        }
        if (notifyUser) {
          [[NSNotificationCenter defaultCenter] postNotificationName:kATZPackageWasUpdatedNotification object:package];
          [self postUserNotificationForUpdatedPackage:package];
        }
      }
      running = NO;
      CFRunLoopStop(currentRunLoop);
    }];

    while (running) {
      CFRunLoopRun();
    }
  }];
  updateOperation.queuePriority = NSOperationQueuePriorityVeryLow;
  [__installationQueue addOperation:updateOperation];
}

+ (void)enqueuePackageInstallation:(ATZPackage *)package
{
  NSOperation *updateOperation = [NSBlockOperation blockOperationWithBlock:^{
    CFRunLoopRef currentRunLoop = CFRunLoopGetCurrent();
    __block BOOL running = YES;
    [package installWithProgress:^(NSString *proggressMessage, CGFloat progress){}
                      completion:^(NSError *failure) {
      if (failure) {
        NSLog(@"[Alcatraz][ATZPackageUtils] Package \"%@\" installation failed with error: %@", package.name, failure);
      } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:kATZPackageWasInstalledNotification object:package];
        [self postUserNotificationForInstalledPackage:package];
      }
      running = NO;
      CFRunLoopStop(currentRunLoop);
    }];

    while (running) {
      CFRunLoopRun();
    }
  }];
  updateOperation.queuePriority = NSOperationQueuePriorityNormal;
  [__installationQueue addOperation:updateOperation];
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

+ (void)postUserNotificationForAddedPackages:(NSArray *)packages
{
  [self _becomeUserNotificationCenterDelegate];

  NSUserNotification *notification = [NSUserNotification new];
  notification.title = [NSString stringWithFormat:@"New Packages Added"];
  if ([packages count] == 1) {
    notification.informativeText = [NSString stringWithFormat:@"Package %@ is now available.\nOpen Package Manager to install it.", packages[0]];
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
