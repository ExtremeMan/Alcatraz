#import "ATZUtils.h"

#import "ATZConstants.h"

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
