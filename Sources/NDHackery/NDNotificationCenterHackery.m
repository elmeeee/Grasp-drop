//
//  NDNotificationCenterHackery.m
//  Grasp
//
//  Created by Elmee on 10/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

#import "NDNotificationCenterHackery.h"
#import <objc/runtime.h>

@implementation NDNotificationCenterHackery

+ (void)removeDefaultAction:(UNMutableNotificationContent*) content {
    @try {
        [content setValue:@YES forKey:@"_shouldHideDate"];
        [content setValue:@YES forKey:@"_shouldPreventNotificationDismissalAfterSaving"];
        [content setValue:@YES forKey:@"_shouldDisplayActionsInline"];
    } @catch (NSException *exception) {
        // Fallback for private API key swizzling
    }
}

@end
