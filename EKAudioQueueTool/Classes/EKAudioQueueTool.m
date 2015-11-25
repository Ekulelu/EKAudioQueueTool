//
//  AudioQueueTool.m
//  AudioQueueTool
//
//  Created by ekulelu on 15/10/26.
//  Copyright © 2015年 ekulelu. All rights reserved.
//
//  This software is based on AudioStreamer by Matt Gallaher.
//  I used AudioStreamer core code to build this software, which can play local and online audio.
//  The code copy from AudioStreamer is marked by @AudioStreamer.
//  This software is free for used, subject to the restrictions as AudioStreamer's:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//  3. This notice may not be removed or altered from any source
//     distribution.
//
#import "EKAudioQueueTool.h"
#import "EKAudioQueueToolFileManager.h"
#import "MGAudioQueueCore.h"
#import "EKAudioQueueToolHeader.h"

@interface EKAudioQueueTool()<NSURLSessionDelegate, NSURLSessionTaskDelegate, NSURLSessionDataDelegate, MGAudioQueueCoreDelegate>
{
    double _duration;
}
@property (nonatomic, strong) MGAudioQueueCore* audioCore;
@property (nonatomic, strong) EKAudioQueueToolFileManager* fileManager;

@property (nonatomic, strong) NSURLSessionDataTask* dataTask;

@property (nonatomic, strong) NSFileHandle* writeHandle;
@property (nonatomic, strong) NSFileHandle* readHandle;
@property (nonatomic, strong) NSMutableArray* datArray;
@property (nonatomic, copy) NSString* datFilePath;

@property (nonatomic, assign) long long currentWriteOffset;
@property (atomic, assign) long long currentReadOffset;
@property (nonatomic, copy) NSString *fileExtension;
@property (nonatomic, strong) NSURL* url;
@property (nonatomic, copy) NSString* audioFilePath;
@property (nonatomic, strong) NSOperationQueue* netWorkthreadQueue;
@property (nonatomic, assign) BOOL isLocalAudio;
@property (nonatomic, copy) NSString* tempFileSaveFolder;
@property (nonatomic, assign) AudioQueueCoreSeekTime seekTimeS;
@property (nonatomic, assign) AudioQueueCoreSeekTime lastSeekTimeS;

@property (nonatomic, assign) BOOL downloadForPlaying;//when seektime, the currentReadOffset should large than
                                                //currentWriteOffset. we should wait until download to
                                                //currentReadOffset.
                                                //There is another situation: when finish downloading
                                                //the latter part, we call a new request to download the front
                                                //part. In this situation ignore the
                                                //currentReadOffet > currentWriteOffset.
                                                //But this situation is left to complete, since I don't know
                                                //whether the situation is really need.
                                                //P.S. when play the local audio, this flag should be NO.
@end

@implementation EKAudioQueueTool

#pragma mark AudioQueueCoreDelegate
- (long long)fileLengthWithAudioQueueCore:(MGAudioQueueCore *)audioQueueCore {
    return self.fileLength;
}

- (NSData *)audioQueueCore:(MGAudioQueueCore *)audioQueueCore readDataOfLength:(long long)dataLength {
    while (self.currentReadOffset + dataLength > self.currentWriteOffset && self.dataTask != nil && self.downloadForPlaying) {
        _waitingData = YES;
        [NSThread sleepForTimeInterval:0.2];// you can also return nil. the audioQueue will pause, but when it
                                            // restart, there is an ear-priercing in my headset. so I choose to
                                            // sleep the thread.
//        return nil;
    }
    _waitingData = NO;
    [self.readHandle seekToFileOffset:self.currentReadOffset];
    NSData *data = [self.readHandle readDataOfLength:dataLength];
    self.currentReadOffset += data.length;
    return data;
}

- (NSString *)fileExtensionWithAudioQueueCore:(MGAudioQueueCore *) audioQueueCore {
    return self.fileExtension;
}

- (double)seekTimeWithAudioQueueCore:(MGAudioQueueCore *)audioQueueCore {
    return self.seekTimeS.exactSeekTime;
}

- (BOOL)isFinishPlayWithAudioQueueCore:(MGAudioQueueCore *)audioQueueCore {
    return self.currentReadOffset >= self.fileLength && self.currentReadOffset > 0;
}


