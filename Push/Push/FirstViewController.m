//
//  FirstViewController.m
//  Push
//
//  Created by Jordan Zucker on 10/13/15.
//  Copyright © 2015 pubnub. All rights reserved.
//

#import "FirstViewController.h"
#import "AppDelegate.h"
#import <PubNub/PubNub.h>

@interface FirstViewController ()
@property (nonatomic, strong) PubNub *client;
@property (nonatomic, weak) IBOutlet UIButton *publishButton;
@end

@implementation FirstViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    self.client = [(AppDelegate *)[UIApplication sharedApplication].delegate client];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)buttonTapped:(id)sender {
    [self.client publish:@"chaaaaaaarge!!!!!" toChannel:@"teddyr" mobilePushPayload:@{@"aps": @{@"content-available": @1}} withCompletion:^(PNPublishStatus *status) {
        NSLog(@"status: %@", status);
    }];
}

@end
