// PluginWindowController.m
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

#import "ATZPluginWindowController.h"

#import "ATZConstants.h"
#import "ATZDownloader.h"
#import "ATZPackageFactory.h"
#import "ATZPackageUtils.h"
#import "ATZUtils.h"

#import "ATZDetailItemButton.h"
#import "ATZPackageTableCellView.h"
#import "ATZVersionLabel.h"

#import "ATZPlugin.h"
#import "ATZColorScheme.h"
#import "ATZTemplate.h"

#import "ATZShell.h"
#import "ATZSegmentedCell.h"

#import "ATZRadialProgressControl.h"

typedef enum : NSInteger {
  ATZRemotePackageTab = 0,
  ATZLocalPackageTab = 1,
} ATZPackageTabIndex;

static NSString *const ALL_ITEMS_ID = @"AllItemsToolbarItem";
static NSString *const CLASS_PREDICATE_FORMAT = @"(self isKindOfClass: %@)";
static NSString *const SEARCH_PREDICATE_FORMAT = @"(name contains[cd] %@ OR description contains[cd] %@)";
static NSString *const SEARCH_AND_CLASS_PREDICATE_FORMAT = @"(name contains[cd] %@ OR description contains[cd] %@) AND (self isKindOfClass: %@)";

@interface ATZPluginWindowController () <NSTabViewDelegate, NSTableViewDelegate, NSControlTextEditingDelegate, NSPathControlDelegate>
@property (assign) IBOutlet NSPanel *previewPanel;
@property (assign) IBOutlet NSImageView *previewImageView;
@property (assign) IBOutlet NSSearchField *searchField;

@property (assign) IBOutlet NSTabView *tabView;
@property (assign) IBOutlet NSTableView *remoteTableView;
@property (assign) IBOutlet NSTableView *localTableView;

@property (assign) IBOutlet NSPathControl *pathControl;
@property (assign) IBOutlet NSPathCell *pathCell;

- (IBAction)checkboxPressed:(NSButton *)sender;
- (IBAction)openPackageWebsitePressed:(NSButton *)sender;
- (IBAction)displayScreenshotPressed:(NSButton *)sender;
- (IBAction)segmentedControlPressed:(id)sender;
- (IBAction)localPackagesLocationChanged:(id)sender;
@end

@interface ATZPluginWindowController ()
@property (nonatomic, retain) NSArray *remotePackages;
@property (nonatomic, retain) NSArray *localPackages;
@property (nonatomic, retain) NSPredicate *filterPredicate;

@property (nonatomic, assign) Class selectedPackageClass;
@property (nonatomic, assign) NSView *hoverButtonsContainer;
@end

@implementation ATZPluginWindowController

- (id)init {
    @throw [NSException exceptionWithName:@"There's a better initializer" reason:@"Use -initWithNibName:inBundle:" userInfo:nil];
}

- (id)initWithBundle:(NSBundle *)bundle {
    if (self = [super initWithWindowNibName:@"PluginWindow"]) {
        [[self.window toolbar] setSelectedItemIdentifier:ALL_ITEMS_ID];
        
        [self addVersionToWindow];

        self.localPackages = [ATZPackageUtils localPackages];
        self.remotePackages = [ATZPackageUtils remotePackages];

        _filterPredicate = [NSPredicate predicateWithValue:YES];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(listOfPackagesWasUpdated:)
                                                     name:kATZListOfPackagesWasUpdatedNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(packageWasUpdated:)
                                                     name:kATZPackageWasUpdatedNotification
                                                   object:nil];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(packageWasInstalled:)
                                                     name:kATZPackageWasInstalledNotification
                                                   object:nil];

    }
    return self;
}

- (void)windowDidLoad
{
  [super windowDidLoad];

  NSString *packagesPath = ATZPluginsSettings()[kATZSettingsPackageSourcesPathKey];
  if (packagesPath) {
    [_pathControl setURL:[NSURL fileURLWithPath:packagesPath]];
  }
  _pathCell.placeholderAttributedString = [[NSAttributedString alloc] initWithString:@"Choose directory with local packages..."
                                                                          attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:9],
                                                                                       NSForegroundColorAttributeName: [NSColor blackColor]}];

  [[self currentTableView] reloadData];
}

