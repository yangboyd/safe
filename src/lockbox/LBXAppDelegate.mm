//
//  LBXAppDelegate.mm
//  Lockbox
//
//  Created by Rian Hunter on 7/25/13.
//  Copyright (c) 2013 Rian Hunter. All rights reserved.
//

#import <lockbox/LBXAppDelegate.h>

#import <lockbox/mount_mac.hpp>
#import <lockbox/lockbox_server.hpp>
#import <lockbox/lockbox_strings.h>
#import <lockbox/recent_paths_storage.hpp>
#import <lockbox/util.hpp>

#import <lockbox/logging.h>

enum {
    CHECK_MOUNT_INTERVAL_IN_SECONDS = 1,
};

// 10 to model after system mac recent menus
const lockbox::RecentlyUsedPathStoreV1::max_ent_t RECENTLY_USED_PATHS_MENU_NUM_ITEMS = 10;
static NSString *const LBX_ACTION_KEY = @"_lbx_action";


@implementation LBXAppDelegate

- (NSURL *)applicationSupportDirectoryError:(NSError **)err {
    NSURL *p = [NSFileManager.defaultManager
                URLForDirectory:NSApplicationSupportDirectory
                inDomain:NSUserDomainMask
                appropriateForURL:nil
                create:YES error:err];
    if (!p) return nil;
    
    NSString *executableName = NSBundle.mainBundle.infoDictionary[@"CFBundleExecutable"];
    
    NSURL *ourAppDirectory = [p URLByAppendingPathComponent:executableName];

    NSError *createErr;
    BOOL created = [NSFileManager.defaultManager
                    createDirectoryAtURL:ourAppDirectory
                    withIntermediateDirectories:NO
                    attributes:@{NSFilePosixPermissions: @0700}
                    error:&createErr];
    if (!created &&
        (![createErr.domain isEqualToString:NSPOSIXErrorDomain] ||
         createErr.code != EEXIST) &&
        (![createErr.domain isEqualToString:NSCocoaErrorDomain] ||
         createErr.code != NSFileWriteFileExistsError)) {
        if (err) *err = createErr;
        return nil;
    }
    
    return ourAppDirectory;
}

- (void)saveCurrentlyActive:(NSNotification *)notification {
    NSRunningApplication *app = [notification.userInfo objectForKey:NSWorkspaceApplicationKey];
    if (![app isEqual:NSRunningApplication.currentApplication]) {
        self.lastActiveApp = app;
    }
}

- (void)restoreLastActive {
    if (!self.createWindows.count && !self.mountWindows.count) {
        [self.lastActiveApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    }
}

- (void)_newMount:(lockbox::mac::MountDetails)md {
    self->path_store->use_path(md.get_source_path());
    self->mounts.push_back(std::move(md));
    [self _updateStatusMenu];
    self->mounts.back().open_mount();
    [self notifyUserTitle:@"Success"
                  message:[NSString stringWithFormat:@"You've successfully mounted \"%s.\"",
                           self->mounts.back().get_mount_name().c_str(), nil]];
}

- (void)createLockboxCanceled:(LBXCreateLockboxWindowController *)wc {
    [self.createWindows removeObject:wc];
    [self restoreLastActive];
}

- (void)createLockboxDone:(LBXCreateLockboxWindowController *)wc
                    mount:(lockbox::mac::MountDetails)md {
    (void) wc;
    [self _newMount:std::move(md)];
}

- (void)startLockboxCanceled:(LBXMountLockboxWindowController *)wc {
    [self.mountWindows removeObject:wc];
    [self restoreLastActive];
}

- (void)startLockboxDone:(LBXMountLockboxWindowController *)wc
                   mount:(lockbox::mac::MountDetails)md {
    (void)wc;
    [self _newMount:std::move(md)];
}

static
unsigned
mount_idx_from_menu_item(NSMenuItem *mi) {
    NSInteger mount_idx = mi.tag;
    assert(mount_idx >= 0);
    return (unsigned) mount_idx;
}

- (void)openMount:(id)sender {
    auto mount_idx = mount_idx_from_menu_item(sender);
    
    if (mount_idx >= self->mounts.size()) {
        // this mount index is invalid now
        return;
    }
    
    self->mounts[mount_idx].open_mount();
}

- (void)unmountMount:(id)sender {
    auto mount_idx = mount_idx_from_menu_item(sender);

    if (mount_idx >= self->mounts.size()) {
        // this mount index is invalid now
        return;
    }
    
    self->mounts[mount_idx].unmount();
}

- (void)createBitvault:(id)sender {
    (void)sender;
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    LBXCreateLockboxWindowController *wc = [[LBXCreateLockboxWindowController alloc]
                                            initWithDelegate:self fs:self->native_fs];
    [self.createWindows addObject:wc];
}

- (void)mountBitvault:(id)sender {
    (void)sender;
    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    LBXMountLockboxWindowController *wc = [[LBXMountLockboxWindowController alloc]
                                            initWithDelegate:self fs:self->native_fs];
    [self.mountWindows addObject:wc];
}

static
lockbox::RecentlyUsedPathStoreV1::max_ent_t
recent_idx_from_menu_item(NSMenuItem *mi) {
    NSInteger mount_idx = mi.tag;
    assert(mount_idx >= 0);
    return (lockbox::RecentlyUsedPathStoreV1::max_ent_t) mount_idx;
}

- (void)mountRecentBitvault:(id)sender {
    auto recent_idx = recent_idx_from_menu_item(sender);

    const auto & recent_paths = self->path_store->recently_used_paths();
    
    if (recent_idx >= recent_paths.size()) {
        // somehow this mount idx became invalid
        return;
    }
    
    [NSApplication.sharedApplication activateIgnoringOtherApps:YES];
    LBXMountLockboxWindowController *wc = [LBXMountLockboxWindowController.alloc
                                           initWithDelegate:self
                                           fs:self->native_fs
                                           path:recent_paths[recent_idx]];
                                           
    [self.mountWindows addObject:wc];
}

- (void)clearRecentBitvaultMenu:(id)sender {
    (void) sender;
    self->path_store->clear();
    [self _updateStatusMenu];
}

- (void)getBitvaultSource:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://github.com/rianhunter/bitvault"]];
}

