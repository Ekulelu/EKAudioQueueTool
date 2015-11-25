//
//  AudioQueueCore.m
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

#import "MGAudioQueueCore.h"
#include <AudioToolbox/AudioToolbox.h>
#import <UIKit/UIKit.h>
#include <pthread.h>
#import "EKAudioQueueToolHeader.h"

//@AudioStreamer
#define BitRateEstimationMaxPackets 5000
#define BitRateEstimationMinPackets 50


NSString * const ASStatusChangedNotification = @"ASStatusChangedNotification";
NSString * const ASAudioSessionInterruptionOccuredNotification = @"ASAudioSessionInterruptionOccuredNotification";

NSString * const AS_NO_ERROR_STRING = @"No error.";
NSString * const AS_FILE_STREAM_GET_PROPERTY_FAILED_STRING = @"File stream get property failed.";
NSString * const AS_FILE_STREAM_SEEK_FAILED_STRING = @"File stream seek failed.";
NSString * const AS_FILE_STREAM_PARSE_BYTES_FAILED_STRING = @"Parse bytes failed.";
NSString * const AS_FILE_STREAM_OPEN_FAILED_STRING = @"Open audio file stream failed.";
NSString * const AS_FILE_STREAM_CLOSE_FAILED_STRING = @"Close audio file stream failed.";
NSString * const AS_AUDIO_QUEUE_CREATION_FAILED_STRING = @"Audio queue creation failed.";
NSString * const AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED_STRING = @"Audio buffer allocation failed.";
NSString * const AS_AUDIO_QUEUE_ENQUEUE_FAILED_STRING = @"Queueing of audio buffer failed.";
NSString * const AS_AUDIO_QUEUE_ADD_LISTENER_FAILED_STRING = @"Audio queue add listener failed.";
NSString * const AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED_STRING = @"Audio queue remove listener failed.";
NSString * const AS_AUDIO_QUEUE_START_FAILED_STRING = @"Audio queue start failed.";
NSString * const AS_AUDIO_QUEUE_BUFFER_MISMATCH_STRING = @"Audio queue buffers don't match.";
NSString * const AS_AUDIO_QUEUE_DISPOSE_FAILED_STRING = @"Audio queue dispose failed.";
NSString * const AS_AUDIO_QUEUE_PAUSE_FAILED_STRING = @"Audio queue pause failed.";
NSString * const AS_AUDIO_QUEUE_STOP_FAILED_STRING = @"Audio queue stop failed.";
NSString * const AS_AUDIO_DATA_NOT_FOUND_STRING = @"No audio data found.";
NSString * const AS_AUDIO_QUEUE_FLUSH_FAILED_STRING = @"Audio queue flush failed.";
NSString * const AS_GET_AUDIO_TIME_FAILED_STRING = @"Audio queue get current time failed.";
NSString * const AS_AUDIO_STREAMER_FAILED_STRING = @"Audio playback failed";
NSString * const AS_NETWORK_CONNECTION_FAILED_STRING = @"Network connection failed";
NSString * const AS_AUDIO_BUFFER_TOO_SMALL_STRING = @"Audio packets are larger than kAQDefaultBufSize.";


@interface MGAudioQueueCore()
{
    
    //@AudioStreamer
    AudioQueueRef audioQueue;
    AudioFileStreamID audioFileStream;	// the audio file stream parser
    AudioStreamBasicDescription asbd;	// description of the audio
    
    AudioQueueBufferRef audioQueueBuffer[kNumAQBufs];		// audio queue buffers
    AudioStreamPacketDescription packetDescs[kAQMaxPacketDescs];	// packet descriptions for enqueuing audio
    unsigned int fillBufferIndex;	// the index of the audioQueueBuffer that is being filled
    UInt32 packetBufferSize;
    size_t bytesFilled;				// how many bytes have been filled
    size_t packetsFilled;			// how many packets have been filled
    bool inuse[kNumAQBufs];			// flags to indicate that a buffer is still in use
    NSInteger buffersUsed;
    
    
    pthread_mutex_t queueBuffersMutex;			// a mutex to protect the inuse flags
    pthread_cond_t queueBufferReadyCondition;	// a condition varable for handling the inuse flags
    
    AudioStreamerState state;
    AudioStreamerState laststate;
    AudioStreamerStopReason stopReason;
    AudioStreamerErrorCode errorCode;
    OSStatus err;
    
    bool discontinuous;			// flag to indicate middle of the stream
    
    NSNotificationCenter *notificationCenter;
    
    UInt32 bitRate;				// Bits per second in the file
    NSInteger dataOffset;		// Offset of the first audio packet in the stream
    

    UInt64 audioDataByteCount;  // Used when the actual number of audio bytes in
                                // the file is known (more accurate than assuming
                                // the whole file is audio)
    
    UInt64 processedPacketsCount;		// number of packets accumulated for bitrate estimation
    UInt64 processedPacketsSizeTotal;	// byte size of accumulated estimation packets
    
    double sampleRate;			// Sample rate of the file (used to compare with
                                // samples played by the queue for current playback
                                // time)
    double packetDuration;		// sample rate times frames per packet
    double lastProgress;		// last calculated progress point
    double _duration;
}



@property (nonatomic, copy) NSString *fileExtension;
@property (nonatomic, assign) long long fileLength; // Length of the file in bytes
@property (nonatomic, strong) NSOperationQueue* threadQueue;
@property (nonatomic, strong) NSOperationQueue* netWorkthreadQueue;
@property (nonatomic, assign) BOOL isLocalAudio;
@property (nonatomic, copy) NSString* tempFileSaveFolder;
@property (nonatomic, assign) long long currentReadLength;
 
@end


@implementation MGAudioQueueCore

#pragma mark - AudioQueue

-(void) startAudioPlay {
    
    [self setupInitParams];
    
    [self setupAudioSeesion];
    
    //Create AudioFileStream
    [self createAudioFileStream];
    
    state = AS_WAITING_FOR_DATA;
    
    [self setupAudioRunLoop];
}

-(void) setupInitParams {
    @synchronized(self) {
        if (audioFileStream != nil || audioQueue != nil) {
            [self stop];
        }
        _duration = 0;
        _fileLength = 0;
        _fileExtension = nil;
        self.currentReadLength = 0;
        stopReason = 0;
        err = 0;
        bitRate = 0;
        processedPacketsCount = 0;
        processedPacketsSizeTotal = 0;
        packetDuration = 0;
        audioDataByteCount = 0;
        [self.threadQueue cancelAllOperations];
        self.threadQueue = [[NSOperationQueue alloc] init];
        self.threadQueue.maxConcurrentOperationCount = 1;
    }
    
}

