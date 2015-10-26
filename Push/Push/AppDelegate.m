//
//  AppDelegate.m
//  Push
//
//  Created by Jordan Zucker on 10/13/15.
//  Copyright © 2015 pubnub. All rights reserved.
//

#import <PubNub/PubNub.h>
#import "AppDelegate.h"

NSString *const LAST_READ_DATE_KEY = @"PNLastReadDateKey";
NSString *const DEVICE_TOKEN_KEY = @"PNDeviceTokenKey";

@interface AppDelegate ()
@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
#pragma mark - 1) Special instance creation
    // Must create separate callback queue in order to ensure semaphores trigger for paging
    PubNub *pubNub = [PubNub clientWithConfiguration:[PNConfiguration configurationWithPublishKey:@"pub-c-366ee301-3a9a-41ca-b3f2-d9dba11dbd10" subscribeKey:@"sub-c-66eb5ede-fb1c-11e3-bacb-02ee2ddab7fe"] callbackQueue:dispatch_queue_create("com.Push", DISPATCH_QUEUE_CONCURRENT)];
    self.client = pubNub;
    
    UIUserNotificationType types = UIUserNotificationTypeBadge |
    UIUserNotificationTypeSound | UIUserNotificationTypeAlert;
    
    UIUserNotificationSettings *mySettings =
    [UIUserNotificationSettings settingsForTypes:types categories:nil];
    
    // In iOS 8, this is when the user receives a system prompt for notifications in your app
    [[UIApplication sharedApplication] registerUserNotificationSettings:mySettings];
    [[UIApplication sharedApplication] registerForRemoteNotifications];
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    // Set lastReadDate at app launch and app exit for most accurate value
    // Wrapped in background task for guaranteed execution
    __weak typeof(self) wself = self;
    UIBackgroundTaskIdentifier timeTokenFetchIdentifier = [application beginBackgroundTaskWithName:@"TimeToken" expirationHandler:^{
        __strong typeof(wself) sself = wself;
        [sself.client timeWithCompletion:^(PNTimeResult *result, PNErrorStatus *status) {
            [[NSUserDefaults standardUserDefaults] setObject:result.data.timetoken forKey:LAST_READ_DATE_KEY];
            [[NSUserDefaults standardUserDefaults] synchronize];
            [application endBackgroundTask:timeTokenFetchIdentifier];
        }];
    }];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    // Always reset badge count when launching app so that we can set it in the background
    [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
    // set lastReadDate on app launch and app exit for most accurate value
    [self.client timeWithCompletion:^(PNTimeResult *result, PNErrorStatus *status) {
        [[NSUserDefaults standardUserDefaults] setObject:result.data.timetoken forKey:LAST_READ_DATE_KEY];
    }];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

#pragma mark - APNS

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    NSLog(@"deviceToken: %@", deviceToken);
    [[NSUserDefaults standardUserDefaults] setObject:deviceToken forKey:@"DeviceToken"];
    [self.client addPushNotificationsOnChannels:@[@"teddyr"] withDevicePushToken:deviceToken andCompletion:^(PNAcknowledgmentStatus *status) {
        NSLog(@"status: %@", status);
    }];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    NSLog(@"%s with error: %@", __PRETTY_FUNCTION__, error);
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {

    __block NSInteger finalBadgeCount = 0;
    // There is a false limit here so that we can test paging!
    NSInteger limit = 5;
    __block NSNumber *startTimeToken = nil;
#pragma mark - 2) Semaphores for synchronous paging
    // We need to use a semaphore to block the async call because PubNub history paging must be synchronous!
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __weak typeof(self) wself = self;
    __block NSInteger previousHistoryResultsCount = 0;
    __block BOOL shouldStop = NO;
    __block BOOL isPaging = NO;
    
#pragma mark - 3) First page is special, we are fetching messages when we only need count (optionally: store messages to save on history calls)
    [wself.client historyForChannel:@"teddyr" start:[[NSUserDefaults standardUserDefaults] objectForKey:LAST_READ_DATE_KEY] end:nil limit:5 reverse:YES includeTimeToken:YES withCompletion:^(PNHistoryResult *result, PNErrorStatus *status) {
        if (status.isError) {
            NSLog(@"fetch had an error");
            completionHandler(UIBackgroundFetchResultFailed);
            return;
        }
        // Be conscious of time constraints. Apple has a limit of 30 seconds wall-clock time on background execution.
        // Make sure not to surpass it. Too much paging might be an issue! Save messages here if you want to reduce possible
        // history calls (they do cost money!).
        // Surpassing the 30 seconds of wall-clock time will cause early app termination.
        previousHistoryResultsCount = result.data.messages.count;
        finalBadgeCount += previousHistoryResultsCount;
        startTimeToken = result.data.end;
        // If we hit the limit, then we have to page, even if there are no more messages to fetch, because we have no way of knowing.
#pragma mark - 4) We have to page a second time if we have the maximum number of messages, no way of knowing if there's more unless we try
        if (previousHistoryResultsCount == limit) {
            isPaging = YES;
        }
        // Unlock semaphore in asynch completion block
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
#pragma mark - 5) Second page and on are slightly different
    while (isPaging &&
           !shouldStop) {
        [wself.client historyForChannel:@"teddyr" start:startTimeToken end:nil limit:5 reverse:YES includeTimeToken:YES withCompletion:^(PNHistoryResult *result, PNErrorStatus *status) {
            // Handle an error
            if (status.isError) {
                NSLog(@"fetch had an error");
                completionHandler(UIBackgroundFetchResultFailed);
                return;
            }
            previousHistoryResultsCount = result.data.messages.count;
            finalBadgeCount += previousHistoryResultsCount;
            startTimeToken = result.data.end;
            
            // Stop when we have less than the maximum number of messages. This would mean an extra network call if we have modulo 0 results
            if (previousHistoryResultsCount < limit) {
                shouldStop = YES;
            }
            
            dispatch_semaphore_signal(semaphore);
        }];
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
    
#pragma mark - 6) Make sure to update badge count and end background execution!
    // Here is where we adjust the badge count
    [UIApplication sharedApplication].applicationIconBadgeNumber = finalBadgeCount;
    // This is called to finish background execution. Make sure this is called!
    completionHandler(UIBackgroundFetchResultNewData);
}

@end
