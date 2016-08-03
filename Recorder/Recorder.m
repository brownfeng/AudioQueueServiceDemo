//
//  main.m
//  Recorder
//
//  Created by brownfeng on 16/8/3.
//  Copyright © 2016年 brownfeng. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

static const int kNumberBuffers = 3;
typedef struct AQRecorderState {
    AudioStreamBasicDescription  mDataFormat;
    AudioQueueRef                mQueue;
    AudioQueueBufferRef          mBuffers[kNumberBuffers];
    AudioFileID                  mAudioFile;
    UInt32                       bufferByteSize;
    SInt64                       mCurrentPacket;
    bool                         mIsRunning;
} AQRecorderState;


static void HandleInputBuffer (void                                *aqData,
                               AudioQueueRef                       inAQ,
                               AudioQueueBufferRef                 inBuffer,
                               const AudioTimeStamp                *inStartTime,
                               UInt32                              inNumPackets,
                               const AudioStreamPacketDescription  *inPacketDesc
){
    AQRecorderState *pAqData = (AQRecorderState *) aqData;
    if(inNumPackets == 0 && pAqData->mDataFormat.mBytesPerPacket!=0) {
        inNumPackets = inBuffer->mAudioDataByteSize / pAqData->mDataFormat.mBytesPerPacket;
    }
    
    if (AudioFileWritePackets (pAqData->mAudioFile,false,inBuffer->mAudioDataByteSize,inPacketDesc,pAqData->mCurrentPacket,&inNumPackets, inBuffer->mAudioData) == noErr) {
        pAqData->mCurrentPacket += inNumPackets;
    }
    if (pAqData->mIsRunning == 0)
        return;
    
    AudioQueueEnqueueBuffer(pAqData->mQueue,inBuffer,0,NULL);
}


void DeriveBufferSize (AudioQueueRef audioQueue,AudioStreamBasicDescription *ASBDescription, Float64 seconds,UInt32                       *outBufferSize) {
    static const int maxBufferSize = 0x50000;
 
    int maxPacketSize = (*ASBDescription).mBytesPerPacket;
    if (maxPacketSize == 0) {
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty(audioQueue,kAudioQueueProperty_MaximumOutputPacketSize,&maxPacketSize,&maxVBRPacketSize);
    }
    
    Float64 numBytesForTime =
    (*ASBDescription).mSampleRate * maxPacketSize * seconds;
    *outBufferSize = numBytesForTime < maxBufferSize ? numBytesForTime : maxBufferSize;
}

OSStatus SetMagicCookieForFile(AudioQueueRef inQueue, AudioFileID  inFile) {
    OSStatus result = noErr;
    UInt32 cookieSize;
    if (AudioQueueGetPropertySize (inQueue,kAudioQueueProperty_MagicCookie,&cookieSize) == noErr) {
        char* magicCookie = (char *) malloc (cookieSize);
        if (AudioQueueGetProperty (inQueue,kAudioQueueProperty_MagicCookie,magicCookie,&cookieSize) == noErr){
            result = AudioFileSetProperty (inFile,kAudioFilePropertyMagicCookieData,cookieSize,magicCookie);
        }

        free (magicCookie);
    }
    return result;
}


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        AQRecorderState aqData = {0};
        //设置formatter
        aqData.mDataFormat.mFormatID         = kAudioFormatLinearPCM;
        aqData.mDataFormat.mSampleRate       = 44100.0;
        aqData.mDataFormat.mChannelsPerFrame = 2;
        aqData.mDataFormat.mBitsPerChannel   = 16;
        aqData.mDataFormat.mBytesPerPacket   = aqData.mDataFormat.mBytesPerFrame =  aqData.mDataFormat.mChannelsPerFrame * sizeof (SInt16);
        aqData.mDataFormat.mFramesPerPacket  = 1;
        AudioFileTypeID fileType= kAudioFileAIFFType;
        aqData.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
        
        AudioQueueNewInput (&aqData.mDataFormat,HandleInputBuffer,&aqData,NULL,kCFRunLoopCommonModes,0,&aqData.mQueue);
        
        UInt32 dataFormatSize = sizeof (aqData.mDataFormat);
        AudioQueueGetProperty (aqData.mQueue,kAudioQueueProperty_StreamDescription,&aqData.mDataFormat,&dataFormatSize);
        
        CFURLRef audioFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, CFSTR("output.caf"), kCFURLPOSIXPathStyle, false);
        
        AudioFileCreateWithURL(audioFileURL,fileType, &aqData.mDataFormat, kAudioFileFlags_EraseFile, &aqData.mAudioFile);
        
        DeriveBufferSize(aqData.mQueue, &aqData.mDataFormat, 0.5,  &aqData.bufferByteSize);
        
        for (int i = 0; i < kNumberBuffers; ++i) {
            AudioQueueAllocateBuffer(aqData.mQueue,aqData.bufferByteSize,&aqData.mBuffers[i]);
            AudioQueueEnqueueBuffer (aqData.mQueue,aqData.mBuffers[i], 0, NULL);
        }
        
        aqData.mCurrentPacket = 0;
        aqData.mIsRunning = true;
        AudioQueueStart (aqData.mQueue,NULL);
        
        printf("Recording, press <return> to stop:\n");
        getchar();
        printf("* recording done *\n");
        
        AudioQueueStop ( aqData.mQueue,true);
        aqData.mIsRunning = false;
        AudioQueueDispose (aqData.mQueue, true );
        AudioFileClose (aqData.mAudioFile);
    }
    return 0;
}