#pragma mark - NSURLSessionDataDelegate
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler{
    
     _fileExtension = [response.suggestedFilename pathExtension];
    
    // we only have a subset of the total bytes.
    // if the self.fileLength = 0, means can't read form dat file or audio file,
    // means is the first time to play the online audio. The first time we don't seek time,
    // so we create file and read the fileLength form response.
    if (self.fileLength == 0)
    {
        _fileLength = response.expectedContentLength;
        RWFileS *RWFileS = [self.fileManager createFileWithRequestURL:self.url extensionName:_fileExtension fileLength:_fileLength];
        self.readHandle = [NSFileHandle fileHandleForReadingAtPath:RWFileS.audioFilePath];
        self.writeHandle = [NSFileHandle fileHandleForWritingAtPath:RWFileS.audioFilePath];
        self.audioFilePath = RWFileS.audioFilePath;
        self.datArray = RWFileS.datArray;
        self.datFilePath = RWFileS.datFilePath;
        EKLog(@"response fileLength = %lld", _fileLength);
    }
   
    long length = response.expectedContentLength;
    EKLog(@"sub fileLength = %ld", length);
    EKLog(@"response currentWrite = %lld", self.currentWriteOffset);

    
    [self.audioCore startAudioPlay];
    
    completionHandler(NSURLSessionResponseAllow);
   
}


- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {

    [self.fileManager saveData:data WriteHandle:self.writeHandle offset:self.currentWriteOffset datArray:self.datArray datFilePath:self.datFilePath fileLength:self.fileLength];
    self.currentWriteOffset += data.length;
    
    if(self.fileLength != 0)
        self.downLoadPercent = (double) self.currentWriteOffset / self.fileLength;
}

#pragma mark - NSURLSessionTaskDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error != nil) {
        if(error.code != NSURLErrorCancelled) EKErrorLog(@"%@",error);
        else EKLog(@"cancel connection");
    }
    [self.writeHandle closeFile];
    self.writeHandle = nil;
    if (self.downLoadPercent == 1) {
        EKLog(@"url connection stop, download completed");
    } else {
        EKLog(@"url connection stop, download incompleted");
    }
    BOOL fileDownloadCompleted = YES;
    for (long i = 0; i < self.datArray.count; i++) {
        if ([self.datArray[i] boolValue] == NO) {
            fileDownloadCompleted = NO;
            break;
        }
    }
    if (fileDownloadCompleted) {
        self.downLoadPercent = 1.0;
        [self deleteFile:self.datFilePath];
    }
    if (!_cacheEnable) {
        [self deleteFile:self.audioFilePath];
        [self deleteFile:self.datFilePath];
    }
    self.dataTask = nil;
}

#pragma mark URLSession init
- (instancetype)initWithCacheEnable:(BOOL) cacheEnable{
    if (self = [super init]) {
        _fileManager = [[EKAudioQueueToolFileManager alloc] init];
        NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
        NSString *cachefolder = [CachePath stringByAppendingPathComponent:@"EKAQToolCache"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:cachefolder]) {
            [fileManager createDirectoryAtPath:cachefolder withIntermediateDirectories:YES attributes:nil error:nil];
        }
        _fileManager.saveFolder = cachefolder;
        self.tempFileSaveFolder = cachefolder;
        _audioCore = [[MGAudioQueueCore alloc] init];
        _audioCore.delegate = self;
        _cacheEnable = cacheEnable;
    }
    return self;
}



- (instancetype)init {
    return [self initWithCacheEnable:YES];
}

- (void)cleanSeekTimeS {
    AudioQueueCoreSeekTime s;
    s.seekByteOffset = 0;
    s.isShouldSeek = NO;
    s.exactSeekTime = 0;
    self.seekTimeS = s;
}

- (void)cleanLastSeekTimeS {
    AudioQueueCoreSeekTime s;
    s.seekByteOffset = 0;
    s.isShouldSeek = NO;
    s.exactSeekTime = 0;
    self.lastSeekTimeS = s;
}



- (void)setupInitParams {
    //stop the audioQueue and download if opened before
    if (![self isIdle]) [self internalStop];
    
    self.downLoadPercent = 0.0;
    self.currentWriteOffset = 0;
    self.currentReadOffset = 0;
    self.audioFilePath = nil;
    self.url = nil;
    _duration = 0;
    _fileLength = 0;
    _fileExtension = nil;
    [self cleanSeekTimeS];
    [self cleanLastSeekTimeS];
    self.datArray = nil;
    self.downloadForPlaying = NO;
}