#pragma mark -
#pragma mark Helpers

- (ATZPackageTabIndex)selectedTabIndex
{
  return [_tabView indexOfTabViewItem:[_tabView selectedTabViewItem]];
}

- (NSTableView *)tableViewForTabIndex:(ATZPackageTabIndex)tabIndex
{
  switch (tabIndex) {
    case ATZRemotePackageTab:
      return _remoteTableView;

    case ATZLocalPackageTab:
      return _localTableView;
  }
}

- (NSTableView *)currentTableView
{
  return [self tableViewForTabIndex:[self selectedTabIndex]];
}

- (NSArray *)currentPackageArray
{
  switch ([self selectedTabIndex]) {
    case ATZRemotePackageTab:
      return _remotePackages;

    case ATZLocalPackageTab:
      return _localPackages;
  }
}

#pragma mark -
#pragma mark NSTabView Delegate

- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
  [[self tableViewForTabIndex:[_tabView indexOfTabViewItem:tabViewItem]] reloadData];
}

#pragma mark -
#pragma mark Path Control Delegate

- (void)pathControl:(NSPathControl *)pathControl willDisplayOpenPanel:(NSOpenPanel *)openPanel
{
  [openPanel setAllowsMultipleSelection:NO];
  [openPanel setCanChooseDirectories:YES];
  [openPanel setCanChooseFiles:NO];
  [openPanel setResolvesAliases:YES];
  [openPanel setTitle:@"Choose a directory with packages"];
  [openPanel setPrompt:@"Choose"];
}

- (IBAction)localPackagesLocationChanged:(NSPathControl *)sender
{
  // find the path component selected
  NSPathComponentCell *component = [sender clickedPathComponentCell];
  NSURL *url = [component URL];

  // update displayed path
  [sender setURL:url];

  // save path to settings file
  ATZPluginsUpdateSettingsValueForKey([url path], kATZSettingsPackageSourcesPathKey);
}

#pragma mark - Bindings

- (IBAction)checkboxPressed:(ATZRadialProgressControl *)control {
    ATZPackage *package = [[self currentPackageArray] filteredArrayUsingPredicate:self.filterPredicate][[[self currentTableView] rowForView:control]];
    
    if (package.isInstalled)
        [self removePackage:package andUpdateControl:control];
    else
        [self installPackage:package andUpdateControl:control];
}

- (NSDictionary *)segmentClassMapping {
    static NSDictionary *segmentClassMapping;
    if (!segmentClassMapping) {
       segmentClassMapping = @{@(ATZFilterSegmentColorSchemes): [ATZColorScheme class],
            @(ATZFilterSegmentPlugins): [ATZPlugin class],
            @(ATZFilterSegmentTemplates): [ATZTemplate class]};
    }
    return segmentClassMapping;
}

- (IBAction)segmentedControlPressed:(id)sender {
    NSInteger selectedSegment = [sender selectedSegment];
    self.selectedPackageClass = [self segmentClassMapping][@(selectedSegment)];
    [self updatePredicate];
}

- (IBAction)displayScreenshotPressed:(NSButton *)sender {
    ATZPackage *package = [[self currentPackageArray] filteredArrayUsingPredicate:self.filterPredicate][[[self currentTableView] rowForView:sender]];
    
    [self displayScreenshot:package.screenshotPath withTitle:package.name];
}

- (IBAction)openPackageWebsitePressed:(NSButton *)sender {
    ATZPackage *package = [[self currentPackageArray] filteredArrayUsingPredicate:self.filterPredicate][[[self currentTableView] rowForView:sender]];

    [self openWebsite:package.website];
}

- (void)controlTextDidChange:(NSNotification *)note {
    [self updatePredicate];
}

- (void)keyDown:(NSEvent *)event {
    if (hasPressedCommandF(event))
        [self.window makeFirstResponder:self.searchField];
    else
        [super keyDown:event];
}


#pragma mark - Private

- (void)removePackage:(ATZPackage *)package andUpdateControl:(ATZRadialProgressControl *)control {
    [control setProgress:0 animated:YES];
    [package removeWithCompletion:^(NSError *failure) {}];
}

