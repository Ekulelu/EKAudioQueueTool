//
//  AudioQueueToolFileManager.m
//  AudioQueueTool
//
//  Created by Ekulelu on 15/10/30.
//  Copyright © 2015年 ekulelu. All rights reserved.
//

#import "EKAudioQueueToolFileManager.h"
#import "CommonCrypto/COmmonDigest.h"
#import "EKAudioQueueToolHeader.h"

#define datArraySymble @"datArray"
#define fileLengthSymble @"fileLength"

@implementation RWFileS
- (instancetype)initWithFilePath:(NSString *) audioFilePath datFilePath:(NSString *) datFilePath{
    if (self = [super init]) {
        _audioFilePath = audioFilePath;
        _datFilePath = datFilePath;
    }
    return self;
}

@end


@implementation EKAudioQueueToolFileManager


//called only when the audio file is not exist
- (RWFileS *)createFileWithRequestURL:(NSURL *) url extensionName:(NSString *) extensionName fileLength:(long long) fileLength{
    NSString *md5 = [self md5:url.path];
    NSString *audioFileName = [md5 stringByAppendingString:[NSString stringWithFormat:@".%@",extensionName]];
    NSString *datFileName = [md5 stringByAppendingString:[NSString stringWithFormat:@".dat"]];
    NSString *audioFilePath = [self.saveFolder stringByAppendingPathComponent:audioFileName];
    NSString *datFilePath = [self.saveFolder stringByAppendingPathComponent:datFileName];
    [[NSFileManager defaultManager] createFileAtPath:audioFilePath  contents:nil attributes:nil];
    
    RWFileS *fileS = [[RWFileS alloc] initWithFilePath:audioFilePath datFilePath:datFilePath];
    long long blockCount;
    if (fileLength % BlockDataSize == 0) {
        blockCount = fileLength / BlockDataSize;
    } else {
        blockCount = fileLength / BlockDataSize + 1;
    }
    fileS.datArray = [NSMutableArray array];
    for (long i = 0; i < blockCount; i++) {
        fileS.datArray[i] = [[NSNumber alloc] initWithBool:NO];
    }
    return fileS;
}


- (void)saveData:(NSData *) data WriteHandle:(NSFileHandle *) writeHandle offset:(const long long) currentWriteOffset datArray:(NSMutableArray *)datArray datFilePath:(NSString *) datFilePath fileLength: (long long) fileLength{
    [writeHandle seekToFileOffset:currentWriteOffset];
    [writeHandle writeData:data];
    //update datArray
    long startBlockIndex = currentWriteOffset / BlockDataSize;
    long endBlockIndex = (currentWriteOffset + data.length) / BlockDataSize;
     BOOL shouldUpdateDatFile = NO;
    for (long i = startBlockIndex; i < endBlockIndex ; i++) {
        datArray[i] = [[NSNumber alloc] initWithBool:YES];
        shouldUpdateDatFile = YES;
    }
   
    if (currentWriteOffset + data.length >= fileLength) {
        [datArray removeLastObject];
        [datArray addObject:[[NSNumber alloc] initWithBool:YES]];
        shouldUpdateDatFile = YES;
    }
    if (shouldUpdateDatFile) {
        NSMutableData *mutableData = [[NSMutableData alloc] init];
        NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:mutableData];
        [archiver encodeObject:datArray forKey:datArraySymble];
        [archiver encodeObject:[[NSNumber alloc] initWithLongLong:fileLength] forKey:fileLengthSymble];
        [archiver finishEncoding];
        [mutableData writeToFile:datFilePath atomically:NO];
    }
}