- (void)testBubble:(id)sender {
    (void)sender;
    [self notifyUserTitle:@"Short Title"
                  message:(@"Very long message full of meaningful info that you "
                           @"will find very interesting because you love to read "
                           @"tray icon bubbles. Don't you? Don't you?!?!")];
}

- (void)quitBitvault:(id)sender {
    [NSApp terminate:sender];
}

- (NSMenuItem *)_addItemToMenu:(NSMenu *)menu
             title:(NSString *)title
              action:(SEL)sel {
    NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:title
                                                action:sel
                                         keyEquivalent:@""];
    mi.target = self;
    [menu addItem:mi];
    return mi;
}

- (void)_updateStatusMenu {
    NSMenu *menu = self.statusItem.menu;
    
    [menu removeAllItems];
    
    // Menu is:
    // [ (Open | Unmount) "<mount name>" ]
    // ...
    // [ <separator> ]
    // Create New...
    // Mount Existing...
    // Mount Recent >
    //   [ <folder icon> <mount name> ]
    //   ...
    //   [ <separator> ]
    //   Clear Menu
    // <separator>
    // Get Source Code
    // Quit Bitvault
    // [ <separator> ]
    // [ Test Bubble ]

    bool showUnmount = self->lastModifierFlags & NSAlternateKeyMask;
    NSString *verbString;
    SEL sel;
    if (showUnmount) {
        verbString = @"Unmount";
        sel = @selector(unmountMount:);
    }
    else {
        verbString = @"Open";
        sel = @selector(openMount:);
    }
    
    NSInteger tag = 0;
    for (const auto & md : self->mounts) {
        NSString *title = [NSString stringWithFormat:@"%@ \"%s\"",
                           verbString, md.get_mount_name().c_str(), nil];
        NSMenuItem *mi = [self _addItemToMenu:menu
                                        title:title
                                       action:sel];
        mi.tag = tag++;
    }

    if (tag) {
        [menu addItem:NSMenuItem.separatorItem];
    }
    
    // Create a New Bitvault
    [self _addItemToMenu:menu
                   title:@"Create New..."
                  action:@selector(createBitvault:)];
  
    // Mount an Existing Bitvault
    [self _addItemToMenu:menu
                   title:@"Mount Existing..."
                  action:@selector(mountBitvault:)];
    
    // create Submenu
    if (self->path_store) {
        NSMenu *recentSubmenu = NSMenu.alloc.init;
    
        NSInteger sub_tag = 0;
        for (const auto & p : self->path_store->recently_used_paths()) {
            NSMenuItem *mi = [self _addItemToMenu:recentSubmenu
                                            title:[NSString stringWithUTF8String:p.basename().c_str()]
                                           action:@selector(mountRecentBitvault:)];
            mi.image = [NSWorkspace.sharedWorkspace iconForFileType:@"public.folder"];
            mi.tag = sub_tag++;
        }
        
        if (sub_tag) [recentSubmenu addItem:NSMenuItem.separatorItem];
        
        [self _addItemToMenu:recentSubmenu
                       title:@"Clear Menu"
                      action:(sub_tag ? @selector(clearRecentBitvaultMenu:) : nil)];
        
        NSMenuItem *mi = [self _addItemToMenu:menu
                                        title:@"Mount Recent"
                                       action:nil];
        mi.submenu = recentSubmenu;
    }
    
    [menu addItem:NSMenuItem.separatorItem];
    
    // Get Source Code
    [self _addItemToMenu:menu
                   title:@"Get Source Code"
                  action:@selector(getBitvaultSource:)];
    
#ifndef NDEBUG
    // Test Bubble
    [self _addItemToMenu:menu
                   title:@"Test Bubble"
                  action:@selector(testBubble:)];
#endif
    
    [menu addItem:NSMenuItem.separatorItem];

    // Quit Bitvault
    [self _addItemToMenu:menu
                   title:@"Quit Bitvault"
                  action:@selector(quitBitvault:)];
    
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    (void)menu;
    assert(menu = self.statusItem.menu);
    self->lastModifierFlags = NSEvent.modifierFlags;
    // update menu based on modifier key
    [self _updateStatusMenu];
}

