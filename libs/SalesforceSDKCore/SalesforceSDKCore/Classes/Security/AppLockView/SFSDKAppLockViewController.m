/*
 SFSDKAppLockViewController.m
 SalesforceSDKCore
 
 Copyright (c) 2018-present, salesforce.com, inc. All rights reserved.
 
 Redistribution and use of this software in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of
 conditions and the following disclaimer in the documentation and/or other materials provided
 with the distribution.
 * Neither the name of salesforce.com, inc. nor the names of its contributors may be used to
 endorse or promote products derived from this software without specific prior written
 permission of salesforce.com, inc.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "SFSDKAppLockViewController.h"
#import "SFSDKPasscodeCreateController.h"
#import "SFSDKPasscodeVerifyController.h"
#import "SFPasscodeManager.h"
#import "SFSDKBiometricViewController+Internal.h"
#import "SFSDKAppLockViewConfig.h"
#import "SFSDKResourceUtils.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import "SFSDKWindowManager.h"
#import "SFSecurityLockout.h"

NSNotificationName AppLockViewShouldUnlockNotification       = @"AppLockViewShouldUnlockNotification";
NSNotificationName AppLockViewShouldAllowBiometricUnlock     = @"AppLockViewShouldAllowBiometricUnlock";

@interface SFSDKAppLockViewController () <SFSDKPasscodeCreateDelegate,SFSDKBiometricViewDelegate,SFSDKPasscodeVerifyDelegate>

/**
 Setup passcode view related preferences.
 */
@property (nonatomic, readonly) SFSDKAppLockViewConfig *viewConfig;

@end

@implementation SFSDKAppLockViewController

- (instancetype)initWithMode:(SFAppLockControllerMode)mode andViewConfig:(SFSDKAppLockViewConfig *)config
{
    _viewConfig = config;
    UIViewController *controller = [self controllerFromMode:mode andViewConfig:config];
    self = [super initWithRootViewController:controller];
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self setupNavBar];
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

- (void)setupNavBar
{
    [self.navigationController.view setBackgroundColor:[UIColor clearColor]];
    self.navigationController.navigationBar.backgroundColor = self.viewConfig.navBarColor;
    self.navigationController.navigationBar.tintColor = self.viewConfig.navBarColor;
    self.navigationBar.translucent = NO;
    self.navigationController.navigationBar.titleTextAttributes =
        @{NSForegroundColorAttributeName : self.viewConfig.navBarTextColor,
                     NSFontAttributeName : self.viewConfig.navBarFont};
}

#pragma mark - SFSDKPasscodeCreateDelegate

- (void)passcodeCreated:(NSString *)passcode updateMode:(BOOL)isUpdateMode
{
    [[SFPasscodeManager sharedManager] changePasscode:passcode];
    if ([SFSecurityLockout biometricState] == SFBiometricUnlockAvailable) {
        [self promptBiometricEnrollment];
    } else {
        SFSecurityLockoutAction action = isUpdateMode ? SFSecurityLockoutActionPasscodeChanged : SFSecurityLockoutActionPasscodeCreated;
        [self.navigationController popViewControllerAnimated:NO];
        [self fireUnlockNotification:YES action:action];
    }
}

#pragma mark - SFSDKPasscodeVerifyDelegate

- (void)passcodeVerified
{
    if ([SFSecurityLockout biometricState] == SFBiometricUnlockAvailable) {
        [self promptBiometricEnrollment];
    } else {
        [self.navigationController popViewControllerAnimated:NO];
        [self fireUnlockNotification:YES action:SFSecurityLockoutActionPasscodeVerified];
    }
}

- (void)passcodeFailed
{
    [[SFPasscodeManager sharedManager] resetPasscode];
    [self fireUnlockNotification:NO  action:SFSecurityLockoutActionNone];
}

#pragma mark - SFSDKBiometricViewDelegate

