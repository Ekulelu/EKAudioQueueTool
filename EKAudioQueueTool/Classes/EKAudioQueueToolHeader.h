//
//  Header.h
//  AudioQueueTool2
//
//  Created by 黄政 on 15/10/30.
//  Copyright © 2015年 ekulelu. All rights reserved.
//

#ifndef Header_h
#define EKErrorLog(...) NSLog(__VA_ARGS__)

#ifdef DEBUG
#define EKLog(...) NSLog(__VA_ARGS__)

#else
#define EKLog(...)
#endif

#define DocumentPath NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject
#define CachePath NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject

#define Header_h


#endif /* Header_h */