- (long long) fileLength {
    if (_fileLength <= 0 && [self.delegate respondsToSelector:@selector(fileLengthWithAudioQueueCore:)]) {
        _fileLength = [self.delegate fileLengthWithAudioQueueCore:self];
    }
    return _fileLength;
}

- (NSString *) fileExtension {
    if (_fileExtension == nil && [self.delegate respondsToSelector:@selector(fileExtensionWithAudioQueueCore:)]) {
        _fileExtension = [self.delegate fileExtensionWithAudioQueueCore:self];
    }
    return _fileExtension;
}

// shouldSeekToTime:
// if there isn't playing, can not seektime, so if you want to seek time, you should call the method after starting playing audio 
// if can seekTime, return the exact seekTime and seekByteOffset.
//
- (AudioQueueCoreSeekTime )shouldSeekToTime:(double)requestSeekTime
{
    AudioQueueCoreSeekTime seekTimeS;
    if ([self calculatedBitRate] == 0.0 || _fileLength <= 0)
    {
        return seekTimeS;
    }
    
    //
    // Calculate the byte offset for seeking
    //
    NSInteger seekByteOffset = dataOffset +
    (requestSeekTime / self.duration) * (_fileLength - dataOffset);
    
    //
    // Attempt to leave 1 useful packet at the end of the file (although in
    // reality, this may still seek too far if the file has a long trailer).
    //
    if (seekByteOffset > _fileLength - 2 * packetBufferSize)
    {
        seekByteOffset = _fileLength - 2 * packetBufferSize;
    }
    
    //
    // Store the old time from the audio queue and the time that we're seeking
    // to so that we'll know the correct time progress after seeking.
    //
    double seekTime = requestSeekTime;
    
    //
    // Attempt to align the seek with a packet boundary
    //
    double calculatedBitRate = [self calculatedBitRate];
    if (packetDuration > 0 &&
        calculatedBitRate > 0)
    {
        UInt32 ioFlags = 0;
        SInt64 packetAlignedByteOffset;
        SInt64 seekPacket = floor(requestSeekTime / packetDuration);
        err = AudioFileStreamSeek(audioFileStream, seekPacket, &packetAlignedByteOffset, &ioFlags);
        if (!err && !(ioFlags & kAudioFileStreamSeekFlag_OffsetIsEstimated))
        {
            seekTime -= ((seekByteOffset - dataOffset) - packetAlignedByteOffset) * 8.0 / calculatedBitRate;
            seekByteOffset = packetAlignedByteOffset + dataOffset;
        }
    }

    seekTimeS.isShouldSeek = true;
    seekTimeS.seekByteOffset = seekByteOffset;
    seekTimeS.exactSeekTime = seekTime;
    return seekTimeS;
}


// @AudioStreamer
// setupAudioSeesion
-(void) setupAudioSeesion {
    @synchronized(self)
    {
#if TARGET_OS_IPHONE
        //
        // Set the audio session category so that we continue to play if the
        // iPhone/iPod auto-locks.
        //
        AudioSessionInitialize (
                                NULL,                          // 'NULL' to use the default (main) run loop
                                NULL,                          // 'NULL' to use the default run loop mode
                                ASAudioSessionInterruptionListener,  // a reference to your interruption callback
                                (__bridge void *)(self)                       // data to pass to your interruption listener callback
                                );
        UInt32 sessionCategory = kAudioSessionCategory_MediaPlayback;
        AudioSessionSetProperty (
                                 kAudioSessionProperty_AudioCategory,
                                 sizeof (sessionCategory),
                                 &sessionCategory
                                 );
        AudioSessionSetActive(true);
#endif
        // initialize a mutex and condition so that we can block on buffers in use.
        pthread_mutex_init(&queueBuffersMutex, NULL);
        pthread_cond_init(&queueBufferReadyCondition, NULL);
    }
    self.state = AS_INITIALIZED;
}

-(void) setupAudioRunLoop {
    NSBlockOperation *op = [NSBlockOperation blockOperationWithBlock:^{
        //
        // Process the run loop until playback is finished or failed.
        //
        BOOL isRunning = YES;
        do
        {
            //            isRunning = [[NSRunLoop currentRunLoop]
            //                         runMode:NSDefaultRunLoopMode
            //                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
            
            //            @synchronized(self) {
            //                if (seekWasRequested) {
            //                    [self internalSeekToTime:requestedSeekTime];
            //                    seekWasRequested = NO;
            //                }
            //            }
            
            if(buffersUsed < kNumAQBufs) {
                if ([self.delegate isFinishPlayWithAudioQueueCore:self]) {
                    [self finishTheAudioQueue];
                } else {
                    NSData *data = [self.delegate audioQueueCore:self readDataOfLength:kAQDefaultBufSize];
                    [self passDataToAudioFileStream:data];
                }
                
            }
            
            // @AudioStreamer
            // If there are no queued buffers, we need to check here since the
            // handleBufferCompleteForQueue:buffer: should not change the state
            // (may not enter the synchronized section).
            //
            if (buffersUsed == 0 && self.state == AS_PLAYING)
            {
                err = AudioQueuePause(audioQueue);
                if (err)
                {
                    [self failWithErrorCode:AS_AUDIO_QUEUE_PAUSE_FAILED];
                    return;
                }
                self.state = AS_BUFFERING;
            }
            
        } while (isRunning && ![self runLoopShouldExit]);
        
        EKLog(@"break while");
        [self cleanAudioQueue];
    }];
    
    
    [self.threadQueue addOperation:op];
}

//@AudioStreamer
-(void) passDataToAudioFileStream:(NSData*) data {
    
    UInt8 *bytes;
    CFIndex length = 0;
    @synchronized(self)
    {
        if ([self isFinishing])
        {
            return;
        }
        
        bytes = data.bytes;
        length = data.length;
        self.currentReadLength += data.length;
        
        
        if (length == -1)
        {
            [self failWithErrorCode:AS_AUDIO_DATA_NOT_FOUND];
            return;
        }
        
        if (length == 0)
        {
            return;
        }
    }
    
    if (discontinuous)
    {
        err = AudioFileStreamParseBytes(audioFileStream, length, bytes, kAudioFileStreamParseFlag_Discontinuity);
        if (err)
        {
            [self failWithErrorCode:AS_FILE_STREAM_PARSE_BYTES_FAILED];
            return;
        }
    }
    else
    {
        err = AudioFileStreamParseBytes(audioFileStream, length, bytes, 0);
        if (err)
        {
            [self failWithErrorCode:AS_FILE_STREAM_PARSE_BYTES_FAILED];
            return;
        }
    }
}

