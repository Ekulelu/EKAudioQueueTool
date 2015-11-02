//
//  AudioQueueToolFileManager.h
//  AudioQueueTool
//
//  Created by Ekulelu on 15/10/30.
//  Copyright © 2015年 ekulelu. All rights reserved.
//

#import <Foundation/Foundation.h>

#define BlockDataSize 204800

@interface RWFileS: NSObject
@property (nonatomic, copy) NSString* audioFilePath;
@property (nonatomic, copy) NSString* datFilePath;
@property (nonatomic, assign) BOOL shouldRedownload;
@property (nonatomic, strong) NSMutableArray* datArray;
@property (nonatomic, assign) long long startDownloadOffset;
@property (nonatomic, assign) long long endDownloadOffset;
@property (nonatomic, assign) long long fileLength;
@property (nonatomic, assign, getter=isFileAleadyDownLoadCompleted) BOOL fileAleadyDownLoadCompleted;
@end

@interface EKAudioQueueToolFileManager : NSObject

@property (nonatomic, copy) NSString* saveFolder;



- (NSString *)searchFileWithURL:(NSURL *) url;
- (NSString *)searchFileWithMD5:(NSString *) md5;
- (RWFileS *)createFileWithRequestURL:(NSURL *) url extensionName:(NSString *) extensionName fileLength:(long long) fileLength;

- (void)saveData:(NSData *) data WriteHandle:(NSFileHandle *) writeHandle offset:(const long long) currentWriteOffset datArray:(NSMutableArray *)datArray datFilePath:(NSString *) datFilePath fileLength: (long long) fileLength;

- (RWFileS *)shouldDownloadWithURL:(NSURL *) url seekByteOffset:(long long) seekByteOffset lastSeekByteOffset:(long long) lastseekByteOffset currentWriteOffset:(long long) currentWriteOffset fileLength:(long long) fileLength datArray:(NSMutableArray *) datArray isSeekTime:(BOOL) isSeekTime;


@end
