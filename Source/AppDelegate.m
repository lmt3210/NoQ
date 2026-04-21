//
// AppDelegate.m
// 
// Copyright (c) 2026 Larry M. Taylor
//
// This software is provided 'as-is', without any express or implied
// warranty. In no event will the authors be held liable for any damages
// arising from the use of this software. Permission is granted to anyone to
// use this software for any purpose, including commercial applications, and to
// to alter it and redistribute it freely, subject to 
// the following restrictions:
//
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgment in the product documentation would be
//    appreciated but is not required.
// 2. Altered source versions must be plainly marked as such, and must not be
//    misrepresented as being the original software.
// 3. This notice may not be removed or altered from any source
//

#import <sys/types.h>
#import <pwd.h>
#import <uuid/uuid.h>
#import <sys/utsname.h>

#import "AppDelegate.h"
#import "NSFileManager+DirectoryLocations.h"

static CFStringRef NoQAppID = CFSTR("com.larrymtaylor.NoQ");
static NSThread *gMonitorThread = nil;
static os_log_t gLog = nil;
static NSString *gLogFile = @"";

void fsEventsCallback(ConstFSEventStreamRef streamRef,
                      void *clientCallBackInfo, size_t numEvents,
                      void *eventPaths,
                      const FSEventStreamEventFlags *eventFlags,
                      const FSEventStreamEventId *eventIds)
{
    CFArrayRef cfEventPaths = (CFArrayRef)eventPaths;

    for (size_t i = 0; i < numEvents; i++)
    {
        CFStringRef path = CFArrayGetValueAtIndex(cfEventPaths, i);
        
        if (path != NULL)
        {
            removexattr(CFStringGetCStringPtr(path, kCFStringEncodingUTF8),
                        "com.apple.quarantine", 0);
            const char *str =
            CFStringGetCStringPtr(path, kCFStringEncodingMacRoman);
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            [dateFormatter setDateFormat:@"MM/dd/yyyy h:mm a"];
            NSString *day = [dateFormatter stringFromDate:[NSDate date]];
            LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO,
                  @"%@: Removed quarantine attribute from %s", day, str);
        }
    }
}

// Load latest event ID that was process or fallback
// to kFSEventStreamEventIdSinceNow
FSEventStreamEventId prefLoadNoQState(void)
{
    CFNumberRef eventIDNum = CFPreferencesCopyValue(CFSTR("LastEventID"),
                                                    NoQAppID,
                                                    kCFPreferencesCurrentUser,
                                                    kCFPreferencesAnyHost);

    // Convert CFNumberRef to FSEventStreamEventId safely
    FSEventStreamEventId latestEventId = kFSEventStreamEventIdSinceNow;

    if (eventIDNum != NULL)
    {
        // From CFNumberGetValue docs:
        // "If the argument type differs from the return type,
        // and the conversion is lossy or the return value is out of range,
        // then this function passes back an approximate value
        // in valuePtr and returns false."
        // when that happens, we log the fallback and start
        // monitoring from now on.
        if (!CFNumberGetValue(eventIDNum, kCFNumberSInt64Type,
                              &latestEventId))
        {
            // Fallback if conversion fails
            latestEventId = kFSEventStreamEventIdSinceNow;
        }

        CFRelease(eventIDNum);
    }
    
    return latestEventId;
}