//@AudioStreamer
-(void) createAudioFileStream {
    @synchronized(self) {
        if (audioFileStream != nil) {
            return;
        }
        
        AudioFileTypeID fileTypeHint =
        [MGAudioQueueCore hintForFileExtension:self.fileExtension];
        
        // create an audio file stream parser
        err = AudioFileStreamOpen((__bridge void * _Nullable)(self), ASPropertyListenerProc, ASPacketsProc,
                                  fileTypeHint, &audioFileStream);
        if (err)
        {
            [self failWithErrorCode:AS_FILE_STREAM_OPEN_FAILED];
            return;
        }
    }
}

//@AudioStream
-(void) finishTheAudioQueue {
    @synchronized(self)
    {
        if ([self isFinishing])
        {
            return;
        }
    }
    //
    // If there is a partially filled buffer, pass it to the AudioQueue for
    // processing
    //
    if (bytesFilled)
    {
        if (self.state == AS_WAITING_FOR_DATA)
        {
            //
            // Force audio data smaller than one whole buffer to play.
            //
            self.state = AS_FLUSHING_EOF;
        }
        [self enqueueBuffer];
    }
    
    @synchronized(self)
    {
        if (state == AS_WAITING_FOR_DATA)
        {
            [self failWithErrorCode:AS_AUDIO_DATA_NOT_FOUND];
        }
        
        //
        // We left the synchronized section to enqueue the buffer so we
        // must check that we are !finished again before touching the
        // audioQueue
        //
        else if (![self isFinishing])
        {
            if (audioQueue)
            {
                //
                // Set the progress at the end of the stream
                //
                err = AudioQueueFlush(audioQueue);
                if (err)
                {
                    [self failWithErrorCode:AS_AUDIO_QUEUE_FLUSH_FAILED];
                    return;
                }
                
                self.state = AS_STOPPING;
                stopReason = AS_STOPPING_EOF;
                err = AudioQueueStop(audioQueue, false);
                if (err)
                {
                    [self failWithErrorCode:AS_AUDIO_QUEUE_FLUSH_FAILED];
                    return;
                }
            }
            else
            {
                self.state = AS_STOPPED;
                stopReason = AS_STOPPING_EOF;
            }
        }
    }
    
}

//@AudioStreamer
-(void) cleanAudioQueue {
    @synchronized(self)
    {
        EKLog(@"start clean audioQueue");
        //
        // Close the audio file strea,
        //
        if (audioFileStream)
        {
            err = AudioFileStreamClose(audioFileStream);
            audioFileStream = nil;
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_CLOSE_FAILED];
            }
        }
        
        //
        // Dispose of the Audio Queue
        //
        if (audioQueue)
        {
            err = AudioQueueDispose(audioQueue, true);
            audioQueue = nil;
            if (err)
            {
                [self failWithErrorCode:AS_AUDIO_QUEUE_DISPOSE_FAILED];
            }
        }
        
        bytesFilled = 0;
        packetsFilled = 0;
        packetBufferSize = 0;
        err = 0;
        self.state = AS_INITIALIZED;
    }
}

#pragma mark Audio Callback Function Implementations

// @AudioStream
// ASPropertyListenerProc
//
// Receives notification when the AudioFileStream has audio packets to be
// played. In response, this function creates the AudioQueue, getting it
// ready to begin playback (playback won't begin until audio packets are
// sent to the queue in ASEnqueueBuffer).
//
// This function is adapted from Apple's example in AudioFileStreamExample with
// kAudioQueueProperty_IsRunning listening added.
//
static void ASPropertyListenerProc(void *						inClientData,
                                   AudioFileStreamID				inAudioFileStream,
                                   AudioFileStreamPropertyID		inPropertyID,
                                   UInt32 *						ioFlags)
{
    // this is called by audio file stream when it finds property values
    MGAudioQueueCore* audioCore = (__bridge MGAudioQueueCore *)inClientData;
    [audioCore
     handlePropertyChangeForFileStream:inAudioFileStream
     fileStreamPropertyID:inPropertyID
     ioFlags:ioFlags];
}

// @AudioStreamer
// ASPacketsProc
//
// When the AudioStream has packets to be played, this function gets an
// idle audio buffer and copies the audio packets into it. The calls to
// ASEnqueueBuffer won't return until there are buffers available (or the
// playback has been stopped).
//
// This function is adapted from Apple's example in AudioFileStreamExample with
// CBR functionality added.
//
static void ASPacketsProc(		void *					inClientData,
                          UInt32						inNumberBytes,
                          UInt32						inNumberPackets,
                          const void *					inInputData,
                          AudioStreamPacketDescription	*inPacketDescriptions)
{
    // this is called by audio file stream when it finds packets of audio
    MGAudioQueueCore* audioCore = (__bridge MGAudioQueueCore *)inClientData;
    [audioCore
     handleAudioPackets:inInputData
     numberBytes:inNumberBytes
     numberPackets:inNumberPackets
     packetDescriptions:inPacketDescriptions];
}

// @AudioStreamer
// ASAudioQueueOutputCallback
//
// Called from the AudioQueue when playback of specific buffers completes. This
// function signals from the AudioQueue thread to the AudioStream thread that
// the buffer is idle and available for copying data.
//
// This function is unchanged from Apple's example in AudioFileStreamExample.
//
static void ASAudioQueueOutputCallback(void*				inClientData,
                                       AudioQueueRef			inAQ,
                                       AudioQueueBufferRef		inBuffer)
{
    // this is called by the audio queue when it has finished decoding our data.
    // The buffer is now free to be reused.
    MGAudioQueueCore* audioCore = (__bridge MGAudioQueueCore *)inClientData;
    [audioCore handleBufferCompleteForQueue:inAQ buffer:inBuffer];
}

// @AudioStreamer
// ASAudioQueueIsRunningCallback
//
// Called from the AudioQueue when playback is started or stopped. This
// information is used to toggle the observable "isPlaying" property and
// set the "finished" flag.
//
static void ASAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    MGAudioQueueCore* audioCore = (__bridge MGAudioQueueCore *)inUserData;
    [audioCore handlePropertyChangeForQueue:inAQ propertyID:inID];
}