- (void)playLocalAudioWithFilePath: (NSString*) filePath {
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        EKErrorLog(@"Local audio file isn't exit!");
        return;
    };
    //should be called first
    [self setupInitParams];
    
    _fileLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil] fileSize];
    _fileExtension = [filePath pathExtension];
    
    self.isLocalAudio = true;
    self.audioFilePath = filePath;

    self.readHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];

    [self.audioCore startAudioPlay];
}

- (void)playOnlineAudioWithURL:(NSURL*) URL{
    [self setupInitParams];
    [self playOnlineAudioWithURL:URL seekTime:0];
}

- (void)seekTime:(double) requestSeekTime {
    if (self.audioFilePath == nil && self.url == nil) {
        EKLog(@"You should start an audio before seeking time.");
        return;
    }
    if (self.isLocalAudio) {
        [self seekTimeWhenPalyLocalAudio:requestSeekTime];
    } else {
        [self playOnlineAudioWithURL:self.url seekTime:requestSeekTime];
    }
}

- (void)seekTimeWhenPalyLocalAudio:(double) requestSeekTime {
    if (requestSeekTime < 0) return;
    self.seekTimeS = [self.audioCore shouldSeekToTime:requestSeekTime];
    if (!self.seekTimeS.isShouldSeek)  return;
    [self.audioCore stop];
    [self.readHandle seekToFileOffset:self.seekTimeS.seekByteOffset];
    self.currentReadOffset = self.seekTimeS.seekByteOffset;
    [self.audioCore startAudioPlay];
}

#warning some online audios don't support seek time
- (void)playOnlineAudioWithURL:(NSURL*) URL seekTime:(double) requestSeekTime{
    self.downloadForPlaying = YES;
    
    if (requestSeekTime > 0) {
        self.seekTimeS = [self.audioCore shouldSeekToTime:requestSeekTime];
    } else {  // the begin to play online audio, clean the SeekTimeS and lastSeekTimeS.
        [self cleanSeekTimeS];
        [self cleanLastSeekTimeS];
    }
    RWFileS *fileS;
    @synchronized(self) {
        fileS = [self.fileManager shouldDownloadWithURL:URL seekByteOffset:self.seekTimeS.seekByteOffset lastSeekByteOffset:self.lastSeekTimeS.seekByteOffset currentWriteOffset:self.currentWriteOffset fileLength:self.fileLength datArray:self.datArray isSeekTime:self.seekTimeS.isShouldSeek];
    }
    
    if (self.seekTimeS.isShouldSeek) {  // this not begin to play an online audio
        EKLog(@"seektime = %f", requestSeekTime);
        
        if (fileS.shouldRedownload) {
            [self internalStop];
            EKLog(@"fileS.startOffset = %lld endOffset = %lld", fileS.startDownloadOffset, fileS.endDownloadOffset);
        } else {
            [self.audioCore stop];
        }
    } else {// to the situation when requestSeekTime is 0. means first time to play a audio
        [self setupInitParams];
        if (fileS.isFileAleadyDownLoadCompleted) {
            _fileLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:fileS.audioFilePath error:nil] fileSize];
            _fileExtension = [fileS.audioFilePath pathExtension];
            self.isLocalAudio = YES;
            self.downLoadPercent = 1.0;
            self.downloadForPlaying = NO;
        }
    }
    if (fileS.audioFilePath != nil && self.readHandle == nil) {
        self.readHandle = [NSFileHandle fileHandleForReadingAtPath:fileS.audioFilePath];
    }
    if (fileS.audioFilePath != nil && self.writeHandle == nil && !fileS.isFileAleadyDownLoadCompleted) {
        self.writeHandle = [NSFileHandle fileHandleForWritingAtPath:fileS.audioFilePath];
    }
    if (fileS.fileLength != 0) {
        _fileLength = fileS.fileLength;
        self.datArray = fileS.datArray;
    }
    if (fileS.audioFilePath != nil) {
        self.audioFilePath = fileS.audioFilePath;
    }
  
    //move the currentReadOffset after audio stoped, and if not to redownload but should seekTime,
    //restart the audio
    self.currentReadOffset = self.seekTimeS.seekByteOffset;
    
    self.lastSeekTimeS = self.seekTimeS;
    if (fileS == nil || !fileS.shouldRedownload) {
        [self.audioCore startAudioPlay];
    }
    
 
    if (!fileS.shouldRedownload) return;
    self.currentWriteOffset = fileS.startDownloadOffset;
    self.isLocalAudio = false;
    self.url = URL;
    //request a online audio
    [self setupURLConnectionWithFileHandle:fileS];
}