- (void)installPackage:(ATZPackage *)package andUpdateControl:(ATZRadialProgressControl *)control {
    [package installWithProgress:^(NSString *progressMessage, CGFloat progress) { //TODO: see if we can get rid of NSString progress
        [control setProgress:progress animated:YES];
    }
                      completion:^(NSError *failure) {
        [control setProgress:failure ? 0 : 1 animated:YES];
        if (package.requiresRestart) {
          [ATZPackageUtils postUserNotificationForInstalledPackage:package];
        }
    }];
}

BOOL hasPressedCommandF(NSEvent *event) {
    return ([event modifierFlags] & NSCommandKeyMask) && [[event characters] characterAtIndex:0] == 'f';
}

- (void)updatePredicate {
    // TODO: refactor, use compound predicates.

    NSString *searchText = self.searchField.stringValue;
    // filter by type and search field text
    if (self.selectedPackageClass && searchText.length > 0) {
        self.filterPredicate = [NSPredicate predicateWithFormat:SEARCH_AND_CLASS_PREDICATE_FORMAT, searchText, searchText, self.selectedPackageClass];
        
    // filter by type
    } else if (self.selectedPackageClass) {
        self.filterPredicate = [NSPredicate predicateWithFormat:CLASS_PREDICATE_FORMAT, self.selectedPackageClass];
        
    // filter by search field text
    } else if (searchText.length > 0) {
        self.filterPredicate = [NSPredicate predicateWithFormat:SEARCH_PREDICATE_FORMAT, searchText, searchText];
        
    // show all
    } else {
        self.filterPredicate = [NSPredicate predicateWithValue:YES];
    }
}

- (void)openWebsite:(NSString *)address {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:address]];
}

- (void)displayScreenshot:(NSString *)screenshotPath withTitle:(NSString *)title {
    
    [self.previewPanel.animator setAlphaValue:0.f];
    self.previewPanel.title = title;
    [self retrieveImageViewForScreenshot:screenshotPath
                                progress:^(CGFloat progress) {

    }
                              completion:^(NSImage *image) {
        
        self.previewImageView.image = image;
        [NSAnimationContext beginGrouping];
        
        [self.previewImageView.animator setFrame:(CGRect){ .origin = CGPointMake(0, 0), .size = image.size }];
        CGRect previewPanelFrame = (CGRect){.origin = self.previewPanel.frame.origin, .size = image.size};
        [self.previewPanel setFrame:previewPanelFrame display:NO animate:NO];
        [self.previewPanel.animator center];
        
        [NSAnimationContext endGrouping];
        
        [self.previewPanel makeKeyAndOrderFront:self];
        [self.previewPanel.animator setAlphaValue:1.f];
    }];
}

- (void)retrieveImageViewForScreenshot:(NSString *)screenshotPath progress:(void (^)(CGFloat))downloadProgress completion:(void (^)(NSImage *))completion {
    
    ATZDownloader *downloader = [ATZDownloader new];
    [downloader downloadFileFromPath:screenshotPath
                            progress:^(CGFloat progress) {
                                downloadProgress(progress);
                            }
                          completion:^(NSData *responseData, NSError *error) {
                              
                              NSImage *image = [[NSImage alloc] initWithData:responseData];
                              completion(image);
                          }];
    
}

- (void)addVersionToWindow {
    NSView *windowFrameView = [[self.window contentView] superview];
    NSTextField *label = [[ATZVersionLabel alloc] initWithFrame:(NSRect){
        .origin.x = self.window.frame.size.width - 46,
        .origin.y = windowFrameView.bounds.size.height - 26,
        .size.width = 40,
        .size.height = 20
    }];
    [windowFrameView addSubview:label];
}

#pragma mark -
#pragma mark Notification Selectors

- (void)listOfPackagesWasUpdated:(NSNotification *)notification
{
  self.localPackages = [ATZPackageUtils localPackages];
  self.remotePackages = [ATZPackageUtils remotePackages];
  [[self currentTableView] reloadData];
}

- (void)packageWasUpdated:(NSNotification *)notification
{
  [self listOfPackagesWasUpdated:notification];
}

- (void)packageWasInstalled:(NSNotification *)notification
{
  [self listOfPackagesWasUpdated:notification];
}

@end