#if TARGET_OS_IPHONE
// @AudioStreamer
// ASAudioSessionInterruptionListener
//
// Invoked if the audio session is interrupted (like when the phone rings)
//
static void ASAudioSessionInterruptionListener(__unused void * inClientData, UInt32 inInterruptionState) {
    [[NSNotificationCenter defaultCenter] postNotificationName:ASAudioSessionInterruptionOccuredNotification object:@(inInterruptionState)];
}
#endif






#pragma mark Handler for callback
// @AudioStreamer
// handlePropertyChangeForFileStream:fileStreamPropertyID:ioFlags:
//
// Object method which handles implementation of ASPropertyListenerProc
//
// Parameters:
//    inAudioFileStream - should be the same as self->audioFileStream
//    inPropertyID - the property that changed
//    ioFlags - the ioFlags passed in
//
- (void)handlePropertyChangeForFileStream:(AudioFileStreamID)inAudioFileStream
                     fileStreamPropertyID:(AudioFileStreamPropertyID)inPropertyID
                                  ioFlags:(UInt32 *)ioFlags
{
    @synchronized(self)
    {
        if ([self isFinishing])
        {
            return;
        }
        
        if (inPropertyID == kAudioFileStreamProperty_ReadyToProducePackets)
        {
            discontinuous = true;
        }
        else if (inPropertyID == kAudioFileStreamProperty_DataOffset)
        {
            SInt64 offset;
            UInt32 offsetSize = sizeof(offset);
            err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataOffset, &offsetSize, &offset);
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
                return;
            }
            dataOffset = offset;
            
            if (audioDataByteCount)
            {
                _fileLength = dataOffset + audioDataByteCount;
            }
        }
        else if (inPropertyID == kAudioFileStreamProperty_AudioDataByteCount)
        {
            UInt32 byteCountSize = sizeof(UInt64);
            err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_AudioDataByteCount, &byteCountSize, &audioDataByteCount);
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
                return;
            }
            _fileLength = dataOffset + audioDataByteCount;
        }
        else if (inPropertyID == kAudioFileStreamProperty_DataFormat)
        {
            if (asbd.mSampleRate == 0)
            {
                UInt32 asbdSize = sizeof(asbd);
                
                // get the stream format.
                err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &asbdSize, &asbd);
                if (err)
                {
                    [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
                    return;
                }
            }
        }
        else if (inPropertyID == kAudioFileStreamProperty_FormatList)
        {
            Boolean outWriteable;
            UInt32 formatListSize;
            err = AudioFileStreamGetPropertyInfo(inAudioFileStream, kAudioFileStreamProperty_FormatList, &formatListSize, &outWriteable);
            if (err)
            {
                [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
                return;
            }
            
            AudioFormatListItem *formatList = malloc(formatListSize);
            err = AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_FormatList, &formatListSize, formatList);
            if (err)
            {
                free(formatList);
                [self failWithErrorCode:AS_FILE_STREAM_GET_PROPERTY_FAILED];
                return;
            }
            
            for (int i = 0; i * sizeof(AudioFormatListItem) < formatListSize; i += sizeof(AudioFormatListItem))
            {
                AudioStreamBasicDescription pasbd = formatList[i].mASBD;
                
                if (pasbd.mFormatID == kAudioFormatMPEG4AAC_HE ||
                    pasbd.mFormatID == kAudioFormatMPEG4AAC_HE_V2)
                {
                    //
                    // We've found HE-AAC, remember this to tell the audio queue
                    // when we construct it.
                    //
#if !TARGET_IPHONE_SIMULATOR
                    asbd = pasbd;
#endif
                    break;
                }
            }
            free(formatList);
        }
        else
        {
            //			EKLog(@"Property is %c%c%c%c",
            //				((char *)&inPropertyID)[3],
            //				((char *)&inPropertyID)[2],
            //				((char *)&inPropertyID)[1],
            //				((char *)&inPropertyID)[0]);
        }
    }
}

// @AudioStreamer
// handleAudioPackets:numberBytes:numberPackets:packetDescriptions:
//
// Object method which handles the implementation of ASPacketsProc
//
// Parameters:
//    inInputData - the packet data
//    inNumberBytes - byte size of the data
//    inNumberPackets - number of packets in the data
//    inPacketDescriptions - packet descriptions
//
- (void)handleAudioPackets:(const void *)inInputData
               numberBytes:(UInt32)inNumberBytes
             numberPackets:(UInt32)inNumberPackets
        packetDescriptions:(AudioStreamPacketDescription *)inPacketDescriptions;
{
    @synchronized(self)
    {
        if ([self isFinishing])
        {
            return;
        }
        
        if (bitRate == 0)
        {
            //
            // m4a and a few other formats refuse to parse the bitrate so
            // we need to set an "unparseable" condition here. If you know
            // the bitrate (parsed it another way) you can set it on the
            // class if needed.
            //
            bitRate = ~0;
        }
        
        // we have successfully read the first packests from the audio stream, so
        // clear the "discontinuous" flag
        if (discontinuous)
        {
            discontinuous = false;
        }
        
        if (!audioQueue)
        {
            [self createQueue];
        }
    }
    
    // the following code assumes we're streaming VBR data. for CBR data, the second branch is used.
    if (inPacketDescriptions)
    {
        for (int i = 0; i < inNumberPackets; ++i)
        {
            SInt64 packetOffset = inPacketDescriptions[i].mStartOffset;
            SInt64 packetSize   = inPacketDescriptions[i].mDataByteSize;
            size_t bufSpaceRemaining;
            
            if (processedPacketsCount < BitRateEstimationMaxPackets)
            {
                processedPacketsSizeTotal += packetSize;
                processedPacketsCount += 1;
            }
            
            @synchronized(self)
            {
                // If the audio was terminated before this point, then
                // exit.
                if ([self isFinishing])
                {
                    return;
                }
                
                if (packetSize > packetBufferSize)
                {
                    [self failWithErrorCode:AS_AUDIO_BUFFER_TOO_SMALL];
                }
                
                bufSpaceRemaining = packetBufferSize - bytesFilled;
            }
            
            // if the space remaining in the buffer is not enough for this packet, then enqueue the buffer.
            if (bufSpaceRemaining < packetSize)
            {
                [self enqueueBuffer];
            }
            
            @synchronized(self)
            {
                // If the audio was terminated while waiting for a buffer, then
                // exit.
                if ([self isFinishing])
                {
                    return;
                }
                
                //
                // If there was some kind of issue with enqueueBuffer and we didn't
                // make space for the new audio data then back out
                //
                if (bytesFilled + packetSize > packetBufferSize)
                {
                    return;
                }
                
                // copy data to the audio queue buffer
                AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
                memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)inInputData + packetOffset, packetSize);
                
                // fill out packet description
                packetDescs[packetsFilled] = inPacketDescriptions[i];
                packetDescs[packetsFilled].mStartOffset = bytesFilled;
                // keep track of bytes filled and packets filled
                bytesFilled += packetSize;
                packetsFilled += 1;
            }
            
            // if that was the last free packet description, then enqueue the buffer.
            size_t packetsDescsRemaining = kAQMaxPacketDescs - packetsFilled;
            if (packetsDescsRemaining == 0) {
                [self enqueueBuffer];
            }
        }
    }
    else
    {
        size_t offset = 0;
        while (inNumberBytes)
        {
            // if the space remaining in the buffer is not enough for this packet, then enqueue the buffer.
            size_t bufSpaceRemaining = kAQDefaultBufSize - bytesFilled;
            if (bufSpaceRemaining < inNumberBytes)
            {
                [self enqueueBuffer];
            }
            
            @synchronized(self)
            {
                // If the audio was terminated while waiting for a buffer, then
                // exit.
                if ([self isFinishing])
                {
                    return;
                }
                
                bufSpaceRemaining = kAQDefaultBufSize - bytesFilled;
                size_t copySize;
                if (bufSpaceRemaining < inNumberBytes)
                {
                    copySize = bufSpaceRemaining;
                }
                else
                {
                    copySize = inNumberBytes;
                }
                
                //
                // If there was some kind of issue with enqueueBuffer and we didn't
                // make space for the new audio data then back out
                //
                if (bytesFilled > packetBufferSize)
                {
                    return;
                }
                
                // copy data to the audio queue buffer
                AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
                memcpy((char*)fillBuf->mAudioData + bytesFilled, (const char*)(inInputData + offset), copySize);
                
                
                // keep track of bytes filled and packets filled
                bytesFilled += copySize;
                packetsFilled = 0;
                inNumberBytes -= copySize;
                offset += copySize;
            }
        }
    }
}