- (void)_setupStatusBar {
    NSMenu *statusMenu = [[NSMenu alloc] init];
    statusMenu.delegate = self;
    
    NSStatusBar *sb = [NSStatusBar systemStatusBar];
    self.statusItem = [sb statusItemWithLength:NSVariableStatusItemLength];
    
    self.statusItem.title = @"Bitvault";
    self.statusItem.highlightMode = YES;
    self.statusItem.menu = statusMenu;
    
    [self _updateStatusMenu];
}

- (IBAction)aboutWindowOK:(NSButton *)sender {
    [sender.window performClose:sender];
}

void PostMouseEvent(CGMouseButton button, CGEventType type, const CGPoint point)
{
    CGEventRef theEvent = CGEventCreateMouseEvent(NULL, type, point, button);
    CGEventSetType(theEvent, type);
    CGEventPost(kCGHIDEventTap, theEvent);
    CFRelease(theEvent);
}

- (void)clickStatusItem {
    NSWindow *statusItemWindow;
    for (NSWindow *w in [NSApplication.sharedApplication windows]) {
        if (!w.title.length) {
            // window without a title, assuming this is our status bar window
            statusItemWindow = w;
            break;
        }
    }
    NSRect f = statusItemWindow.frame;
    CGFloat x_to_press = (f.origin.x + f.size.width/2);
    assert(!NSStatusBar.systemStatusBar.isVertical);
    CGPoint to_press = {x_to_press, NSStatusBar.systemStatusBar.thickness / 2};
    PostMouseEvent(kCGMouseButtonLeft, kCGEventLeftMouseDown, to_press);
}

- (BOOL)haveUserNotifications {
    return NSClassFromString(@"NSUserNotificationCenter") ? YES : NO;
}

- (void)notifyUserTitle:(NSString *)title
                message:(NSString *)msg
                 action:(SEL) sel {
    if (![self haveUserNotifications]) return;
    
    NSUserNotification *user_not = [[NSUserNotification alloc] init];
    user_not.title = title;
    user_not.informativeText = msg;
    user_not.deliveryDate = [NSDate dateWithTimeInterval:0 sinceDate:NSDate.date];
    user_not.soundName = NSUserNotificationDefaultSoundName;
    
    if (sel) {
        user_not.userInfo = @{LBX_ACTION_KEY: NSStringFromSelector(sel)};
    }

    [NSUserNotificationCenter.defaultUserNotificationCenter
     scheduleNotification:user_not];
}

- (void)notifyUserTitle:(NSString *)title
                message:(NSString *)msg {
    [self notifyUserTitle:title message:msg action:nil];
}

#define SuppressPerformSelectorLeakWarning(Stuff) \
do { \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Warc-performSelector-leaks\"") \
Stuff; \
_Pragma("clang diagnostic pop") \
} while (0)

