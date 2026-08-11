//
//  NDNotificationCenterHackery.h
//  Grasp
//
//  Created by Elmee on 01/08/26.
//  Copyright © 2026 KaMy Studio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

NS_ASSUME_NONNULL_BEGIN

@interface NDNotificationCenterHackery : NSObject

+ (void)removeDefaultAction:(UNMutableNotificationContent*) content;

@end

NS_ASSUME_NONNULL_END