//
// createQueue
//
// Method to create the AudioQueue from the parameters gathered by the
// AudioFileStream.
//
// Creation is deferred to the handling of the first audio packet (although
// it could be handled any time after kAudioFileStreamProperty_ReadyToProducePackets
// is true).
//
- (void)createQueue
{
    sampleRate = asbd.mSampleRate;
    packetDuration = asbd.mFramesPerPacket / sampleRate;
    
    // create the audio queue
    err = AudioQueueNewOutput(&asbd, ASAudioQueueOutputCallback, (__bridge void * _Nullable)(self), NULL, NULL, 0, &audioQueue);
    if (err)
    {
        [self failWithErrorCode:AS_AUDIO_QUEUE_CREATION_FAILED];
        return;
    }
    
    // start the queue if it has not been started already
    // listen to the "isRunning" property
    err = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, ASAudioQueueIsRunningCallback, (__bridge void * _Nullable)(self));
    if (err)
    {
        [self failWithErrorCode:AS_AUDIO_QUEUE_ADD_LISTENER_FAILED];
        return;
    }
    
    // get the packet size if it is available
    UInt32 sizeOfUInt32 = sizeof(UInt32);
    err = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_PacketSizeUpperBound, &sizeOfUInt32, &packetBufferSize);
    if (err || packetBufferSize == 0)
    {
        err = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_MaximumPacketSize, &sizeOfUInt32, &packetBufferSize);
        if (err || packetBufferSize == 0)
        {
            // No packet size available, just use the default
            packetBufferSize = kAQDefaultBufSize;
        }
    }
    
    // allocate audio queue buffers
    for (unsigned int i = 0; i < kNumAQBufs; ++i)
    {
        err = AudioQueueAllocateBuffer(audioQueue, packetBufferSize, &audioQueueBuffer[i]);
        if (err)
        {
            [self failWithErrorCode:AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED];
            return;
        }
    }
    
    // get the cookie size
    UInt32 cookieSize;
    Boolean writable;
    OSStatus ignorableError;
    ignorableError = AudioFileStreamGetPropertyInfo(audioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable);
    if (ignorableError)
    {
        return;
    }
    
    // get the cookie data
    void* cookieData = calloc(1, cookieSize);
    ignorableError = AudioFileStreamGetProperty(audioFileStream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, cookieData);
    if (ignorableError)
    {
        return;
    }
    
    // set the cookie on the queue.
    ignorableError = AudioQueueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, cookieData, cookieSize);
    free(cookieData);
    if (ignorableError)
    {
        return;
    }
}

// @AudioStreamer
// enqueueBuffer
//
// Called from ASPacketsProc and connectionDidFinishLoading to pass filled audio
// bufffers (filled by ASPacketsProc) to the AudioQueue for playback. This
// function does not return until a buffer is idle for further filling or
// the AudioQueue is stopped.
//
// This function is adapted from Apple's example in AudioFileStreamExample with
// CBR functionality added.
//
- (void)enqueueBuffer
{
    @synchronized(self)
    {
        if ([self isFinishing])
        {
            return;
        }
        
        inuse[fillBufferIndex] = true;		// set in use flag
        buffersUsed++;
        
        // enqueue buffer
        AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
        fillBuf->mAudioDataByteSize = bytesFilled;
        
        if (packetsFilled)
        {
            err = AudioQueueEnqueueBuffer(audioQueue, fillBuf, packetsFilled, packetDescs);
        }
        else
        {
            err = AudioQueueEnqueueBuffer(audioQueue, fillBuf, 0, NULL);
        }
        
        if (err)
        {
            [self failWithErrorCode:AS_AUDIO_QUEUE_ENQUEUE_FAILED];
            return;
        }
        
        
        if (state == AS_BUFFERING ||
            state == AS_WAITING_FOR_DATA ||
            state == AS_FLUSHING_EOF ||
            (state == AS_STOPPED && stopReason == AS_STOPPING_TEMPORARILY))
        {
            //
            // Fill all the buffers before starting. This ensures that the
            // AudioFileStream stays a small amount ahead of the AudioQueue to
            // avoid an audio glitch playing streaming files on iPhone SDKs < 3.0
            //
            if (state == AS_FLUSHING_EOF || buffersUsed == kNumAQBufs - 1)
            {
                if (self.state == AS_BUFFERING)
                {
                    err = AudioQueueStart(audioQueue, NULL);
                    if (err)
                    {
                        [self failWithErrorCode:AS_AUDIO_QUEUE_START_FAILED];
                        return;
                    }
                    self.state = AS_PLAYING;
                }
                else
                {
                    self.state = AS_WAITING_FOR_QUEUE_TO_START;
                    
                    err = AudioQueueStart(audioQueue, NULL);
                    if (err)
                    {
                        [self failWithErrorCode:AS_AUDIO_QUEUE_START_FAILED];
                        return;
                    }
                }
            }
        }
        
        // go to next buffer
        if (++fillBufferIndex >= kNumAQBufs) fillBufferIndex = 0;
        bytesFilled = 0;		// reset bytes filled
        packetsFilled = 0;		// reset packets filled
    }
    
    // wait until next buffer is not in use
    pthread_mutex_lock(&queueBuffersMutex);
    while (inuse[fillBufferIndex])
    {
        pthread_cond_wait(&queueBufferReadyCondition, &queueBuffersMutex);
    }
    pthread_mutex_unlock(&queueBuffersMutex);
}

