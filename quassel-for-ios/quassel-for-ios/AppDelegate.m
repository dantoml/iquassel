// Dual-Licensed, GPLv3 and Woboq GmbH's private license. See file "LICENSE"

#import "AppDelegate.h"
#import "BufferViewController.h"
#import "Message.h"
#import "LoginViewController.h"
#import "DDLog.h"
#import "DDASLLogger.h"
#import "DDTTYLogger.h"
#import "ConnectingViewController.h"
#import "ErrorViewController.h"

#import "AppState.h"


@implementation AppDelegate
@synthesize quasselCoreConnection;
@synthesize bufferListViewControllerPopoverController;
@synthesize bufferListBarButtonItem;

@synthesize window = _window;

@synthesize lastErrorMessage;

@synthesize shouldAutoReconnect;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
        //UINavigationController *navigationController = [splitViewController.viewControllers lastObject];
        splitViewController.delegate = self;
        //(id)navigationController.topViewController;
    } else {
        
    }
    
    
#ifdef TESTFLIGHT
    [TestFlight takeOff:@"c7d61f3a-8a1c-4b0a-ad5c-02bf0987114b"];
//    [TestFlight setDeviceIdentifier:[[UIDevice currentDevice] uniqueIdentifier]];
#endif
    
    bgTask = UIBackgroundTaskInvalid;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(doBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(doForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification object:nil];
    
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:-1];
    
    //NSSetUncaughtExceptionHandler (&myExceptionHandler);
    
    return YES;
}

void myExceptionHandler (NSException *exception)
{
    NSArray *stack = [exception callStackReturnAddresses];
    NSLog(@"Stack trace: %@", stack);
}

- (void) endBgTask
{
    UIApplication *app = [UIApplication sharedApplication];
    if (bgTask != UIBackgroundTaskInvalid) {
        NSLog(@"BACKGROUNDHANDLER endBgTask Actually ending it %lu", (unsigned long)bgTask);
        [app endBackgroundTask:bgTask];
        bgTask = UIBackgroundTaskInvalid;
    }
}

- (void) doForeground:(NSNotification *)aNotification {
    [self endBgTask];
}


- (void) doBackground:(NSNotification *)aNotification {
    UIApplication *app = [UIApplication sharedApplication];


    NSLog(@"BACKGROUNDHANDLER We entered the background, trying to postpone it, we would get killedin %f seconds", [app backgroundTimeRemaining]);
    if ([app respondsToSelector:@selector(beginBackgroundTaskWithExpirationHandler:)]) {
        bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
            // Synchronize the cleanup call on the main thread in case
            // the task actually finishes at around the same time.
            NSLog(@"BACKGROUNDHANDLER background expiration time ended :( We will get killed in %f seconds", [app backgroundTimeRemaining]);
            
            __block __weak AppDelegate* selfCpy = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                // FIXME Here we should kill the socket..
                NSLog(@"BACKGROUNDHANDLER Disconnecting socket now on main thread");

                [selfCpy disconnectQuasselConnection];
                [selfCpy endBgTask];
            });
        }];
    }
    
}

							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.

    if (quasselCoreConnection && quasselCoreConnection.socket && quasselCoreConnection.socket.isConnected) {
        shouldAutoReconnect = YES;

    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.

}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    // FIXME: Check if really invisible

    // FIXME: Check if we have config

    // FIXME: Make sure we don't init any User/Network structures but just fetch all backlogs

    // FIXME: Idea: Could remember all query buffers in NSUserDefaults or so and only fetch those
    // FIXME: Could even remember the last MsgId of each buffer so we don't need to fetch it all

    // http://nsscreencast.com/episodes/92-background-fetch

    // FIXME: idea: notifications for hilights, for message just unread count?
}



- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // iOS8+
    if ([application respondsToSelector:@selector(registerUserNotificationSettings:)]) {
        UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeBadge categories:nil];
        [application registerUserNotificationSettings:settings];
    }

    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    if ([self bufferViewController] && quasselCoreConnection) {
        BufferId *bufferId = [self bufferViewController].currentBufferId;
        NSArray *messages = [quasselCoreConnection.bufferIdMessageListMap objectForKey:bufferId];
        [self updateLastSeenOrBadge:bufferId messageId:[[messages lastObject] messageId]];
    }

    [self performSelector:@selector(doReconnectIfNecessary) withObject:nil afterDelay:0.25];
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (BufferListViewController*) bufferListViewController
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
        BufferListViewController *blvC = (BufferListViewController*)[splitViewController.viewControllers objectAtIndex:0];
        return blvC;
    } else {
        UINavigationController *navController = (UINavigationController*) self.window.rootViewController;
        NSArray *vcs = navController.viewControllers;
        for (int i = 0; i < vcs.count; i++)
            if ([[vcs objectAtIndex:i] isMemberOfClass:[BufferListViewController class]])
                return [vcs objectAtIndex:i];
        NSLog(@"FIXME, find the bufferListViewController in navigation stack, is nil");
        return nil;
    }
}

- (UIViewController*) detailViewController
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
        return (UISplitViewController*)[[[splitViewController.viewControllers lastObject] viewControllers] lastObject];
    } else {
        UINavigationController *navController = (UINavigationController*) self.window.rootViewController;
        //NSLog(@"FIXME detailViewController");
        return navController.topViewController;
    }
}


- (BufferViewController*) bufferViewController
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UIViewController *vc = [self detailViewController];
        if ([vc isKindOfClass:[BufferViewController class]])
            return (BufferViewController*) vc;
        return nil;
    } else {
        UINavigationController *navController = (UINavigationController*) self.window.rootViewController;
        NSArray *vcs = navController.viewControllers;
        for (int i = 0; i < vcs.count; i++)
            if ([[vcs objectAtIndex:i] isMemberOfClass:[BufferViewController class]])
                return [vcs objectAtIndex:i];
        NSLog(@"FIXME, find the bufferViewController in navigation stack, is nil");
        return nil;
    }
}

- (void) bufferViewControllerDidAppear
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        NSLog(@"bufferViewControllerDidAppear -> reloadBufferListAndSelectLastUsedOne");
        [[self bufferListViewController] reloadBufferListAndSelectLastUsedOne];
    }
}

- (void) startConnectingTo:(NSString*)hostName port:(int)port userName:(NSString*)userName passWord:(NSString*)passWord
{
    quasselCoreConnection = [[QuasselCoreConnection alloc] init];
    quasselCoreConnection.delegate = self;


    BufferId* bufferId = [AppState getLastSelectedBufferId];
    if (bufferId.intValue >= 0) {
        NSLog(@"startConnectingTo will restore buffer");
        quasselCoreConnection.bufferIdToRestore = bufferId;
    }

    [quasselCoreConnection connectTo:hostName port:port userName:userName passWord:passWord];
}

#pragma mark - Quassel

- (void) updateConnectionProgress:(NSString*)s
{
    
    if ([self.detailViewController isMemberOfClass:ConnectingViewController.class]) {
        ConnectingViewController *cvc = (ConnectingViewController*)self.detailViewController;
        cvc.navigationItem.title = s;
    }
}

- (void) quasselConnected
{
    shouldAutoReconnect = NO;
    NSLog(@"BufferListViewController quasselConnected");
    [self updateConnectionProgress:@"Connected"];
}

- (void) quasselAuthenticated
{
    NSLog(@"BufferListViewController quasselAuthenticated");
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [self bufferListViewController].quasselCoreConnection = quasselCoreConnection;
        // For iPhone, it is done in ConnectingViewController
    }
    [self updateConnectionProgress:@"Authenticated"];
}

- (void) quasselEncrypted
{
    NSLog(@"BufferListViewController quasselEncrypted");
    [self updateConnectionProgress:@"Encrypted"];
}

- (void) quasselBufferListReceived
{
    NSLog(@"BufferListViewController quasselBufferListReceived");

}

- (void) quasselNetworkInitReceived:(NSString*)networkName
{
    [self updateConnectionProgress:[NSString stringWithFormat:@"Parsed %@", networkName]];
}


