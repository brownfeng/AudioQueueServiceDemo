//
//  main.m
//  Player
//
//  Created by brownfeng on 16/8/3.
//  Copyright © 2016年 brownfeng. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#define kPlaybackFileLocation CFSTR("./output.caf")
static const int kNumberBuffers = 3;

typedef struct AQPlayerState {
    AudioStreamBasicDescription   mDataFormat;
    AudioQueueRef                 mQueue;
    AudioQueueBufferRef           mBuffers[kNumberBuffers];
    AudioFileID                   mAudioFile;
    UInt32                        bufferByteSize;
    SInt64                        mCurrentPacket;
    UInt32                        mNumPacketsToRead;
    AudioStreamPacketDescription  *mPacketDescs;
    bool                          mIsRunning;
}AQPlayerState;


#pragma mark utility functions
static void CheckError(OSStatus error, const char *operation) {
    if(error == noErr) return;
    
    char errorString[20];
    
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
        
    } else { // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
    }
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    exit(1);
}


//The Playback Audio Queue Callback
static void HandleOutputBuffer(void* aqData,AudioQueueRef inAQ,AudioQueueBufferRef inBuffer){
    AQPlayerState *pAqData = (AQPlayerState *) aqData;
//    if (pAqData->mIsRunning == 0) return; // 注意苹果官方文档这里有这一句,应该是有问题,这里应该是判断如果pAqData->isDone??
    
    UInt32 numBytesReadFromFile;
    UInt32 numPackets = pAqData->mNumPacketsToRead;
    CheckError(AudioFileReadPackets(pAqData->mAudioFile,false,&numBytesReadFromFile,pAqData->mPacketDescs,pAqData->mCurrentPacket,&numPackets,inBuffer->mAudioData), "AudioFileReadPackets");
    
    if (numPackets > 0) {
        inBuffer->mAudioDataByteSize = numBytesReadFromFile;
        AudioQueueEnqueueBuffer(inAQ,inBuffer,(pAqData->mPacketDescs ? numPackets : 0),pAqData->mPacketDescs);
        pAqData->mCurrentPacket += numPackets;
    } else {
        if (pAqData->mIsRunning) {
            
        }
        AudioQueueStop(inAQ,false);
        pAqData->mIsRunning = false; 
    }
}

//计算buffer size
void DeriveBufferSize (AudioStreamBasicDescription inDesc,UInt32 maxPacketSize,Float64 inSeconds,UInt32 *outBufferSize,UInt32 *outNumPacketsToRead) {
    
    static const int maxBufferSize = 0x10000;
    static const int minBufferSize = 0x4000;
    
    if (inDesc.mFramesPerPacket != 0) {
        Float64 numPacketsForTime = inDesc.mSampleRate / inDesc.mFramesPerPacket * inSeconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    } else {
        *outBufferSize = maxBufferSize > maxPacketSize ? maxBufferSize : maxPacketSize;
    }
    
    if (*outBufferSize > maxBufferSize && *outBufferSize > maxPacketSize){
        *outBufferSize = maxBufferSize;
    }
    else {
        if (*outBufferSize < minBufferSize){
            *outBufferSize = minBufferSize;
        }
    }
    
    *outNumPacketsToRead = *outBufferSize / maxPacketSize;
}

static void MyCopyEncoderCookieToQueue(AudioFileID theFile,AudioQueueRef queue) {
    UInt32 cookieSize;
    OSStatus result = AudioFileGetPropertyInfo(theFile,kAudioFilePropertyMagicCookieData,&cookieSize,NULL);
    
    if (result == noErr && cookieSize > 0) {
        char* magicCookie = (char *) malloc(cookieSize);
        AudioFileGetProperty(theFile,kAudioFilePropertyMagicCookieData,&cookieSize,magicCookie);
        AudioQueueSetProperty(queue,kAudioQueueProperty_MagicCookie,magicCookie,cookieSize);
        free (magicCookie);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        AQPlayerState aqData;
       
        CFURLRef audioFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,kPlaybackFileLocation,kCFURLPOSIXPathStyle,false);
        
        CheckError(AudioFileOpenURL(audioFileURL,kAudioFileReadPermission,0,&aqData.mAudioFile), "AudioFileOpenURL");
        CFRelease (audioFileURL);
        
        UInt32 dataFormatSize = sizeof(aqData.mDataFormat);
        CheckError(AudioFileGetProperty(aqData.mAudioFile,kAudioFilePropertyDataFormat,&dataFormatSize,&aqData.mDataFormat),"AudioFileGetProperty");
        
        CheckError(AudioQueueNewOutput(&aqData.mDataFormat,HandleOutputBuffer,&aqData,CFRunLoopGetCurrent(),kCFRunLoopCommonModes,0,&aqData.mQueue),"");
        
        UInt32 maxPacketSize;
        UInt32 propertySize = sizeof(maxPacketSize);
        CheckError(AudioFileGetProperty(aqData.mAudioFile,kAudioFilePropertyPacketSizeUpperBound,&propertySize,&maxPacketSize),"AudioFileGetProperty");
        
        DeriveBufferSize(aqData.mDataFormat,maxPacketSize,0.5,&aqData.bufferByteSize,&aqData.mNumPacketsToRead);
        
        bool isFormatVBR = (aqData.mDataFormat.mBytesPerPacket == 0 ||aqData.mDataFormat.mFramesPerPacket == 0);
        
        if (isFormatVBR) {
            aqData.mPacketDescs =(AudioStreamPacketDescription*) malloc (aqData.mNumPacketsToRead * sizeof (AudioStreamPacketDescription));
        } else {
            aqData.mPacketDescs = NULL;
        }
        
        
        //Set a Magic Cookie for a Playback Audio Queue
        MyCopyEncoderCookieToQueue(aqData.mAudioFile, aqData.mQueue);

        //Allocate and Prime Audio Queue Buffers
        aqData.mCurrentPacket = 0;
        
        for (int i = 0; i < kNumberBuffers; ++i) {
            CheckError(AudioQueueAllocateBuffer(aqData.mQueue,aqData.bufferByteSize,&aqData.mBuffers[i]),"AudioQueueAllocateBuffer");
            HandleOutputBuffer(&aqData,aqData.mQueue,aqData.mBuffers[i]);
        }
        
        
        Float32 gain = 10.0;
        
        // Optionally, allow user to override gain setting here
        AudioQueueSetParameter (
                                aqData.mQueue,
                                kAudioQueueParam_Volume,
                                gain
                                );
        
        
        //Start and Run an Audio Queue
        aqData.mIsRunning = true;
        CheckError(AudioQueueStart(aqData.mQueue,NULL),"AudioQueueStart failed");

        printf("Playing...\n");

        do {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.25,false);
        } while (aqData.mIsRunning);
        
        CFRunLoopRunInMode(kCFRunLoopDefaultMode,2,false);
        
        
        //Clean Up After Playing
        CheckError(AudioQueueStop(aqData.mQueue,TRUE),"AudioQueueStop failed");
        AudioQueueDispose (aqData.mQueue,true);
        AudioFileClose (aqData.mAudioFile);
        free (aqData.mPacketDescs);
        
        printf("done!!");
    }
    return 0;
}