// @AudioStreamer
// handleBufferCompleteForQueue:buffer:
//
// Handles the buffer completetion notification from the audio queue
//
// Parameters:
//    inAQ - the queue
//    inBuffer - the buffer
//
- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
                              buffer:(AudioQueueBufferRef)inBuffer
{
    unsigned int bufIndex = -1;
    for (unsigned int i = 0; i < kNumAQBufs; ++i)
    {
        if (inBuffer == audioQueueBuffer[i])
        {
            bufIndex = i;
            break;
        }
    }
    
    if (bufIndex == -1)
    {
        [self failWithErrorCode:AS_AUDIO_QUEUE_BUFFER_MISMATCH];
        pthread_mutex_lock(&queueBuffersMutex);
        pthread_cond_signal(&queueBufferReadyCondition);
        pthread_mutex_unlock(&queueBuffersMutex);
        return;
    }
    
    // signal waiting thread that the buffer is free.
    pthread_mutex_lock(&queueBuffersMutex);
    inuse[bufIndex] = false;
    buffersUsed--;
    
    //
    //  Enable this logging to measure how many buffers are queued at any time.
    //
#if LOG_QUEUED_BUFFERS
    EKLog(@"Queued buffers: %ld", buffersUsed);
#endif
    
    pthread_cond_signal(&queueBufferReadyCondition);
    pthread_mutex_unlock(&queueBuffersMutex);
}

- (void)handlePropertyChange:(NSNumber *)num
{
    [self handlePropertyChangeForQueue:NULL propertyID:[num intValue]];
}

// @AudioStreamer
// handlePropertyChangeForQueue:propertyID:
//
// Implementation for ASAudioQueueIsRunningCallback
//
// Parameters:
//    inAQ - the audio queue
//    inID - the property ID
//
- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
                          propertyID:(AudioQueuePropertyID)inID
{
    
    //    if (![[NSThread currentThread] isEqual:internalThread])
    //    {
    //        [self
    //         performSelector:@selector(handlePropertyChange:)
    //         onThread:internalThread
    //         withObject:[NSNumber numberWithInt:inID]
    //         waitUntilDone:NO
    //         modes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];
    //        return;
    //    }
    @synchronized(self)
    {
        if (inID == kAudioQueueProperty_IsRunning)
        {
            if (state == AS_STOPPING)
            {
                // Should check value of isRunning to ensure this kAudioQueueProperty_IsRunning isn't
                // the *start* of a very short stream
                UInt32 isRunning = 0;
                UInt32 size = sizeof(UInt32);
                AudioQueueGetProperty(audioQueue, inID, &isRunning, &size);
                if (isRunning == 0)
                {
                    self.state = AS_STOPPED;
                }
            }
            else if (state == AS_WAITING_FOR_QUEUE_TO_START)
            {
                //
                // Note about this bug avoidance quirk:
                //
                // On cleanup of the AudioQueue thread, on rare occasions, there would
                // be a crash in CFSetContainsValue as a CFRunLoopObserver was getting
                // removed from the CFRunLoop.
                //
                // After lots of testing, it appeared that the audio thread was
                // attempting to remove CFRunLoop observers from the CFRunLoop after the
                // thread had already deallocated the run loop.
                //
                // By creating an NSRunLoop for the AudioQueue thread, it changes the
                // thread destruction order and seems to avoid this crash bug -- or
                // at least I haven't had it since (nasty hard to reproduce error!)
                //
                [NSRunLoop currentRunLoop];
                
                self.state = AS_PLAYING;
            }
            else
            {
                EKLog(@"AudioQueue changed state in unexpected way.");
            }
        }
    }
    
}
#pragma mark interface methods
// @AudioStreamer
// setState:
//
// Sets the state and sends a notification that the state has changed.
//
// This method
//
// Parameters:
//    anErrorCode - the error condition
//
- (void)setState:(AudioStreamerState)aStatus
{
    @synchronized(self)
    {
        if (state != aStatus)
        {
            state = aStatus;
            
            if ([[NSThread currentThread] isEqual:[NSThread mainThread]])
            {
                [self mainThreadStateNotification];
            }
            else
            {
                [self
                 performSelectorOnMainThread:@selector(mainThreadStateNotification)
                 withObject:nil
                 waitUntilDone:NO];
            }
        }
    }
}

// @AudioStreamer
// state
//
// returns the state value.
//
- (AudioStreamerState)state
{
    @synchronized(self)
    {
        return state;
    }
}

// @AudioStreamer
// progress
//
// returns the current playback progress. Will return zero if sampleRate has
// not yet been detected.
//
- (double)playProgress
{
    @synchronized(self)
    {
        if (sampleRate > 0 && (state == AS_STOPPING || ![self isFinishing]))
        {
            if (state != AS_PLAYING && state != AS_PAUSED && state != AS_BUFFERING && state != AS_STOPPING)
            {
                return lastProgress;
            }
            
            AudioTimeStamp queueTime;
            Boolean discontinuity;
            err = AudioQueueGetCurrentTime(audioQueue, NULL, &queueTime, &discontinuity);
            
            const OSStatus AudioQueueStopped = 0x73746F70; // 0x73746F70 is 'stop'
            if (err == AudioQueueStopped)
            {
                return lastProgress;
            }
            else if (err)
            {
                [self failWithErrorCode:AS_GET_AUDIO_TIME_FAILED];
            }
            //this queueTime.mSampleTime / sampleRate is the time counted from the audioQueue start.
            //if you don't stop the AudioQueue, this wouldn't be set zero.
            //For getting the rigth progress, we restart the AudioQueue, and plus the seekTime.
            double seekTime = 0;
            if ([self.delegate respondsToSelector:@selector(seekTimeWithAudioQueueCore:)]) {
                seekTime = [self.delegate seekTimeWithAudioQueueCore:self];
            }
            double progress = seekTime + queueTime.mSampleTime / sampleRate;
            if (progress < 0.0)
            {
                progress = 0.0;
            }
            
            lastProgress = progress;
            return progress;
        }
    }
    
    return lastProgress;
}