//this method check the if has cache, it decide whether download audio or not.
//if has imcompleted temp file, calculate the download range.
//if has a completed file, return the file path, and don't download.
//
- (RWFileS *)shouldDownloadWithURL:(NSURL *) url seekByteOffset:(long long) seekByteOffset lastSeekByteOffset:(long long) lastseekByteOffset  currentWriteOffset:(long long) currentWriteOffset fileLength:(long long) fileLength datArray:(NSMutableArray *) datArray isSeekTime:(BOOL) isSeekTime{
    NSString *fileMD5 = [self md5:url.path];
    NSString *audioFilePath = nil;
    NSString *datFilePath = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *fileList = [fileManager contentsOfDirectoryAtPath:self.saveFolder error:&error];
    for (NSString *fileName in fileList) {
        if([[fileName stringByDeletingPathExtension] isEqualToString:fileMD5]) {
            if ([[fileName pathExtension] isEqualToString:@"dat"]) {
                datFilePath = [self.saveFolder stringByAppendingPathComponent:fileName];
            } else {
                audioFilePath = [self.saveFolder stringByAppendingPathComponent:fileName];
                if (datFilePath == nil) {
                    NSString *datFileName = [[fileName stringByDeletingPathExtension] stringByAppendingString:@".dat"];
                    //we don't sure the dat file exist.
                    datFilePath = [self.saveFolder stringByAppendingPathComponent:datFileName];
                }
                break;
            }
        }
    }
    //if audioFile isn't exist, but datFile exist, delete the datFile.
    if (audioFilePath == nil && datFilePath != nil) {
        NSError *error;
        [fileManager removeItemAtPath:datFilePath error:&error];
        if (error != nil) {
            EKErrorLog(@"fileDeleteError = %@",error);
        }
    }
    RWFileS *fileS = [[RWFileS alloc] init];
    if (audioFilePath == nil) {  //The audio file isn't exist. we should download.
        fileS.startDownloadOffset = 0;
        fileS.endDownloadOffset = -1;  //-1 means we don't konw the file length.
        fileS.shouldRedownload = YES;
        return fileS;
    }
    //The audio file has downloaded completely. Return the file path, and don't download.
    if (audioFilePath != nil && ![fileManager fileExistsAtPath:datFilePath]) {
        fileS.shouldRedownload = NO;
        fileS.audioFilePath = audioFilePath;
        fileS.fileAleadyDownLoadCompleted = YES;
        return fileS;
    }
    
    //the audio is not download completely. Calculate the download range.
    fileS.audioFilePath = audioFilePath;
    fileS.datFilePath = datFilePath;
    
    if (datArray == nil) {
        NSMutableData *mutableData = [[NSMutableData alloc] initWithContentsOfFile:datFilePath];
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:mutableData];
        fileS.datArray = [unarchiver decodeObjectForKey:datArraySymble];
        fileS.fileLength = [(NSNumber *)[unarchiver decodeObjectForKey:fileLengthSymble] longLongValue];
        [unarchiver finishDecoding];
    } else {
        fileS.datArray = datArray;
        fileS.fileLength = fileLength;
    }
    
    
    //search the start and end download range
    long seekTimeIndex = seekByteOffset / BlockDataSize;
    long lastSeekTimeIndex = lastseekByteOffset / BlockDataSize;
    
    if (!isSeekTime) {
        fileS.shouldRedownload = YES;
        //find the startDownloadOffset
        [self findStartDownloadOffset:fileS];
        //find the endDownloadOffset
        [self findEndDownloadOffset:fileS fileLength:fileS.fileLength];
        EKLog(@"no seektime");
        return fileS;
    }
    
    if ([fileS.datArray[seekTimeIndex] boolValue] == NO || seekByteOffset > currentWriteOffset) {
        // the block seek to is not download, or seekOffset large than currentWriteOffset.
        fileS.startDownloadOffset = seekTimeIndex * BlockDataSize;
        //find the endDownloadOffset
        [self findEndDownloadOffset:fileS fileLength:fileLength];
        fileS.shouldRedownload = YES;
        EKLog(@"move to no download part or seekOffset large than currentWriteOffset, %lld - %lld", fileS.startDownloadOffset, fileS.endDownloadOffset);
        
    } else if (seekByteOffset > lastseekByteOffset) {
        //this also means the currentWriteOffset large than the seekTimeOffset
        fileS.shouldRedownload = NO;
        EKLog(@"seek ahead to download part and seekOffset large than lastseekByteOffset \n seekByteOffset = %lld, lastSeekOffset= %lld", seekByteOffset, lastseekByteOffset);
        
    } else if(seekTimeIndex < lastSeekTimeIndex){
        // this situation, the play must be starting. and seek back.
        // we calculate the first not download block between seekTimeIndex and lastSeekTimeIndex.
        // and the last not download block in the file.
        fileS.shouldRedownload = NO;
        for (long i = seekTimeIndex; i < lastSeekTimeIndex; i++) {
            if ([fileS.datArray[i] boolValue] == NO) {
                fileS.shouldRedownload = YES;
                [self findStartDownloadOffset:fileS];

                [self findEndDownloadOffset:fileS fileLength:fileLength];
                 EKLog(@"seek to back no download part, %lld - %lld", fileS.startDownloadOffset, fileS.endDownloadOffset);
                break;
            }
        }
        
    } else if (seekTimeIndex == lastSeekTimeIndex){
        // seek the same time, but the block hasn't download completed.
        // we continue the download connection.
        fileS.shouldRedownload = NO;
        EKLog(@"seek the same time");
        
    } else {
        //Other situation I missed. If you see the situatuion, please contact me.
        EKErrorLog(@"Error situation to be fix");
        NSString *errorLog = [NSString stringWithFormat:@"seekTimeOffset = @%lld \n lastSeekTimeOffset = %lld \n currentWrite = %lld \n fileLength = %lld isSeekTime = %d", seekByteOffset, lastseekByteOffset, currentWriteOffset, fileLength, isSeekTime];
        NSString *path = [DocumentPath stringByAppendingPathComponent:@"errorLog.log"];
        [errorLog writeToFile:path atomically:YES encoding:NSUnicodeStringEncoding error:nil];
        NSAssert(YES, errorLog);
    }
    
    return fileS;
}

- (void)findStartDownloadOffset:(RWFileS *) fileS {
    for (long i = 0; i < fileS.datArray.count; i++) {
        if ([fileS.datArray[i] boolValue] == NO) {
            fileS.startDownloadOffset = i * BlockDataSize;
            break;
        }
    }
}

- (void)findEndDownloadOffset:(RWFileS *) fileS fileLength:(long long) fileLength{
    for (long i = (fileS.datArray.count - 1); i > 0; i--) {
        if ([fileS.datArray[i] boolValue] == NO) {
            fileS.endDownloadOffset = (i + 1)* BlockDataSize;
            if (fileS.endDownloadOffset > fileLength) {
                fileS.endDownloadOffset = fileLength;
            }
            break;
        }
    }
}

- (NSString *)searchFileWithURL:(NSURL *) url {
    
    NSString *filePath = [self md5:url.path];
    NSString *result = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *fileList = [fileManager contentsOfDirectoryAtPath:self.saveFolder error:&error];
    for (NSString *fileName in fileList) {
        if([[fileName stringByDeletingPathExtension] isEqualToString:filePath]) {
            result = fileName;
            break;
        }
    }
    if (result != nil) {
        return [self.saveFolder stringByAppendingPathComponent:result];
    }
    return nil;
}

- (NSString *)searchFileWithMD5:(NSString *) filePath {
    return nil;
}

#pragma mark md5
- (NSString*)md5:(NSString *) input {
    const char* str = [input UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, strlen(str), result);
    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH];
    
    for(int i = 0; i<CC_MD5_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02X",result[i]];
    }
    return ret;
}

@end
