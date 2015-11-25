//
//  AudioQueueCore.h
//  AudioQueueTool
//
//  Created by Ekulelu on 15/10/30.
//  Copyright © 2015年 ekulelu. All rights reserved.
//
//  This software is based on AudioStreamer by Matt Gallaher.
//  I used AudioStreamer core code to build this software, which can play local and online audio.
//  The code copy from AudioStreamer is marked by @AudioStreamer.
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



@class MGAudioQueueCore;

@protocol MGAudioQueueCoreDelegate <NSObject>
@required
- (NSData *) audioQueueCore:(MGAudioQueueCore *) audioQueueCore readDataOfLength:(long long) dataLength;
- (long long) fileLengthWithAudioQueueCore:(MGAudioQueueCore *) audioQueueCore;
- (NSString *) fileExtensionWithAudioQueueCore:(MGAudioQueueCore *) audioQueueCore;
- (double) seekTimeWithAudioQueueCore:(MGAudioQueueCore *) audioQueueCore;
- (BOOL) isFinishPlayWithAudioQueueCore:(MGAudioQueueCore *) audioQueueCore;
@end


@interface MGAudioQueueCore : NSObject
#define LOG_QUEUED_BUFFERS 0

//@AudioStreamer
#define kNumAQBufs 16			// Number of audio queue buffers we allocate.
// Needs to be big enough to keep audio pipeline
// busy (non-zero number of queued buffers) but
// not so big that audio takes too long to begin
// (kNumAQBufs * kAQBufSize of data must be
// loaded before playback will start).
//
// Set LOG_QUEUED_BUFFERS to 1 to log how many
// buffers are queued at any time -- if it drops
// to zero too often, this value may need to
// increase. Min 3, typical 8-24.
//@AudioStreamer
#define kAQDefaultBufSize 2048	// Number of bytes in each audio queue buffer
// Needs to be big enough to hold a packet of
// audio from the audio file. If number is too
// large, queuing of audio before playback starts
// will take too long.
// Highly compressed files can use smaller
// numbers (512 or less). 2048 should hold all
// but the largest packets. A buffer size error
// will occur if this number is too small.
//@AudioStreamer
#define kAQMaxPacketDescs 512	// Number of packet descriptions in our array
//@AudioStreamer
typedef enum
{
    AS_INITIALIZED = 0,
    AS_STARTING_FILE_THREAD,
    AS_WAITING_FOR_DATA,
    AS_FLUSHING_EOF,
    AS_WAITING_FOR_QUEUE_TO_START,
    AS_PLAYING,
    AS_BUFFERING,
    AS_STOPPING,
    AS_STOPPED,
    AS_PAUSED
} AudioStreamerState;
//@AudioStreamer
typedef enum
{
    AS_NO_STOP = 0,
    AS_STOPPING_EOF,
    AS_STOPPING_USER_ACTION,
    AS_STOPPING_ERROR,
    AS_STOPPING_TEMPORARILY
} AudioStreamerStopReason;
//@AudioStreamer
typedef enum
{
    AS_NO_ERROR = 0,
    AS_NETWORK_CONNECTION_FAILED,
    AS_FILE_STREAM_GET_PROPERTY_FAILED,
    AS_FILE_STREAM_SET_PROPERTY_FAILED,
    AS_FILE_STREAM_SEEK_FAILED,
    AS_FILE_STREAM_PARSE_BYTES_FAILED,
    AS_FILE_STREAM_OPEN_FAILED,
    AS_FILE_STREAM_CLOSE_FAILED,
    AS_AUDIO_DATA_NOT_FOUND,
    AS_AUDIO_QUEUE_CREATION_FAILED,
    AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED,
    AS_AUDIO_QUEUE_ENQUEUE_FAILED,
    AS_AUDIO_QUEUE_ADD_LISTENER_FAILED,
    AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED,
    AS_AUDIO_QUEUE_START_FAILED,
    AS_AUDIO_QUEUE_PAUSE_FAILED,
    AS_AUDIO_QUEUE_BUFFER_MISMATCH,
    AS_AUDIO_QUEUE_DISPOSE_FAILED,
    AS_AUDIO_QUEUE_STOP_FAILED,
    AS_AUDIO_QUEUE_FLUSH_FAILED,
    AS_AUDIO_STREAMER_FAILED,
    AS_GET_AUDIO_TIME_FAILED,
    AS_AUDIO_BUFFER_TOO_SMALL
} AudioStreamerErrorCode;

typedef struct {
    double exactSeekTime;
    long long seekByteOffset;
    BOOL isShouldSeek;
} AudioQueueCoreSeekTime;

@property (nonatomic) BOOL shouldDisplayAlertOnError; // to control whether the alert is displayed in failWithErrorCode
@property (readonly) AudioStreamerState state;

@property (readonly, assign) double playProgress;
@property (readonly, assign) double duration;
//@property (nonatomic, assign) double seekTime;
@property (nonatomic, weak) id<MGAudioQueueCoreDelegate> delegate;
 //In AudioQueueCoreDelegate, you should set the fileLength before you call this method. Or maybe can not return the right duration
- (void)startAudioPlay;
- (AudioQueueCoreSeekTime)shouldSeekToTime:(double)requestSeekTime;
- (void)pause;
- (void)stop;
- (BOOL)isPlaying;
- (BOOL)isPaused;
- (BOOL)isIdle;
- (BOOL)isFinishPlayingSuccessfully;
@end