// @AudioStreamer
// calculatedBitRate
//
// returns the bit rate, if known. Uses packet duration times running bits per
//   packet if available, otherwise it returns the nominal bitrate. Will return
//   zero if no useful option available.
//
- (double)calculatedBitRate
{
    if (packetDuration && processedPacketsCount > BitRateEstimationMinPackets)
    {
        double averagePacketByteSize = processedPacketsSizeTotal / processedPacketsCount;
        return 8.0 * averagePacketByteSize / packetDuration;
    }
    
    if (bitRate)
    {
        return (double)bitRate;
    }
    
    return 0;
}

// @AudioStreamer
// duration
//
// Calculates the duration of available audio from the bitRate and fileLength.
//
// returns the calculated duration in seconds.
//
- (double)duration
{
    double calculatedBitRate = [self calculatedBitRate];
    
    if (calculatedBitRate == 0 || self.fileLength == 0)
    {
        return 0.0;
    }
    
    return (self.fileLength - dataOffset) / (calculatedBitRate * 0.125);
}

// @AudioStreamer
// pause
//
// A togglable pause function.
//
- (void)pause
{
    @synchronized(self)
    {
        if (state == AS_PLAYING || state == AS_STOPPING)
        {
            err = AudioQueuePause(audioQueue);
            if (err)
            {
                [self failWithErrorCode:AS_AUDIO_QUEUE_PAUSE_FAILED];
                return;
            }
            laststate = state;
            self.state = AS_PAUSED;
        }
        else if (state == AS_PAUSED)
        {
            err = AudioQueueStart(audioQueue, NULL);
            if (err)
            {
                [self failWithErrorCode:AS_AUDIO_QUEUE_START_FAILED];
                return;
            }
            self.state = laststate;
        }
    }
}

// @AudioStreamer
// stop
//
// This method can be called to stop downloading/playback before it completes.
// It is automatically called when an error occurs.
//
// If playback has not started before this method is called, it will toggle the
// "isPlaying" property so that it is guaranteed to transition to true and
// back to false
//
-(void) stop
{
    EKLog(@"AudioQueueCore func stop");
    @synchronized(self)
    {
        if (audioQueue &&
            (state == AS_PLAYING || state == AS_PAUSED ||
             state == AS_BUFFERING || state == AS_WAITING_FOR_QUEUE_TO_START))
        {
            self.state = AS_STOPPING;
            stopReason = AS_STOPPING_USER_ACTION;
            err = AudioQueueStop(audioQueue, true);
            if (err)
            {
                [self failWithErrorCode:AS_AUDIO_QUEUE_STOP_FAILED];
                return;
            }
        }
        else if (state != AS_INITIALIZED)
        {
            self.state = AS_STOPPED;
            stopReason = AS_STOPPING_USER_ACTION;
        }
    }
    
    while (state != AS_INITIALIZED)
    {
        [NSThread sleepForTimeInterval:0.1];
    }
}

- (BOOL)isFinishPlayingSuccessfully {
    if (stopReason == AS_STOPPING_EOF) {
        return YES;
    }
    return NO;
}

// @AudioStreamer
// isFinishing
//
// returns YES if the audio has reached a stopping condition.
//
- (BOOL)isFinishing
{
    @synchronized (self)
    {
        if ((errorCode != AS_NO_ERROR && state != AS_INITIALIZED) ||
            ((state == AS_STOPPING || state == AS_STOPPED) &&
             stopReason != AS_STOPPING_TEMPORARILY))
        {
            return YES;
        }
    }
    
    return NO;
}

// @AudioStreamer
// isIdle
//
// returns YES if the AudioStream is in the AS_INITIALIZED state (i.e.
// isn't doing anything).
//
- (BOOL)isIdle
{
    if (state == AS_INITIALIZED)
    {
        return YES;
    }
    
    return NO;
}

// @AudioStreamer
// isPlaying
//
// returns YES if the audio currently playing.
//
- (BOOL)isPlaying
{
    if (state == AS_PLAYING)
    {
        return YES;
    }
    return NO;
}

// @AudioStreamer
// isPaused
//
// returns YES if the audio currently pause.
//
- (BOOL)isPaused
{
    if (state == AS_PAUSED)
    {
        return YES;
    }
    
    return NO;
}
#pragma mark other
// @AudioStreamer
// mainThreadStateNotification
//
// Method invoked on main thread to send notifications to the main thread's
// notification center.
//
- (void)mainThreadStateNotification
{
    NSNotification *notification =
    [NSNotification
     notificationWithName:ASStatusChangedNotification
     object:self];
    [[NSNotificationCenter defaultCenter]
     postNotification:notification];
}

// @AudioStreamer
// runLoopShouldExit
//
// returns YES if the run loop should exit.
//
- (BOOL)runLoopShouldExit
{
    @synchronized(self)
    {
        if (errorCode != AS_NO_ERROR ||
            (state == AS_STOPPED &&
             stopReason != AS_STOPPING_TEMPORARILY))
        {
            EKLog(@"errorCode=%d, state=%d, stopReason=%d", errorCode, state, stopReason);
            return YES;
        }
    }
    
    return NO;
}


