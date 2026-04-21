//
// PreferencesController.m
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
//    distribution.
//

#import "PreferencesController.h"

@implementation PreferencesController

- (id)init
{
    self = [super initWithWindowNibName:@"PreferencesController"];
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    [self.window setBackgroundColor:[NSColor colorWithSRGBRed:(61.0 / 255.0)
                                     green:(39.0 / 255.0) blue:(93.0 / 255.0)
                                     alpha:1.0]];
}

- (NSDictionary *)settings
{
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                              [mPath1 stringValue],
                              @"Path1", [mPath2 stringValue],
                              @"Path2", [mPath3 stringValue],
                              @"Path3", nil];

    return settings;
}

- (void)setSettings:(NSDictionary *)settings
{
    [mPath1 setStringValue:[settings objectForKey:@"Path1"]];
    [mPath2 setStringValue:[settings objectForKey:@"Path2"]];
    [mPath3 setStringValue:[settings objectForKey:@"Path3"]];
}

@end