- (void) quasselAllNetworkInitReceived
{
    NSLog(@"BufferListViewController quasselAllNetworkInitReceived");
//    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [[self detailViewController] performSegueWithIdentifier:@"ConnectedSegue" sender:self];
//    } else {
//        
//    }
    [self updateConnectionProgress:@"Logged In"];
}

- (void) quasselBufferListUpdated
{
    NSLog(@"BufferListViewController quasselBufferListUpdated");
    [[self bufferListViewController].tableView reloadData];
}

- (void) quasselSwitchToBuffer:(BufferId*)bufferId
{
    [[self bufferListViewController] clickRowForBufferId:bufferId];
}


- (void) quasselMessageReceived:(Message*)msg received:(enum ReceiveStyle)style onIndex:(int)i
{    
    if ([self bufferViewController]) {
        BufferViewController* bvc = [self bufferViewController];
        NSLog(@"Message received, currentBufferId=%@ msgBufferId=%@", [bvc currentBufferId], msg.bufferInfo.bufferId);
        // Check detail view if if is relevant for this message
        if ([[bvc currentBufferId] isEqual:msg.bufferInfo.bufferId]) {
            [bvc addMessage:msg received:style onIndex:i];
            [self updateLastSeenOrBadge:msg.bufferInfo.bufferId messageId:msg.messageId];
            return;
        } else if ([bvc currentBufferId]) {
            // If not, update bufferListViewController
            BufferListViewController* blVc = [self bufferListViewController];
            [blVc reloadRowForBufferId:msg.bufferInfo.bufferId];
        } else {
            NSLog(@"Not updating UI, we seem not to be fully loaded yet");
        }
    } else if ([self bufferListViewController]) {
        // Happens on iPod only
        BufferListViewController* blVc = [self bufferListViewController];
        [blVc reloadRowForBufferId:msg.bufferInfo.bufferId];
    }
}

- (void) quasselMessagesReceived:(NSArray*)messages received:(enum ReceiveStyle)style
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];

    NSLog(@"----->Messages received<--------");


    if ([self bufferViewController]) {
        BufferViewController* bvc = [self bufferViewController];
        Message *firstReceivedMessage = [messages objectAtIndex:0];
        BufferId *bufferId = firstReceivedMessage.bufferInfo.bufferId;
        NSLog(@"Messages received, currentBufferId=%@ msgBufferId=%@", [bvc currentBufferId], firstReceivedMessage.bufferInfo.bufferId);
        // Check detail view if if is relevant for this message
        if ([[bvc currentBufferId] isEqual:bufferId]) {
            [bvc addMessages:messages received:style];
            Message *msg = [messages lastObject];
            [self updateLastSeenOrBadge:msg.bufferInfo.bufferId messageId:msg.messageId];
            return;
        } else if ([bvc currentBufferId]) {
            // If not, update bufferListViewController
            BufferListViewController* blVc = [self bufferListViewController];
            [blVc reloadRowForBufferId:bufferId];
        } else {
            NSLog(@"Not updating UI, we seem not to be fully loaded yet");
        }
    } else if ([self bufferListViewController]) {
        // Happens on iPod/iPhone only
        BufferListViewController* blVc = [self bufferListViewController];
        Message *firstReceivedMessage = [messages objectAtIndex:0];
        [blVc reloadRowForBufferId:firstReceivedMessage.bufferInfo.bufferId];
    } else {
        NSLog(@"NOPE!");
    }
}
                
- (void) updateLastSeenOrBadge:(BufferId*)bufferId messageId:(MsgId*)msgId
{
    if ( [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
        [quasselCoreConnection setLastSeenMsg:msgId forBuffer:bufferId];
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:-1];
    } else {
        int unreadCount = [quasselCoreConnection computeUnreadCountForBuffer:bufferId];
        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:unreadCount];
    }
}

- (void) quasselSocketFailedConnect:(NSString*)msg
{
    [self popToLoginAndShowError:msg];
}


- (void) quasselSocketDidDisconnect:(NSString*)msg
{
    [[self bufferListViewController] quasselSocketDidDisconnect]; 
    if ([self bufferViewController]) {
        [[self bufferViewController] quasselSocketDidDisconnect];
    }
    [self popToLoginAndShowError:msg];
}

