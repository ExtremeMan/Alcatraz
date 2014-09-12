NSString *ATZPluginsDataDirectoryPath();

NSString *ATZPluginsInstallPath();

NSDictionary *ATZPluginsSettings();

void ATZPluginsUpdateSettingsWithDictionary(NSDictionary *settings);

void ATZPluginsUpdateSettingsValueForKey(NSString *value, NSString *key);
