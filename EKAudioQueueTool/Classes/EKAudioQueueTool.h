//
//  AudioQueueTool.h
//  AudioQueueTool
//
//  Created by ekulelu on 15/10/26.
//  Copyright © 2015年 ekulelu. All rights reserved.
//
//  This software is based on AudioStreamer by Matt Gallaher.
//  I used AudioStreamer core code to build this software, which can play local and online audio.
//  The code copy from AudioStreamer is marked by @AudioStreamer.
//  To Matt: if this software violate your right, please contact me, and I will remove it form github.
//  This software is free for used, subject to the restrictions as AudioStreamer's:
//
//
//  Below is AudioStreamer's copyright notice.
//
//
//  AudioStreamer.h
//  StreamingAudioPlayer
//
//  Created by Matt Gallagher on 27/09/08.
//  Copyright 2008 Matt Gallagher. All rights reserved.
//
//  This software is provided 'as-is', without any express or implied
//  warranty. In no event will the authors be held liable for any damages
//  arising from the use of this software. Permission is granted to anyone to
//  use this software for any purpose, including commercial applications, and to
//  alter it and redistribute it freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source
//     distribution.

#import <Foundation/Foundation.h>


@interface EKAudioQueueTool : NSObject


@property (assign) double downLoadPercent;
@property (readonly, assign) double playProgress;
@property (readonly, assign) double duration;
@property (nonatomic, readonly, assign) long long fileLength; // Length of the file in bytes
@property (nonatomic, assign, readonly, getter=isWaitData) BOOL waitingData;
@property (nonatomic, assign) BOOL cacheEnable;

- (instancetype)init;

- (instancetype)initWithCacheEnable:(BOOL) cacheEnable;
- (void)cleanCache;
//play local audio
- (void)playLocalAudioWithFilePath: (NSString*) filePath;
//play online audio
- (void)playOnlineAudioWithURL:(NSURL*) URL;
//seekTime: should not be call before start play an audio
- (void)seekTime:(double) requestSeekTime;
- (void)playOnlineAudioWithURL:(NSURL*) URL seekTime:(double) seektime;
- (void)cancelDownload;
- (void)pause;
- (void)stop;
- (BOOL)isPlaying;
- (BOOL)isPaused;
- (BOOL)isIdle;
- (BOOL)isFinishPlaySuccessfully;
@end