// always present and remove notifications, to get growl-like functionality
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
       didActivateNotification:(NSUserNotification *)notification {
    (void)center;
    if (notification.activationType == NSUserNotificationActivationTypeContentsClicked &&
        notification.userInfo &&
        notification.userInfo[LBX_ACTION_KEY]) {
        SuppressPerformSelectorLeakWarning([self performSelector:NSSelectorFromString(notification.userInfo[LBX_ACTION_KEY])]);
    }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center
        didDeliverNotification:(NSUserNotification *)notification {
    [center removeDeliveredNotification:notification];
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
     shouldPresentNotification:(NSUserNotification *)notification {
    (void) center;
    (void) notification;
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification {
    (void) notification;
    
    [self.aboutWindow orderOut:self];
    self.aboutWindow = nil;
    
    [self _setupStatusBar];
    
    if ([self haveUserNotifications]) {
        [self notifyUserTitle:@"Bitvault is now Running!"
                      message:@"If you need to use Bitvault, just click on Bitvault menu bar icon."
                       action:@selector(clickStatusItem)];
    }
    else [self clickStatusItem];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    (void)aNotification;
    
    log_printer_default_init();
    logging_set_global_level(LOG_DEBUG);
    log_debug("Hello world!");
    
    NSError *err;
    NSURL *appSupportDir = [self applicationSupportDirectoryError:&err];
    if (!appSupportDir) {
        lbx_log_critical("Error while getting application support directory: (%s:%ld) %s",
                         err.domain.UTF8String,
                         (long) err.code,
                         err.localizedDescription.UTF8String);
        [NSApp presentError:err];
        [NSApp terminate:self];
        return;
    }
    
    lockbox::global_webdav_init();
    
    self->native_fs = lockbox::create_native_fs();
    
    auto recently_used_paths_storage_path =
    self->native_fs->pathFromString(appSupportDir.path.fileSystemRepresentation).join(lockbox::RECENTLY_USED_PATHS_V1_FILE_NAME);
    
    try {
        try {
            self->path_store = lockbox::make_unique<lockbox::RecentlyUsedPathStoreV1>(self->native_fs, recently_used_paths_storage_path, RECENTLY_USED_PATHS_MENU_NUM_ITEMS);
        }
        catch (const lockbox::RecentlyUsedPathsParseError & err) {
            lbx_log_error("Parse error on recently used path store: %s", err.what());
            // delete path and try again
            self->native_fs->unlink(recently_used_paths_storage_path);
            self->path_store = lockbox::make_unique<lockbox::RecentlyUsedPathStoreV1>(self->native_fs, recently_used_paths_storage_path, RECENTLY_USED_PATHS_MENU_NUM_ITEMS);
        }
    }
    catch (const std::exception & err) {
        // error while creating recently used path storee
        // not a huge deal, but log error
        lbx_log_error("Couldn't create recently used path store: %s", err.what());
    }
    
    self.createWindows = [NSMutableArray array];
    self.mountWindows = [NSMutableArray array];
    
    // get notification whenever active application changes,
    // we preserve this so we can switch back when the user
    // selects "cancel" on our dialogs
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(saveCurrentlyActive:)
                                                               name:NSWorkspaceDidActivateApplicationNotification
                                                             object:nil];
    // kickoff mount watch timer
    // get notifaction whenever device is unmounted
    // so we can update our internal structures
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                           selector:@selector(driveWasUnmounted:)
                                                               name:NSWorkspaceDidUnmountNotification
                                                             object:nil];

    if ([self haveUserNotifications]) {
        NSUserNotificationCenter.defaultUserNotificationCenter.delegate = self;
    }

    [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    [NSBundle loadNibNamed:@"LBXAboutWindow" owner:self];
    self.aboutWindow.delegate = self;
    self.aboutWindow.level = NSModalPanelWindowLevel;
    self.aboutWindowText.stringValue = [NSString stringWithUTF8String:LOCKBOX_ABOUT_BLURB];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    
    for (auto & md : self->mounts) {
        md.unmount();
    }
    
    lockbox::global_webdav_shutdown();
}

- (void)driveWasUnmounted:(NSNotification *)p {
    (void)p;

    // check all devices and if any of them were no longer unmount
    // then stop and update status
    // TODO: maybe just unmount them based on the notification
    //       are notifications reliable? guessing yes
    for (auto it = self->mounts.begin(); it != self->mounts.end();) {
        if (!it->is_still_mounted()) {
            it->signal_stop();
            auto mount_name = it->get_mount_name();
            it = self->mounts.erase(it);
            [self _updateStatusMenu];
            [self notifyUserTitle:@"Success"
                          message:[NSString stringWithFormat:@"You've successfully unmounted \"%s.\"",
                                   mount_name.c_str(), nil]];
        }
        else ++it;
    }
}

@end