// Save latest event ID along with volume UUID
void prefSaveNoQState(FSEventStreamRef streamRef)
{
    // Grab the latest event ID from the stream
    FSEventStreamEventId latestEventId =
        FSEventStreamGetLatestEventId(streamRef);
    
    // Persist the event ID and stream UUID using CFPreferences
    CFNumberRef eventIDNum =
        CFNumberCreate(NULL, kCFNumberSInt64Type, &latestEventId);
    CFPreferencesSetValue(CFSTR("LastEventID"), eventIDNum,
                          NoQAppID, kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFRelease(eventIDNum);
}


@implementation AppDelegate

@synthesize mStatusBar;
@synthesize mStatusMenu;
@synthesize mStartMenu;

#define UDKEY_SETTINGS_LIST   @"NoQSettings"

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Set up logging
    gLog = os_log_create("com.larrymtaylor.NoQ", "AppDelegate");
    NSBundle *appBundle = [NSBundle mainBundle];
    NSString *path =
        [[NSFileManager defaultManager] applicationSupportDirectory];
    gLogFile = [[NSString alloc] initWithFormat:@"%@/logFile.txt", path];
    UInt64 fileSize = [[[NSFileManager defaultManager]
                        attributesOfItemAtPath:gLogFile error:nil] fileSize];

    if (fileSize > (1024 * 1024))
    {
        [[NSFileManager defaultManager] removeItemAtPath:gLogFile error:nil];
    }

    // Get macOS version
    NSOperatingSystemVersion sysVersion =
        [[NSProcessInfo processInfo] operatingSystemVersion];
    NSString *systemVersion = [NSString stringWithFormat:@"%ld.%ld",
                               sysVersion.majorVersion,
                               sysVersion.minorVersion];
    
    // Log some basic information
    NSDictionary *appInfo = [appBundle infoDictionary];
    NSString *appVersion =
        [appInfo objectForKey:@"CFBundleShortVersionString"];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MM/dd/yyyy h:mm a"];
    NSString *day = [dateFormatter stringFromDate:[NSDate date]];
    struct utsname osinfo;
    uname(&osinfo);
    NSString *info = [NSString stringWithUTF8String:osinfo.version];
    LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO,
          @"\nNoQ v%@ running on macOS %@ (%@)\n%@",
          appVersion, systemVersion, day, info);
    CFRunLoopRef rl = CFRunLoopGetCurrent();
    LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO, @"Main thread = 0x%08x", rl);

    // Setup status bar menu
    mStatusBar = [[NSStatusBar systemStatusBar]
        statusItemWithLength:NSVariableStatusItemLength];
    mStatusBar.menu = mStatusMenu;
    mStatusBar.highlightMode = YES;
    
    // Create preferences controller
    mPreferencesController = [[PreferencesController alloc] init];
    
    // Watch for preferences panel close
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(preferencesPanelClose:)
        name:NSWindowWillCloseNotification
        object:[mPreferencesController window]];
    
    // Get settings and show icon
    [self loadSettings];
    [self setIcon];

    // Initialize checkbox
    mStart = 0;  // always start disabled
    [mStartMenu setState:mStart];
    
    // Version check
    mVersionCheck = [[LTVersionCheck alloc] initWithAppName:@"NoQ"
                     withAppVersion:appVersion
                     withLogHandle:gLog withLogFile:gLogFile];
}

- (void)setIcon
{
    if (mStart == 1)
    {
        [mStatusBar setImage:[NSImage imageNamed:@"icon_16x16.png"]];
    }
    else
    {
        [mStatusBar setImage:[NSImage imageNamed:@"noq.png"]];
    }
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MM/dd/yyyy h:mm a"];
    NSString *day = [dateFormatter stringFromDate:[NSDate date]];
    LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO, @"%@: Exiting NoQ", day);
}

- (IBAction)showPreferences:(id)sender
{
    [mPreferencesController showWindow:self];
}

- (void)preferencesPanelClose:(NSNotification *)aNotification
{
    NSDictionary *settings = [mPreferencesController settings];
    mPath1 = [settings objectForKey:@"Path1"];
    mPath2 = [settings objectForKey:@"Path2"];
    mPath3 = [settings objectForKey:@"Path3"];
    [self saveSettings];
}

- (IBAction)showAboutBox:(id)sender
{
    [[AboutWindowController defaultController].window orderFront:self];
}

- (IBAction)startAction:(id)sender
{
    (mStart == 0) ? (mStart = 1) : (mStart = 1);
    [mStartMenu setState:mStart];
    
    if (mStart == 1)
    {
        [self startThread];
    }
    
    [self setIcon];
}

- (void)loadSettings
{
    NSUserDefaults *userDefaults =
          [[NSUserDefaultsController sharedUserDefaultsController] values];
    NSDictionary *settings = [userDefaults valueForKey:UDKEY_SETTINGS_LIST];
    
    if (settings != nil)
    {
        mPath1 = [settings objectForKey:@"Path1"];
        (mPath1 == nil) ? (mPath1 = @"") : mPath1;
        mPath2 = [settings objectForKey:@"Path2"];
        (mPath2 == nil) ? (mPath2 = @"") : mPath2;
        mPath3 = [settings objectForKey:@"Path3"];
        (mPath3 == nil) ? (mPath3 = @"") : mPath3;
    }
    else
    {
        mPath1 = @"";
        mPath2 = @"";
        mPath3 = @"";
    }
    
    NSDictionary *loadedSettings = [NSDictionary dictionaryWithObjectsAndKeys:
        mPath1, @"Path1", mPath2, @"Path2", mPath3, @"Path3", nil];
    [mPreferencesController setSettings:loadedSettings];
}

