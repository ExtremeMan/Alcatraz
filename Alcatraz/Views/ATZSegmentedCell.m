//
//  ATZSegmentedCell.m
//  Alcatraz
//
//  Created by Jurre Stender on 25/11/13.
//  Copyright (c) 2013 supermar.in. All rights reserved.
//

#import "ATZSegmentedCell.h"
#import "NSColor+Alcatraz.h"
#import "NSImage+Alcatraz.h"
#import "Alcatraz.h"
#import "ATZColorScheme.h"
#import "ATZPlugin.h"
#import "ATZTemplate.h"

static NSString *const ALL_ITEMS_TITLE = @"All";
static NSString *const NEW_ITEMS_TITLE = @"New";
static NSString *const INSTALLED_ITEMS_TITLE = @"Installed";

@implementation ATZSegmentedCell

- (void)drawSegment:(NSInteger)segment inFrame:(NSRect)frame withView:(NSView *)controlView {
    double offset = 0;
    for (int i=0; i<segment; i++) {
        offset += [self widthForSegment:i];
    }

    CGRect segmentFrame = CGRectIntegral(CGRectMake(offset,
                                                    frame.origin.y,
                                                    frame.size.width,
                                                    frame.size.height));
    if (ATZFilterSegmentAll == segment) {
        [self drawAllItemsSegmentInFrame:segmentFrame];
    } else if (ATZFilterSegmentNew == segment) {
        [self drawNewItemsSegmentInFrame:segmentFrame];
    } else if (ATZFilterSegmentInstalled == segment) {
        [self drawInstalledItemsSegmentInFrame:segmentFrame];
    } else {
        NSImage *icon = [self iconForSegment:segment];
        NSColor * color = [self colorForSegmentAtIndex:segment];
        // we're drawing in a flipped context
        segmentFrame.origin.y = -(frame.size.height - icon.size.height)/2;
        segmentFrame.size = icon.size;
        [NSImage drawImage:icon withColor:color inFrame:segmentFrame flipVertically:YES];
    }
}

- (NSColor *)colorForSegmentAtIndex:(NSInteger)segmentIndex
{
    if (self.selectedSegment == segmentIndex) {
        return [NSColor alcatrazBlueColor];
    } else {
        return [NSColor colorWithDeviceWhite:0.1f alpha:1.0f];
    }
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    for (NSInteger segment = 0; segment < self.segmentCount; segment++) {
        [self drawSegment:segment inFrame:cellFrame withView:controlView];
    }
}

#pragma mark - Private

- (NSDictionary *)segmentIconMapping {
    static NSDictionary *segmentIconMapping;
    if (!segmentIconMapping) {
        segmentIconMapping = @{@(ATZFilterSegmentColorSchemes): COLOR_SCHEME_ICON_NAME,
                               @(ATZFilterSegmentPlugins): PLUGIN_ICON_NAME,
                               @(ATZFilterSegmentTemplates): TEMPLATE_ICON_NAME};
    }
    return segmentIconMapping;
}

- (NSImage *)iconForSegment:(ATZFilterSegment)segment {
    return [[[Alcatraz sharedPlugin] bundle] imageForResource:[self segmentIconMapping][@(segment)]];
}

- (void)drawString:(NSAttributedString *)string inRect:(CGRect)frame
{
    frame.origin.y = (frame.size.height - string.size.height) - 3;
    [string drawInRect:frame];
}

- (void)drawAllItemsSegmentInFrame:(CGRect)frame {
    BOOL selected = self.selectedSegment == ATZFilterSegmentAll;
    NSAttributedString *title = selected ? [self allItemsLabelSelected] : [self allItemsLabelUnselected];
    [self drawString:title inRect:frame];
}

- (void)drawNewItemsSegmentInFrame:(CGRect)frame {
    BOOL selected = self.selectedSegment == ATZFilterSegmentNew;
    NSAttributedString *title = selected ? [self newItemsLabelSelected] : [self newItemsLabelUnselected];
    [self drawString:title inRect:frame];
}

- (void)drawInstalledItemsSegmentInFrame:(CGRect)frame {
    BOOL selected = self.selectedSegment == ATZFilterSegmentInstalled;
    NSAttributedString *title = selected ? [self installedItemsLabelSelected] : [self installedItemsLabelUnselected];
    [self drawString:title inRect:frame];
}

#pragma mark -
#pragma mark Working with labels

- (NSFont *)titleFont
{
  static NSFont *titleFont;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    titleFont = [NSFont systemFontOfSize:13.0f];
  });
  return titleFont;
}

- (NSColor *)titleColor:(BOOL)selected
{
  static NSColor *selectedColor;
  static NSColor *unselectedColor;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    selectedColor = [NSColor colorWithDeviceRed:0.139 green:0.449 blue:0.867 alpha:1.000];
    unselectedColor = [NSColor blackColor];
  });
  return selected ? selectedColor : unselectedColor;
}

- (NSDictionary *)attributesForTitleStateSelected:(BOOL)selected
{
  return @{NSFontAttributeName: [self titleFont],
           NSForegroundColorAttributeName: [self titleColor:selected]};
}

- (NSAttributedString *)allItemsLabelUnselected {
  static NSAttributedString *labelUnselected;
  if (!labelUnselected) {
    labelUnselected = [[NSAttributedString alloc] initWithString:ALL_ITEMS_TITLE
                                                      attributes:[self attributesForTitleStateSelected:NO]];
  }
  return labelUnselected;
}

- (NSAttributedString *)allItemsLabelSelected {
  static NSAttributedString *labelSelected;
  if (!labelSelected) {
    labelSelected = [[NSAttributedString alloc] initWithString:ALL_ITEMS_TITLE
                                                    attributes:[self attributesForTitleStateSelected:YES]];
  }
  return labelSelected;
}

- (NSAttributedString *)newItemsLabelUnselected {
  static NSAttributedString *labelUnselected;
  if (!labelUnselected) {
    labelUnselected = [[NSAttributedString alloc] initWithString:NEW_ITEMS_TITLE
                                                      attributes:[self attributesForTitleStateSelected:NO]];
  }
  return labelUnselected;
}

- (NSAttributedString *)newItemsLabelSelected {
  static NSAttributedString *labelSelected;
  if (!labelSelected) {
    labelSelected = [[NSAttributedString alloc] initWithString:NEW_ITEMS_TITLE
                                                    attributes:[self attributesForTitleStateSelected:YES]];
  }
  return labelSelected;
}

- (NSAttributedString *)installedItemsLabelUnselected {
  static NSAttributedString *labelUnselected;
  if (!labelUnselected) {
    labelUnselected = [[NSAttributedString alloc] initWithString:INSTALLED_ITEMS_TITLE
                                                      attributes:[self attributesForTitleStateSelected:NO]];
  }
  return labelUnselected;
}

- (NSAttributedString *)installedItemsLabelSelected {
  static NSAttributedString *labelSelected;
  if (!labelSelected) {
    labelSelected = [[NSAttributedString alloc] initWithString:INSTALLED_ITEMS_TITLE
                                                    attributes:[self attributesForTitleStateSelected:YES]];
  }
  return labelSelected;
}

@end
