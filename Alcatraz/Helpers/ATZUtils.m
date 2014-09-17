#import "ATZUtils.h"

#include <errno.h>
#include <libproc.h>

#import "ATZConstants.h"

/**
 _CFProcessPath is method in CFPlatform that returns a string representing 
 the path to the executable that is running.  The implementations can be found here:
 http://opensource.apple.com/source/CF/CF-744.18/CFPlatform.c
 */
char *_CFProcessPath(void);

static NSMutableDictionary *__settings;

#pragma mark -
#pragma mark Private Helpers Definitions

NSString *ATZPluginsSettingsPath();
void ATZSavePluginsSettings();

#pragma mark -
#pragma mark Public Methods

NSString *ATZPluginsDataDirectoryPath()
{
  return [NSHomeDirectory() stringByAppendingPathComponent:kATZPluginsDataDirectory];
}

NSString *ATZPluginsInstallPath()
{
  return [NSHomeDirectory() stringByAppendingPathComponent:kATZPluginsInstallDirectory];
}

NSDictionary *ATZPluginsSettings()
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *path = ATZPluginsSettingsPath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
      NSLog(@"[Alcatraz.ATZUtils][ERROR] ATZPlugins settings file wasn't found");
      __settings = [@{} mutableCopy];
    } else {
      __settings = [NSMutableDictionary dictionaryWithContentsOfFile:path];
      NSLog(@"[Alcatraz.ATZUtils][INFO] settings: %@", __settings);
    }
  });
  return [__settings copy];
}

void ATZPluginsUpdateSettingsWithDictionary(NSDictionary *settings)
{
  if (!__settings) {
    ATZPluginsSettings();
  }

  __settings = [settings mutableCopy];
  ATZSavePluginsSettings();
}

void ATZPluginsUpdateSettingsValueForKey(NSString *value, NSString *key)
{
  if (!__settings) {
    ATZPluginsSettings();
  }

  [__settings setValue:value forKey:key];
  ATZSavePluginsSettings();
}

NSString *ATZCurrentXcodePath()
{
  static NSString *xcodePath;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    xcodePath = [NSString stringWithUTF8String:_CFProcessPath()];
  });
  return xcodePath;
}

NSDictionary *ATZCurrentXcodePlist()
{
  static NSDictionary *dictionary;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *plistPath = [[ATZCurrentXcodePath() stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
    plistPath = [plistPath stringByAppendingPathComponent:@"Info.plist"];
    dictionary = [NSDictionary dictionaryWithContentsOfFile:plistPath];
  });
  return dictionary;
}

NSString *ATZCurrentXcodeUDID()
{
  static NSString *xcodeUDID;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    xcodeUDID = ATZCurrentXcodePlist()[@"DVTPlugInCompatibilityUUID"];
  });
  return xcodeUDID;
}

#pragma mark - 
#pragma mark Private Helpers

NSString *ATZPluginsSettingsPath()
{
  return [ATZPluginsDataDirectoryPath() stringByAppendingPathComponent:kATZSettingsFile];
}

void ATZSavePluginsSettings()
{
  [__settings writeToFile:ATZPluginsSettingsPath() atomically:YES];
}
