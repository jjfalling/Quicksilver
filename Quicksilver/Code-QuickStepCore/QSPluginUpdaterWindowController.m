//
//  QSPluginUpdaterWindowController.m
//  Quicksilver
//
//  Created by Patrick Robertson on 26/01/2013.
//  Copyright 2013
//

#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#import "QSPluginUpdaterWindowController.h"


// The height of a cell when it's closed
#define kExpandHeight 47.0
// used to pad out the web view a little bit
#define kPaddingFactor 1.1

@implementation QSPluginUpdaterWindowController

@synthesize pluginTableView, pluginsArray;

- (id)initWithPlugins:(NSArray *)newPluginsArray
{
    self = [super initWithWindowNibName:@"QSPluginUpdater"];
    if (self) {
        pluginsArray = [newPluginsArray retain];
        // all plugins are checked to install by default
        numberOfPluginsToInstall = [pluginsArray count];
        pluginsToInstall = nil;
    }
    return self;
}

-(void)windowDidLoad {
    // set the window height to its initial height (all changes boxes are closed)
    [self setWindowHeight:0 animate:NO];
}

-(void)setWindowHeight:(CGFloat)aHeight animate:(BOOL)animate {
    NSRect frame = [[self window] frame];
    CGFloat originy = frame.origin.y;

    // Values for aHeight: -ive indicates shrinkage, +ive indicates expand. 0 indicates use initial height
    if (aHeight == 0) {
        // 121 is the 'extra' height of the window
        aHeight = [pluginsArray count]*kExpandHeight+121;
    } else {
        originy -= aHeight;
        aHeight = frame.size.height + aHeight;
    }

    [[self window] setFrame:NSMakeRect(frame.origin.x, originy, frame.size.width,aHeight) display:YES animate:animate];
}

- (void)dealloc {
    [pluginsArray release]; pluginsArray = nil;
    [pluginsToInstall release]; pluginsToInstall = nil;
    [super dealloc];
}

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return [pluginsArray count];
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([[tableColumn identifier] isEqualToString:@"PluginColumn"]) {
        QSPluginUpdateTableCellView *cellView = [tableView makeViewWithIdentifier:@"PluginsView" owner:self];
        // set up the plugin view and load the html
        [cellView setOptions:[pluginsArray objectAtIndex:row]];
        return cellView;
    }
    // checkbox column. Nothing to setup
    return [tableView makeViewWithIdentifier:@"Checkbox" owner:self];
}

- (NSArray *)showModal {
    [NSApp runModalForWindow:[self window]];
    // return an immutable representation
    return [[pluginsToInstall copy] autorelease];
}

-(IBAction)cancel:(id)sender {
    [self close];
    [NSApp stopModal];
}

-(IBAction)install:(id)sender {
    [self close];
    pluginsToInstall = [[NSMutableArray arrayWithCapacity:numberOfPluginsToInstall] retain];
    // generate an array of plugin IDs to install
    [pluginsArray enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
        if ([obj objectForKey:@"shouldInstall"] == nil || [[obj objectForKey:@"shouldInstall"] integerValue] == NSOnState) {
            [pluginsToInstall addObject:[(QSPlugIn *)[obj objectForKey:@"plugin"] identifier]];
        }
    }];
    [NSApp stopModal];
}

/* The height of the row is based on whether or not the HTML changes view is showing.
 The value is stored in the plugins dictionary in pluginsArray (and set in -[QSPluginUpdateTableCellView updateHeight])
 */
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
    NSNumber *height = [[pluginsArray objectAtIndex:row] objectForKey:@"cellHeight"];
    if (height == nil) {
        return 45;
    }
    return [height doubleValue];
}

// Calls the NSTableView equivalent, converting a given cell view into a its row number in the table
-(void)noteHeightOfRowChanged:(QSPluginUpdateTableCellView *)cell {
    [pluginTableView noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndex:[pluginTableView rowForView:cell]]];
}