//request a online audio
- (void)setupURLConnectionWithFileHandle:(RWFileS *) fileS{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.url];
    //endDownloadOffset == -1 means the first time to request the audio, we don't know the fileLength.
    if (fileS.startDownloadOffset != 0 && fileS.endDownloadOffset != -1) {
        NSString *byteOffset = [NSString stringWithFormat:@"bytes=%lld-%lld", fileS.startDownloadOffset, fileS.endDownloadOffset];
        EKLog(@"set download range = %@",byteOffset);
        EKLog(@"currentWriteOffset = %lld", self.currentWriteOffset);
        EKLog(@"currentReadOffset = %lld",self.currentReadOffset);
        [request setValue:byteOffset forHTTPHeaderField:@"Range"];
        self.currentWriteOffset = fileS.startDownloadOffset;
        [self.writeHandle seekToFileOffset:fileS.startDownloadOffset];
    }
    
    self.netWorkthreadQueue = [[NSOperationQueue alloc] init];
    
    NSURLSessionConfiguration* defaultConfigObject = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *urlSession = [NSURLSession sessionWithConfiguration:defaultConfigObject delegate:self delegateQueue:self.netWorkthreadQueue];
    
    
    self.dataTask = [urlSession dataTaskWithRequest:request];
    
    [self.dataTask resume];
}

- (void)closeFileHandle {
    @synchronized(self) {// the network thread will affect this
        [self.writeHandle closeFile];
        self.writeHandle = nil; // must set nil, since the URLSession callback may be called
        [self.readHandle closeFile];
        self.readHandle = nil;
    }
    EKLog(@"AQTool -- close fileHandle completed");
}

- (void)cancelDownload {
    if(self.dataTask != nil){
        EKLog(@"begin dataTask cancel");
        [self.dataTask cancel];
        while(self.dataTask != nil) { // make sure the connection has close
            [NSThread sleepForTimeInterval:0.25];
        }
    }
    self.netWorkthreadQueue = nil;
    
    [self closeFileHandle];
}

- (void)deleteFile:(NSString *) filePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:filePath]) {
        NSError *error;
        [fileManager removeItemAtPath:filePath error:&error];
        if (error != nil) {
            EKErrorLog(@"fileDeleteError = %@",error);
        }
        EKLog(@"delete file - %@", filePath);
    }
}

#pragma mark interface
- (double)duration {
    return self.audioCore.duration;
}
- (double)playProgress {
    if (!([self.audioCore isPaused] || [self.audioCore isPlaying])) {
        return 0;
    }
    return [self.audioCore playProgress];
}

// this method for internal use, which wouldn't clean _duration, _fileLength, _fileExtension,
// _seekTimeS, _lastTimeS, _datArray
- (void)internalStop {
    [self.audioCore stop];
    [self cancelDownload];
    self.currentWriteOffset = 0;
    self.currentReadOffset = 0;
}

//this method for outside call
- (void)stop {
    [self setupInitParams];
}

- (void)pause {
    [self.audioCore pause];
}

- (BOOL)isPaused {
    return [self.audioCore isPaused];
}

- (BOOL)isPlaying {
    return [self.audioCore isPlaying];
}

- (BOOL)isIdle {
    return [self.audioCore isIdle];
}

- (BOOL)isFinishPlaySuccessfully {
    return [self.audioCore isFinishPlayingSuccessfully];
}

- (void)cleanCache {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:self.tempFileSaveFolder]) {
        return;
    }
    NSArray *tempFileList = [fileManager contentsOfDirectoryAtPath:self.tempFileSaveFolder error:nil];
    for (NSString* fileName in tempFileList) {
        NSString *filePath = [self.tempFileSaveFolder stringByAppendingPathComponent:fileName];
        [self deleteFile:filePath];
    }
}
@end