// @AudioStreamer
// failWithErrorCode:
//
// Sets the playback state to failed and logs the error.
//
// Parameters:
//    anErrorCode - the error condition
//
- (void)failWithErrorCode:(AudioStreamerErrorCode)anErrorCode
{
    @synchronized(self)
    {
        if (errorCode != AS_NO_ERROR)
        {
            // Only set the error once.
            return;
        }
        
        errorCode = anErrorCode;
        
        if (err)
        {
            char *errChars = (char *)&err;
            EKLog(@"%@ err: %c%c%c%c %d\n",
                  [MGAudioQueueCore stringForErrorCode:anErrorCode],
                  errChars[3], errChars[2], errChars[1], errChars[0],
                  (int)err);
        }
        else
        {
            EKLog(@"%@", [MGAudioQueueCore stringForErrorCode:anErrorCode]);
        }
        
        if (state == AS_PLAYING ||
            state == AS_PAUSED ||
            state == AS_BUFFERING)
        {
            self.state = AS_STOPPING;
            stopReason = AS_STOPPING_ERROR;
            AudioQueueStop(audioQueue, true);
        }
        
        if (self.shouldDisplayAlertOnError)
            [self presentAlertWithTitle:NSLocalizedStringFromTable(@"File Error", @"Errors", nil)
                                message:NSLocalizedStringFromTable(@"Unable to configure network read stream.", @"Errors", nil)];
    }
}
// @AudioStreamer
// presentAlertWithTitle:message:
//
// Common code for presenting error dialogs
//
// Parameters:
//    title - title for the dialog
//    message - main test for the dialog
//
- (void)presentAlertWithTitle:(NSString*)title message:(NSString*)message
{
#if TARGET_OS_IPHONE
    UIAlertView *alert =
    [[UIAlertView alloc]
     initWithTitle:title
     message:message
     delegate:nil
     cancelButtonTitle:NSLocalizedString(@"OK", @"")
     otherButtonTitles: nil];
    [alert
     performSelector:@selector(show)
     onThread:[NSThread mainThread]
     withObject:nil
     waitUntilDone:NO];
#else
    NSAlert *alert =
    [NSAlert
     alertWithMessageText:title
     defaultButton:NSLocalizedString(@"OK", @"")
     alternateButton:nil
     otherButton:nil
     informativeTextWithFormat:message];
    [alert
     performSelector:@selector(runModal)
     onThread:[NSThread mainThread]
     withObject:nil
     waitUntilDone:NO];
#endif
}





// @AudioStreamer
// hintForFileExtension:
//
// Generates a first guess for the file type based on the file's extension
//
// Parameters:
//    fileExtension - the file extension
//
// returns a file type hint that can be passed to the AudioFileStream
//
+ (AudioFileTypeID)hintForFileExtension:(NSString *)fileExtension
{
    AudioFileTypeID fileTypeHint = kAudioFileAAC_ADTSType;
    if ([fileExtension isEqual:@"mp3"])
    {
        fileTypeHint = kAudioFileMP3Type;
    }
    else if ([fileExtension isEqual:@"wav"])
    {
        fileTypeHint = kAudioFileWAVEType;
    }
    else if ([fileExtension isEqual:@"aifc"])
    {
        fileTypeHint = kAudioFileAIFCType;
    }
    else if ([fileExtension isEqual:@"aiff"])
    {
        fileTypeHint = kAudioFileAIFFType;
    }
    else if ([fileExtension isEqual:@"m4a"])
    {
        fileTypeHint = kAudioFileM4AType;
    }
    else if ([fileExtension isEqual:@"mp4"])
    {
        fileTypeHint = kAudioFileMPEG4Type;
    }
    else if ([fileExtension isEqual:@"caf"])
    {
        fileTypeHint = kAudioFileCAFType;
    }
    else if ([fileExtension isEqual:@"aac"])
    {
        fileTypeHint = kAudioFileAAC_ADTSType;
    }
    return fileTypeHint;
}

// @AudioStreamer
// stringForErrorCode:
//
// Converts an error code to a string that can be localized or presented
// to the user.
//
// Parameters:
//    anErrorCode - the error code to convert
//
// returns the string representation of the error code
//
+ (NSString *)stringForErrorCode:(AudioStreamerErrorCode)anErrorCode
{
    switch (anErrorCode)
    {
        case AS_NO_ERROR:
            return AS_NO_ERROR_STRING;
        case AS_FILE_STREAM_GET_PROPERTY_FAILED:
            return AS_FILE_STREAM_GET_PROPERTY_FAILED_STRING;
        case AS_FILE_STREAM_SEEK_FAILED:
            return AS_FILE_STREAM_SEEK_FAILED_STRING;
        case AS_FILE_STREAM_PARSE_BYTES_FAILED:
            return AS_FILE_STREAM_PARSE_BYTES_FAILED_STRING;
        case AS_AUDIO_QUEUE_CREATION_FAILED:
            return AS_AUDIO_QUEUE_CREATION_FAILED_STRING;
        case AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED:
            return AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED_STRING;
        case AS_AUDIO_QUEUE_ENQUEUE_FAILED:
            return AS_AUDIO_QUEUE_ENQUEUE_FAILED_STRING;
        case AS_AUDIO_QUEUE_ADD_LISTENER_FAILED:
            return AS_AUDIO_QUEUE_ADD_LISTENER_FAILED_STRING;
        case AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED:
            return AS_AUDIO_QUEUE_REMOVE_LISTENER_FAILED_STRING;
        case AS_AUDIO_QUEUE_START_FAILED:
            return AS_AUDIO_QUEUE_START_FAILED_STRING;
        case AS_AUDIO_QUEUE_BUFFER_MISMATCH:
            return AS_AUDIO_QUEUE_BUFFER_MISMATCH_STRING;
        case AS_FILE_STREAM_OPEN_FAILED:
            return AS_FILE_STREAM_OPEN_FAILED_STRING;
        case AS_FILE_STREAM_CLOSE_FAILED:
            return AS_FILE_STREAM_CLOSE_FAILED_STRING;
        case AS_AUDIO_QUEUE_DISPOSE_FAILED:
            return AS_AUDIO_QUEUE_DISPOSE_FAILED_STRING;
        case AS_AUDIO_QUEUE_PAUSE_FAILED:
            return AS_AUDIO_QUEUE_DISPOSE_FAILED_STRING;
        case AS_AUDIO_QUEUE_FLUSH_FAILED:
            return AS_AUDIO_QUEUE_FLUSH_FAILED_STRING;
        case AS_AUDIO_DATA_NOT_FOUND:
            return AS_AUDIO_DATA_NOT_FOUND_STRING;
        case AS_GET_AUDIO_TIME_FAILED:
            return AS_GET_AUDIO_TIME_FAILED_STRING;
        case AS_NETWORK_CONNECTION_FAILED:
            return AS_NETWORK_CONNECTION_FAILED_STRING;
        case AS_AUDIO_QUEUE_STOP_FAILED:
            return AS_AUDIO_QUEUE_STOP_FAILED_STRING;
        case AS_AUDIO_STREAMER_FAILED:
            return AS_AUDIO_STREAMER_FAILED_STRING;
        case AS_AUDIO_BUFFER_TOO_SMALL:
            return AS_AUDIO_BUFFER_TOO_SMALL_STRING;
        default:
            return AS_AUDIO_STREAMER_FAILED_STRING;
    }
    
    return AS_AUDIO_STREAMER_FAILED_STRING;
}




@end