// setter for adding details to a given plugin's dict (in pluginsArray).
// Used to set the 'cellHeight' key
-(void)setPluginView:(QSPluginUpdateTableCellView *)view details:(id)details forKey:(NSString *)key {
    NSMutableDictionary *pluginDict = [pluginsArray objectAtIndex:[pluginTableView rowForView:view]];
    [pluginDict setObject:details forKey:key];
}

-(IBAction)toggleInstallPlugin:(NSButton *)sender {
    NSInteger row = [pluginTableView rowForView:sender];
    [[pluginsArray objectAtIndex:row] setObject:[NSNumber numberWithInteger:[sender state]] forKey:@"shouldInstall"];
    numberOfPluginsToInstall = numberOfPluginsToInstall + ([sender state] == NSOffState ? -1 : 1);
    
    // disable the install button if no plugins are checked to install
    [installButton setEnabled:numberOfPluginsToInstall > 0];

}

@end

@implementation QSPluginUpdateTableCellView

@synthesize webView, pluginDetails, installedDetails;

- (void)setOptions:(NSDictionary *)options {
    
    _changesAreShowing = NO;
    [webView setFrameLoadDelegate:self];
    [[[webView mainFrame] frameView] setAllowsScrolling:NO];
    [webView setAlphaValue:_changesAreShowing ? 0 : 1];
    [webView setDrawsBackground:NO];
    
    static NSString *css = nil;
    if (css == nil) {
        // CSS for making the web view blend in. !!-Not valid HTML (no <head>,<body>)
        css = [@"<style>body {margin:0px;padding:0px;font-size:11px;font-family:\"lucida grande\";}ul {-webkit-padding-start:16px;list-style-type:square;margin:0px}</style>" retain];
    }
    NSString *name = [options objectForKey:@"name"];
    QSPlugIn *thisPlugin = [options objectForKey:@"plugin"];
    if (!name) {
        name = [NSString stringWithFormat:@"%@ %@",[thisPlugin name],[thisPlugin latestVersion]];
    }
    self.installedDetails.stringValue = [NSString stringWithFormat:NSLocalizedString(@"(Installed: %@)", @"details of the installed plugin version (that is being updated"), [thisPlugin installedVersion]];
    [iconView setImage:[thisPlugin icon]];
    self.pluginDetails.stringValue = name;
    WebFrame *wf = self.webView.mainFrame;
    
    [wf loadHTMLString:[NSString stringWithFormat:@"%@%@",css,[thisPlugin releaseNotes]] baseURL:nil];
}

// gets the height of the HTML in the webFrame, once it has loaded, to set the required height of the cell
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)webFrame {
    //get the rect for the rendered frame
    NSRect webFrameRect = [[[webFrame frameView] documentView] frame];
    //get the rect of the current webview
    NSRect webViewRect = [self.webView frame];
    
    //calculate the new frame
    NSRect newWebViewRect = NSMakeRect(webViewRect.origin.x,
                                       webViewRect.origin.y - NSHeight(webFrameRect),
                                       NSWidth(webViewRect),
                                       NSHeight(webFrameRect)*kPaddingFactor);
    //set the frame
    [self.webView setFrame:newWebViewRect];
    webViewHeight = NSHeight(newWebViewRect)*kPaddingFactor;
}


-(IBAction)toggleChanges:(id)sender {
    _changesAreShowing = !_changesAreShowing;
    [wc setWindowHeight:ceil(webViewHeight)*(_changesAreShowing ? 1 : -1) animate:YES];
    [self.webView setAlphaValue:1.0];
    [[self.webView animator] setAlphaValue:_changesAreShowing ? 1 : 0];
    [self updateHeight];
}

-(void)updateHeight {
    CGFloat height = _changesAreShowing ? webViewHeight + kExpandHeight : kExpandHeight;
    [wc setPluginView:self details:[NSNumber numberWithFloat:height] forKey:@"cellHeight"];
    [wc noteHeightOfRowChanged:self];
    
}


@end