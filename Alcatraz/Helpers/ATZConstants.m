#import "ATZConstants.h"

NSString *const kATZPluginsRepoPath = @"https://raw.github.com/supermarin/alcatraz-packages/master/packages.json";

NSString *const kATZPluginsInstallDirectory = @"Library/Application Support/Developer/Shared/Xcode/Plug-ins";
NSString *const kATZPluginsDataDirectory = @"Library/Application Support/Alcatraz";

NSString *const kATZCachedPackagesFile = @"packages.plist";
NSString *const kATZCachedRemotePackagesListKey = @"remote";
NSString *const kATZCachedLocalPackagesListKey = @"local";
NSString *const kATZSettingsFile = @"settings.plist";
NSString *const kATZSettingsPackageSourcesPathKey = @"ATZPackageSourcesPath";;
NSString *const kATZSettingsPackagesToBeInstalledKey = @"ATZPackagesToBeInstalled";

NSString *const kATZColorSchemesKey = @"color_schemes";
NSString *const kATZProjectTemplatesKey = @"project_templates";
NSString *const kATZFileTemplatesKey = @"file_templates";
NSString *const kATZPluginsKey = @"plugins";

NSString *const kATZPackageNameKey = @"name";
NSString *const kATZPackageVersionKey = @"CFBundleShortVersionString";
NSString *const kATZPackageLocalRelativePathKey = @"ATZPackageLocalPath";
NSString *const kATZPackageDescriptionKey = @"ATZPackageDescription";
NSString *const kATZPackageCategoryKey = @"ATZPackageCategory";
NSString *const kATZPlugInCompatibilityUUIDsKey = @"DVTPlugInCompatibilityUUIDs";

NSString *const kATZLocalPackageScreenshotName = @"ATZPluginScreenshot.png";

NSString *const kATZListOfPackagesWasUpdatedNotification = @"ATZListOfPackagesWasUpdatedNotification";
NSString *const kATZPackageWasInstalledNotification = @"ATZPackageWasInstalledNotification";
NSString *const kATZPackageWasUpdatedNotification = @"ATZPackageWasUpdatedNotification";

NSString *const kATZXcodeProjExtension = @"xcodeproj";
NSString *const KATZProjectPbxprojFileName = @"project.pbxproj";
