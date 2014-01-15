//
//  SCRViewController.m
//  Screener
//
//  Created by Jean-Pierre Mouilleseaux on 14 Jan 2014.
//  Copyright (c) 2014 Chorded Constructions. All rights reserved.
//

#import "SCRViewController.h"
@import Quartz;

@interface SCRViewController () {
    CVDisplayLinkRef displayLink;
    dispatch_queue_t displayQueue;
    CGDisplayStreamRef displayStream;
    IOSurfaceRef updatedSurface;
}
@property (nonatomic) CGDirectDisplayID displayID;
@end

@implementation SCRViewController


- (void)awakeFromNib {
    displayQueue = dispatch_queue_create("com.chordedconstructions.ScreenerCaptureQueue", DISPATCH_QUEUE_SERIAL);
    if (!displayQueue) {
        NSLog(@"ERROR - failed to create display queue");
        exit(EXIT_FAILURE);
    }

    // TODO - populate popup with display names
    [self selectDisplay:CGMainDisplayID()];
    [self startDisplayStream];
}

- (void)dealloc {
    if (!displayStream) {
        return;
    }

    [self stopDisplayStream];

    CFRelease(displayStream);
    displayStream = NULL;

    CVDisplayLinkRelease(displayLink);
    displayLink = NULL;
}

#pragma mark -

- (void)selectDisplay:(CGDirectDisplayID)displayID {
    if (displayID == self.displayID) {
        return;
    }

    if (displayStream) {
        CFRelease(displayStream);
        displayStream = NULL;
    }

    self.displayID = displayID;

    // create stream
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(self.displayID);
    size_t pixelWidth = CGDisplayModeGetPixelWidth(mode);
    size_t pixelHeight = CGDisplayModeGetPixelHeight(mode);
    CGDisplayModeRelease(mode);
    mode = NULL;

    NSDictionary* properties = (@{
//        (NSString*)kCGDisplayStreamQueueDepth: @20,
//        (NSString*)kCGDisplayStreamMinimumFrameTime: @(1.0f/30.0f),
//        (NSString*)kCGDisplayStreamShowCursor: (NSObject*)kCFBooleanFalse,
    });
    displayStream = CGDisplayStreamCreateWithDispatchQueue(self.displayID, pixelWidth, pixelHeight, 'BGRA', (__bridge CFDictionaryRef)properties, displayQueue, ^(CGDisplayStreamFrameStatus status, uint64_t displayTime, IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef) {
        if (status == kCGDisplayStreamFrameStatusFrameComplete && frameSurface) {
            [self emitFrame:frameSurface];
        }
    });

    // create display link
    CVReturn error = CVDisplayLinkCreateWithCGDisplay(self.displayID, &displayLink);
    if (error != kCVReturnSuccess) {
        NSLog(@"ERROR - failed to create display link with error %d", error);
        displayLink = NULL;
        exit(EXIT_FAILURE);
    }
    error = CVDisplayLinkSetOutputCallback(displayLink, DisplayLinkCallback, (__bridge void*)self);
    if (error != kCVReturnSuccess) {
        NSLog(@"ERROR - failed to link display link to callback with error %d", error);
        displayLink = NULL;
        exit(EXIT_FAILURE);
    }
}

#pragma mark -

CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp* inNow, const CVTimeStamp* inOutputTime, CVOptionFlags flagsIn, CVOptionFlags* flagsOut, void* displayLinkContext) {
    [(__bridge SCRViewController*)displayLinkContext publishFrameSurface];
    return kCVReturnSuccess;
}

- (void)startDisplayStream {
    if (!displayStream) {
        return;
    }

    // start display link
    CVReturn err = CVDisplayLinkStart(displayLink);
    if (err != kCVReturnSuccess) {
        NSLog(@"ERROR - failed to start display link with error %d", err);
        exit(EXIT_FAILURE);
    }

    // start stream
    CGError error = CGDisplayStreamStart(displayStream);
    if (error != kCGErrorSuccess) {
        NSLog(@"ERROR - failed to start display stream with error %d", error);
        exit(EXIT_FAILURE);
    }
}

- (void)stopDisplayStream {
    if (!displayStream) {
        return;
    }

    // stop display link
    CVReturn err = CVDisplayLinkStop(displayLink);
    if (err != kCVReturnSuccess) {
        NSLog(@"ERROR - failed to stop display link with error %d", err);
        exit(EXIT_FAILURE);
    }

    // stop stream
    CGError error = CGDisplayStreamStop(displayStream);
    if (error != kCGErrorSuccess) {
        NSLog(@"ERROR - failed to stop display stream with error %d", error);
        exit(EXIT_FAILURE);
    }
}

#pragma mark -

- (IOSurfaceRef)getAndSetFrame:(IOSurfaceRef)surface {
    BOOL status = NO;
    IOSurfaceRef oldSurface;
    do {
        oldSurface = updatedSurface;
        status = OSAtomicCompareAndSwapPtrBarrier(oldSurface, surface, (void * volatile *)&updatedSurface);
    } while (!status);
    return oldSurface;
}

- (IOSurfaceRef)copyFrame {
    return [self getAndSetFrame:NULL];
}

- (void)emitFrame:(IOSurfaceRef)surface {
    CFRetain(surface);
    [self getAndSetFrame:surface];
}

#pragma mark -

- (void)publishFrameSurface {
    IOSurfaceRef frameSurface = [self copyFrame];
    if (!frameSurface) {
        return;
    }

    // TODO - send to server

    CFRelease(frameSurface);
}

@end