- (void)biometricUnlockSucceeded:(BOOL)isVerificationMode
{
    [self fireBiometricAllowedNotification:YES];
    
    if ([SFSecurityLockout locked]) {
        [self.navigationController popViewControllerAnimated:NO];
        [self fireUnlockNotification:YES  action:SFSecurityLockoutActionBiometricVerified];
    } else {
        [self dismissStandaloneBiometricSetup];
    }
}

- (void)biometricUnlockFailed:(BOOL)isVerificationMode
{
    if (isVerificationMode) {
        [self.navigationController popViewControllerAnimated:NO];
        SFSDKPasscodeVerifyController *pvc = [[SFSDKPasscodeVerifyController alloc] initWithViewConfig:self.viewConfig];
        pvc.verifyDelegate = self;
        [self pushViewController:pvc animated:NO];
    } else {
        [self fireBiometricAllowedNotification:NO];
       
        if ([SFSecurityLockout locked]) {
            [self.navigationController popViewControllerAnimated:NO];
            [self fireUnlockNotification:YES  action:SFSecurityLockoutActionPasscodeCreated];
        } else {
            [self dismissStandaloneBiometricSetup];
        }
    }
}

- (void)dismissStandaloneBiometricSetup
{
    [SFSecurityLockout setupTimer];
    [[[SFSDKWindowManager sharedManager] passcodeWindow].viewController dismissViewControllerAnimated:NO completion:^{
        [[SFSDKWindowManager sharedManager].passcodeWindow dismissWindowAnimated:NO withCompletion:^{}];
    }];
}

-(UIViewController *)controllerFromMode:(SFAppLockControllerMode)mode andViewConfig:(SFSDKAppLockViewConfig *)viewConfig
{
    UIViewController *currentViewController = nil;
    SFSDKBiometricViewController *bvc = nil;
    SFSDKPasscodeCreateController *pcvc = nil;
    SFSDKPasscodeVerifyController *pvc = nil;
    
    switch (mode) {
        case SFAppLockControllerModeEnableBiometric:
        case SFAppLockControllerModeVerifyBiometric:
            bvc = [[SFSDKBiometricViewController alloc] initWithViewConfig:viewConfig];
            bvc.biometricResponseDelgate = self;
            bvc.verificationMode = (mode == SFAppLockControllerModeVerifyBiometric);
            currentViewController = bvc;
            break;
        case SFAppLockControllerModeCreatePasscode:
        case SFAppLockControllerModeChangePasscode:
            pcvc = [[SFSDKPasscodeCreateController alloc] initWithViewConfig:viewConfig];
            pcvc.createDelegate = self;
            pcvc.updateMode = (mode == SFAppLockControllerModeChangePasscode);
            currentViewController = pcvc;
            break;
        default:
            pvc = [[SFSDKPasscodeVerifyController alloc] initWithViewConfig:viewConfig];
            pvc.verifyDelegate = self;
            currentViewController = pvc;
            break;
    }
    
    return currentViewController;
}

#pragma mark - private methods

- (void)promptBiometricEnrollment
{
    SFSDKBiometricViewController *pvc = [[SFSDKBiometricViewController alloc] initWithViewConfig:self.viewConfig];
    pvc.biometricResponseDelgate = self;
    [self pushViewController:pvc animated:NO];
}

- (void)fireBiometricAllowedNotification:(BOOL)allowed
{
    NSDictionary *userInfo = @{@"userAllowedBiometric": [NSNumber numberWithBool:allowed]};
    [[NSNotificationCenter defaultCenter] postNotificationName:AppLockViewShouldAllowBiometricUnlock object:self userInfo:userInfo];
}

- (void)fireUnlockNotification:(BOOL)success action:(SFSecurityLockoutAction)lockoutAction {
    NSDictionary *userInfo = @{@"success": [NSNumber numberWithBool:success], @"action": [NSNumber numberWithInt:lockoutAction]};
    [[NSNotificationCenter defaultCenter] postNotificationName:AppLockViewShouldUnlockNotification object:self userInfo:userInfo];
}

@end
