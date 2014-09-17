// Plugin.m
//
// Copyright (c) 2013 Marin Usalj | supermar.in
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "ATZPlugin.h"

#import "ATZConstants.h"
#import "ATZPluginInstaller.h"
#import "ATZUtils.h"

static NSString *const PLUGIN = @"Plugin";
static NSString *const XCPLUGIN = @".xcplugin";

@implementation ATZPlugin
@synthesize requiresRestart;

- (instancetype)initWithDictionary:(NSDictionary *)dictionary
{
  self = [super initWithDictionary:dictionary];
  if (self) {
    if (dictionary[kATZPackageVersionKey]) {
      _version = dictionary[kATZPackageVersionKey];
    }
  }
  return self;
}

- (ATZInstaller *)installer {
    return [ATZPluginInstaller sharedInstaller];
}

- (NSString *)type {
    return PLUGIN;
}

- (NSString *)extension {
    return XCPLUGIN;
}

- (NSString *)iconName {
    return PLUGIN_ICON_NAME;
}

- (NSString *)version
{
  if (_version) {
    return _version;
  }

  _version = [self _availablePackagePlist][kATZPackageVersionKey];
  return _version;
}

- (NSString *)installedVersion
{
  if (_installedVersion || ![self isInstalled]) {
    return _installedVersion;
  }

  _installedVersion = [self _installedPackagePlist][kATZPackageVersionKey];
  return _installedVersion;
}

- (void)reloadInstalledVersion
{
  _installedVersion = nil;
  [self installedVersion];
}

- (BOOL)isOutdated
{
  return ([self isInstalled]) && ([self.installedVersion compare:self.version] == NSOrderedAscending);
}

- (NSArray *)supportedXcodeUDIDs
{
  if (_supportedXcodeUDIDs) {
    return _supportedXcodeUDIDs;
  }

  if (![self localPath] && [self isInstalled]) {
    _supportedXcodeUDIDs = [self _installedPackagePlist][kATZPlugInCompatibilityUUIDsKey];
  } else if ([self localPath]) {
    _supportedXcodeUDIDs = [self _availablePackagePlist][kATZPlugInCompatibilityUUIDsKey];
  }

  return _supportedXcodeUDIDs;
}

#pragma mark -
#pragma mark - Helpers

- (NSDictionary *)_installedPackagePlist
{
  NSString *pluginInstallPath = [[ATZPluginsInstallPath() stringByAppendingPathComponent:self.name] stringByAppendingPathExtension:@"xcplugin"];
  NSString *pluginInfoPlist = [pluginInstallPath stringByAppendingPathComponent:@"Contents/Info.plist"];
  return [NSDictionary dictionaryWithContentsOfFile:pluginInfoPlist];
}

- (NSDictionary *)_availablePackagePlist
{
  NSString *projectSourcePath = self.localPath;
  if (!projectSourcePath) {
    projectSourcePath = [self.installer pathForDownloadedPackage:self];
  }

  NSFileManager *manager = [NSFileManager defaultManager];
  NSDirectoryEnumerator *dirEnum = [manager enumeratorAtPath:projectSourcePath];
  NSString *file;
  NSString *infoPlistFile = [self.name stringByAppendingString:@"-Info.plist"];
  while ((file = [dirEnum nextObject])) {
    if ([file hasSuffix:infoPlistFile]) {
      return [NSDictionary dictionaryWithContentsOfFile:[projectSourcePath stringByAppendingPathComponent:file]];
    }
  }
  return nil;
}

@end