- (void)saveSettings
{
    NSUserDefaults *userDefaults =
        [[NSUserDefaultsController sharedUserDefaultsController] values];
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                              mPath1, @"Path1", mPath2, @"Path2",
                              mPath3, @"Path3", nil];
    [userDefaults setValue:settings forKey:UDKEY_SETTINGS_LIST];
}

- (void)startThread
{
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        if (gMonitorThread == nil)
        {
            gMonitorThread = [[NSThread alloc] initWithTarget:self
                              selector:@selector(monitorThread) object:nil];
        }

        [gMonitorThread start];
    });
}

- (void)monitorThread
{
    @autoreleasepool
    {
        LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO, @"Starting monitor thread");
        [[NSThread currentThread] setName:@"MonitorThread"];
        CFRunLoopRef rl = CFRunLoopGetCurrent();
        LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO,
              @"Monitor thread = 0x%08x", rl);

        // We can't run the run loop unless it has an associated input
        // source or a timer. So we'll just create a timer that will
        // never fire - unless the app runs for 10,000 years
        [NSTimer scheduledTimerWithTimeInterval:
             [[NSDate distantFuture] timeIntervalSinceNow]
               target:self selector:@selector(doNothing)
               userInfo:nil repeats:YES];
        
        CFStringRef path1 = (__bridge CFStringRef)mPath1;
        CFStringRef path2 = (__bridge CFStringRef)mPath2;
        CFStringRef path3 = (__bridge CFStringRef)mPath3;
        int pathCount = 0;
        
        if ([mPath1 isEqualToString:@""] == NO)
        {
            ++pathCount;
            LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO, @"Monitoring %@", mPath1);

            if ([mPath2 isEqualToString:@""] == NO)
            {
                ++pathCount;
                LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO, @"Monitoring %@",
                      mPath2);

                if ([mPath3 isEqualToString:@""] == NO)
                {
                    ++pathCount;
                    LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO, @"Monitoring %@",
                          mPath3);
                }
            }
        }

        const void *paths[] = { path1, path2, path3 };
        
        CFArrayRef pathsToMonitor =
            CFArrayCreate(NULL, (const void **)&paths, pathCount,
                          &kCFTypeArrayCallBacks);
        void *callbackInfo = NULL;
        CFAbsoluteTime latency = 3.0; // seconds
        FSEventStreamEventId latestEventId = prefLoadNoQState();
        FSEventStreamRef fsEventStream =
            FSEventStreamCreate(NULL, &fsEventsCallback, callbackInfo,
                                pathsToMonitor, latestEventId, latency,
                                (kFSEventStreamCreateFlagWatchRoot |
                                kFSEventStreamCreateFlagFileEvents |
                                kFSEventStreamCreateFlagIgnoreSelf |
                                kFSEventStreamCreateFlagUseCFTypes));
        
        dispatch_queue_t dispatchQueue =
            dispatch_queue_create("com.larrymtaylor.noq.queue", NULL);
        FSEventStreamSetDispatchQueue(fsEventStream, dispatchQueue);
        Boolean didEventStreamStart = FSEventStreamStart(fsEventStream);
        
        if (!didEventStreamStart)
        {
            LTLog(gLog, gLogFile, OS_LOG_TYPE_ERROR,
                  @"Failed to start the momitor event stream!");
            goto cleanup;
        }

        LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO,
              @"Starting monitor thread loop run");
        CFRunLoopRun();
        LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO, @"Monitor thread stopped");
        
        // Perform a synchronous flush to ensure all
        // pending events are processed
        // before stopping the stream.
        // Note: This call may block the thread.
        FSEventStreamFlushSync(fsEventStream);
        prefSaveNoQState(fsEventStream);
        FSEventStreamStop(fsEventStream);
        FSEventStreamInvalidate(fsEventStream);

        cleanup:
            FSEventStreamRelease(fsEventStream);
            CFRelease(pathsToMonitor);

        LTLog(gLog, gLogFile, OS_LOG_TYPE_INFO, @"Exiting monitor thread");
        
        return;

    }
}

- (void)doNothing
{
}
        
@end
