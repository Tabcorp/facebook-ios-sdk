// Copyright (c) 2014-present, Facebook, Inc. All rights reserved.
//
// You are hereby granted a non-exclusive, worldwide, royalty-free license to use,
// copy, modify, and distribute this software in source code or binary form for use
// in connection with the web services and APIs provided by Facebook.
//
// As with any software that integrates with the Facebook platform, your use of
// this software is subject to the Facebook Developer Principles and Policies
// [http://developers.facebook.com/policy/]. This copyright notice shall be
// included in all copies or substantial portions of the software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import "FBSDKApplicationDelegate.h"
#import "FBSDKApplicationDelegate+Internal.h"

#import <objc/runtime.h>

#import "FBSDKAppEvents+Internal.h"
#import "FBSDKConstants.h"
#import "FBSDKDynamicFrameworkLoader.h"
#import "FBSDKError.h"
#import "FBSDKInternalUtility.h"
#import "FBSDKLogger.h"
#import "FBSDKServerConfiguration.h"
#import "FBSDKServerConfigurationManager.h"
#import "FBSDKSettings+Internal.h"
#import "FBSDKTimeSpentData.h"
#import "FBSDKUtility.h"

NSString *const FBSDKApplicationDidBecomeActiveNotification = @"com.facebook.sdk.FBSDKApplicationDidBecomeActiveNotification";

static NSString *const FBSDKAppLinkInboundEvent = @"fb_al_inbound";

@implementation FBSDKApplicationDelegate

#pragma mark - Class Methods

+ (void)load
{
  // when the app becomes active by any means,  kick off the initialization.
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(initializeWithLaunchData:)
                                               name:UIApplicationDidFinishLaunchingNotification
                                             object:nil];
}

// Initialize SDK listeners
// Don't call this function in any place else. It should only be called when the class is loaded.
+ (void)initializeWithLaunchData:(NSNotification *)note
{
  NSDictionary *launchData = note.userInfo;
  // Set the SourceApplication for time spent data. This is not going to update the value if the app has already launched.
  [FBSDKTimeSpentData setSourceApplication:launchData[UIApplicationLaunchOptionsSourceApplicationKey]
                                   openURL:launchData[UIApplicationLaunchOptionsURLKey]];
  // Register on UIApplicationDidEnterBackgroundNotification events to reset source application data when app backgrounds.
  [FBSDKTimeSpentData registerAutoResetSourceApplication];

  [FBSDKInternalUtility validateFacebookReservedURLSchemes];

  // Remove the observer
  [[NSNotificationCenter defaultCenter] removeObserver:self];

}

+ (instancetype)sharedInstance
{
  static FBSDKApplicationDelegate *_sharedInstance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    _sharedInstance = [[self alloc] _init];
  });
  return _sharedInstance;
}

#pragma mark - Object Lifecycle

- (instancetype)_init
{
  if ((self = [super init]) != nil) {
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    [defaultCenter addObserver:self selector:@selector(applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];

    [[FBSDKAppEvents singleton] registerNotifications];
  }
  return self;
}

- (instancetype)init
{
  return nil;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UIApplicationDelegate

#if __IPHONE_OS_VERSION_MAX_ALLOWED > __IPHONE_9_0
- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options
{
  return [self application:application
                   openURL:url
         sourceApplication:options[UIApplicationOpenURLOptionsSourceApplicationKey]
                annotation:options[UIApplicationOpenURLOptionsAnnotationKey]];
}
#endif

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
  sourceApplication:(NSString *)sourceApplication
         annotation:(id)annotation
{
  if (sourceApplication != nil && ![sourceApplication isKindOfClass:[NSString class]]) {
    @throw [NSException exceptionWithName:NSInvalidArgumentException
                                   reason:@"Expected 'sourceApplication' to be NSString. Please verify you are passing in 'sourceApplication' from your app delegate (not the UIApplication* parameter). If your app delegate implements iOS 9's application:openURL:options:, you should pass in options[UIApplicationOpenURLOptionsSourceApplicationKey]. "
                                 userInfo:nil];
  }
  [FBSDKTimeSpentData setSourceApplication:sourceApplication openURL:url];

  return NO;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  FBSDKAccessToken *cachedToken = [[FBSDKSettings accessTokenCache] fetchAccessToken];
  [FBSDKAccessToken setCurrentAccessToken:cachedToken];
  // fetch app settings
  [FBSDKServerConfigurationManager loadServerConfigurationWithCompletionBlock:NULL];

  if ([[FBSDKSettings autoLogAppEventsEnabled] boolValue]) {
    [self _logSDKInitialize];
  }
  return NO;
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
  // Auto log basic events in case autoLogAppEventsEnabled is set
  if ([[FBSDKSettings autoLogAppEventsEnabled] boolValue]) {
    [FBSDKAppEvents activateApp];
  }
  [[NSNotificationCenter defaultCenter] postNotificationName:FBSDKApplicationDidBecomeActiveNotification object:self];
}

#pragma mark - Helper Methods

- (void)_logSDKInitialize
{
  NSMutableDictionary *params = [NSMutableDictionary new];
  [params setObject:@1 forKey:@"core_lib_included"];
  if (objc_lookUpClass("FBSDKShareDialog") != nil) {
    [params setObject:@1 forKey:@"share_lib_included"];
  }
  if (objc_lookUpClass("FBSDKLoginManager") != nil) {
    [params setObject:@1 forKey:@"login_lib_included"];
  }
  if (objc_lookUpClass("FBSDKPlacesManager") != nil) {
    [params setObject:@1 forKey:@"places_lib_included"];
  }
  if (objc_lookUpClass("FBSDKMessengerButton") != nil) {
    [params setObject:@1 forKey:@"messenger_lib_included"];
  }
  if (objc_lookUpClass("FBSDKMessengerButton") != nil) {
    [params setObject:@1 forKey:@"messenger_lib_included"];
  }
  if (objc_lookUpClass("FBSDKTVInterfaceFactory.m") != nil) {
    [params setObject:@1 forKey:@"tv_lib_included"];
  }
  if (objc_lookUpClass("FBSDKAutoLog") != nil) {
    [params setObject:@1 forKey:@"marketing_lib_included"];
  }
  [FBSDKAppEvents logEvent:@"fb_sdk_initialize" parameters:params];
}

@end