- (void) quasselLastSeenMsgUpdated:(MsgId*)messageId forBuffer:(BufferId*)bufferId
{
     [self.bufferListViewController reloadRowForBufferId:bufferId];
    
    int unreadCount = [quasselCoreConnection computeUnreadCountForBuffer:bufferId];
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:unreadCount];
}

- (void) quasselNetworkNameUpdated:(NetworkId*)networkId
{
    //[self.bufferListViewController.tableView reloadSectionIndexTitles];
//    int index = [quasselCoreConnection.neworkIdList indexOfObject:networkId];
//    NSLog(@"Network %d Index is %d", networkId.intValue, index);
//    
//    //NSIndexPath *path = self.bufferListViewController.tableView.indexPathForSelectedRow;
//    BufferId *bufferId = self.bufferViewController.currentBufferId;
//    [self.bufferListViewController.tableView reloadSections:[NSIndexSet indexSetWithIndex:index] withRowAnimation:UITableViewRowAnimationFade];
//    //[self.bufferListViewController.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
//    [self.bufferListViewController clickRowForBufferId:bufferId];
}

- (void) popToLoginAndShowError:(NSString*)errorMsg
{
    lastErrorMessage = errorMsg;
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
        UINavigationController *navigationController = [splitViewController.viewControllers lastObject];
        UIViewController *topVc = navigationController.topViewController;
        [topVc performSegueWithIdentifier:@"ShowError" sender:self];
    } else {
        UINavigationController *navigationController = (UINavigationController *)self.window.rootViewController;
        [navigationController.topViewController performSegueWithIdentifier:@"ShowError" sender:self];
        
        //NSLog(@"FIXME popToLoginAndShowError");
    }
}

- (void) doReconnectIfNecessary
{
    if (shouldAutoReconnect
        && quasselCoreConnection
        && quasselCoreConnection.socket
        && quasselCoreConnection.socket.isDisconnected
        && [UIApplication sharedApplication].applicationState == UIApplicationStateActive)
    {
        shouldAutoReconnect = NO;
        UINavigationController *navigationController = nil;
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            UISplitViewController *splitViewController = (UISplitViewController *)self.window.rootViewController;
            navigationController = [splitViewController.viewControllers lastObject];
        } else {
            navigationController = (UINavigationController *)self.window.rootViewController;
        }
        UIViewController *topVc = navigationController.topViewController;
        if ([topVc isKindOfClass:[ErrorViewController class]]) {
             ErrorViewController *evc = (ErrorViewController*)topVc;
            [evc performSelector:@selector(reConnect) withObject:nil afterDelay:0];
        }
    }
}

// iPad
- (void)splitViewController:(UISplitViewController *)svc willHideViewController:(UIViewController *)aViewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController:(UIPopoverController *)pc
{
    barButtonItem.title = @"All Chats";
    bufferListViewControllerPopoverController = pc;
    bufferListBarButtonItem = barButtonItem;
    if (self.bufferViewController) {
        [self.bufferViewController showOrHideBufferListBarButtonItem];
    }
}

// iPad
- (void)splitViewController:(UISplitViewController *)svc willShowViewController:(UIViewController *)aViewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    bufferListViewControllerPopoverController = nil;
    bufferListBarButtonItem = nil;
    if (self.bufferViewController) {
        [self.bufferViewController showOrHideBufferListBarButtonItem];
    }
}

- (void) goToPreviousBuffer
{
    if (self.bufferListViewController) {
        [self.bufferListViewController goToPreviousBuffer];
    }
}

- (void) goToNextBuffer
{
    if (self.bufferListViewController) {
        [self.bufferListViewController goToNextBuffer];
    }
}

- (void) disconnectQuasselConnection
{
    NSLog(@"AppDelegate disconnectQuasselConnection");
    [self.quasselCoreConnection disconnect];
}


+ (AppDelegate*) instance
{
    return (AppDelegate*) [[UIApplication sharedApplication] delegate];
}

@end
