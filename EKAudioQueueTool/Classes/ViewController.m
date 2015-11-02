//
//  ViewController.m
//  AudioQueueTool
//
//  Created by 黄政 on 15/10/26.
//  Copyright © 2015年 ekulelu. All rights reserved.
//

#import "ViewController.h"
#import "EKAudioQueueTool.h"

#define DocumentPath NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject
#define CachePath NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject
@interface ViewController ()
@property (nonatomic, strong) EKAudioQueueTool* audioTool;
@property (weak, nonatomic) IBOutlet UIProgressView *progressView;
@property (weak, nonatomic) IBOutlet UIButton *pauseBtn;
@property (weak, nonatomic) IBOutlet UIButton *stopBtn;
@property (weak, nonatomic) IBOutlet UITextField *seekTimeTextField;
@property (weak, nonatomic) IBOutlet UIButton *seekTimeBtn;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *waitingDataIndicator;
@property (weak, nonatomic) IBOutlet UISlider *slider;
@property (weak, nonatomic) IBOutlet UITextField *urlTextField;

@property (weak, nonatomic) IBOutlet UILabel *timeLabel;
@property (weak, nonatomic) IBOutlet UIProgressView *downloadProgressView;
@property (nonatomic, strong) NSTimer* timer;
@property (nonatomic, strong) NSURL* url;
@property (nonatomic, assign) BOOL touchDownFlag;
@end

@implementation ViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    self.waitingDataIndicator.hidden = YES;
    self.seekTimeBtn.enabled = NO;
    self.pauseBtn.enabled = NO;
    self.stopBtn.enabled = NO;
    
   
//    self.url = [NSURL URLWithString:@"http://mp3.haoduoge.com/music6/2015-10-25/1445767187.mp3"];

//       self.url = [NSURL URLWithString:@"http://mp3.haoduoge.com/music6/2015-10-25/1445767187.mp3"];
    
    //10.2M
    self.url = [NSURL URLWithString:@"http://sc1.111ttt.com/2015/1/11/02/104020653295.mp3"];
    
    self.audioTool = [[EKAudioQueueTool alloc] init];

}

-(void) startTimer {
    if (self.timer != nil) {
        [self releaseTimer];
    }
    self.timer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(showPregress) userInfo:nil repeats:YES];
    self.seekTimeBtn.enabled = YES;
    self.pauseBtn.enabled = YES;
    self.stopBtn.enabled = YES;
    self.touchDownFlag = NO;
    self.pauseBtn.titleLabel.text = @"Pause";
}

-(void) showPregress{
    double progress = self.audioTool.playProgress;
    double duration = self.audioTool.duration;
    BOOL isWaitingData = [self.audioTool isWaitData];
    if (duration >= progress && duration != 0) {
        self.timeLabel.text = [NSString stringWithFormat:@"%d/%d s", (int) progress, (int) duration];
        self.progressView.progress = progress / duration;
        if (!self.touchDownFlag && [self.audioTool isPlaying]) {
            self.slider.value = progress / duration;
        }
    }
    double downloadPercent = self.audioTool.downLoadPercent;
    self.downloadProgressView.progress = downloadPercent;
    if (downloadPercent >= 1 && [self.audioTool isPaused]) {
        [self.timer setFireDate:[NSDate distantFuture]];
    }
    if (isWaitingData) {
        [self.waitingDataIndicator startAnimating];
        self.waitingDataIndicator.hidden = NO;
    } else {
        [self.waitingDataIndicator stopAnimating];
        self.waitingDataIndicator.hidden = YES;
    }
    if ([self.audioTool isFinishPlaySuccessfully]) {
        NSLog(@"finish play successfully");
        [self releaseTimer];
    }
}
-(void) releaseTimer {
    if (self.timer == nil) {
        return;
    }
    [self.timer invalidate];
    self.timer = nil;
    self.waitingDataIndicator.hidden = YES;
    NSLog(@"release timer");
}
- (IBAction)localAudioBtnClicked:(id)sender {
    
    NSString* mp3Path = [DocumentPath stringByAppendingPathComponent:@"3.mp3"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
#warning give a local audio and delete this alertController
    if (![fileManager fileExistsAtPath:mp3Path]) {
        NSString *message = @"Please give a local audio in the source code";
        [self alertWithMessage:message];
        return;
    }
   
    
    [self.audioTool playLocalAudioWithFilePath:mp3Path];
    [self startTimer];
}
- (IBAction)onlineAudioBtnClicked:(id)sender {
    NSString *urlString = self.urlTextField.text;
    if (urlString == nil || urlString.length == 0) {
        [self alertWithMessage:@"url is null and try to play the default url"];
    } else {
        self.url = [NSURL URLWithString:urlString];
    }
    
    [self.audioTool playOnlineAudioWithURL:self.url];
    [self startTimer];
}


- (IBAction)pauseClicked:(id)sender {
    if ([self.audioTool isIdle]) {
        return;
    }
    if([self.audioTool isPaused] && self.timer.isValid) { //resume timer
        [self.timer setFireDate:[NSDate distantPast]];
        [self.pauseBtn setTitle:@"Pause" forState:UIControlStateNormal];
    } else {
        if (self.audioTool.downLoadPercent >= 1) {
            [self.timer setFireDate:[NSDate distantFuture]]; // pause timer
        }
        [self.pauseBtn setTitle:@"Continue" forState:UIControlStateNormal];
    }
    [self.audioTool pause];
}

- (IBAction)stopClicked:(id)sender {
    if ([self.audioTool isIdle]) {
        return;
    }
    [self releaseTimer];
    [self.pauseBtn setTitle:@"Pause" forState:UIControlStateNormal];
    self.progressView.progress = 0;
    self.seekTimeBtn.enabled = NO;
    self.pauseBtn.enabled = NO;
    self.stopBtn.enabled = NO;
    self.slider.value = 0;
    [self.audioTool stop];
    if (self.audioTool.downLoadPercent < 1) {
        self.downloadProgressView.progress = 0;
    }
}

- (IBAction)seekTimeBtnClicked:(id)sender {
    [self.audioTool seekTime: self.seekTimeTextField.text.doubleValue];
    self.pauseBtn.titleLabel.text = @"Pause";
}

- (IBAction)sliderTouchupInside:(UISlider *)slider {
    double seekTimeInSecond = self.audioTool.duration * slider.value;
//    [self.timer setFireDate:[NSDate distantFuture]];
    [self.audioTool seekTime:seekTimeInSecond];
//    [self.timer setFireDate:[NSDate distantPast]];
    self.touchDownFlag = NO;
}

- (IBAction)sliderTouchDown:(id)sender {
    self.touchDownFlag = YES;
}



-(void)viewDidDisappear:(BOOL)animated{
    [self releaseTimer];
    [super viewDidDisappear:animated];
}


- (void) alertWithMessage:(NSString *) message {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Alert" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *action = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alertController addAction:action];
    [self presentViewController:alertController animated:YES completion:nil];
}
@end
