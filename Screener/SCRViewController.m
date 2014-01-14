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

- (id)initWithNibName:(NSString*)name bundle:(NSBundle*)bundle {
    self = [super initWithNibName:name bundle:bundle];
    if (self) {
        displayQueue = dispatch_queue_create("com.chordedconstructions.ScreenerCaptureQueue", DISPATCH_QUEUE_SERIAL);
        if (!displayQueue) {
            NSLog(@"ERROR - failed to create display queue");
            exit(EXIT_FAILURE);
        }

        // TODO - remove after NSPopUpButton is added to xib
        [self selectDisplay:CGMainDisplayID()];
        [self start];
    }
    return self;
}

- (void)dealloc {
    if (!displayStream) {
        return;
    }

    [self stop];

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

    CFDictionaryRef properties = (__bridge CFDictionaryRef)(@{
        (NSString*)kCGDisplayStreamQueueDepth : @20,
//        (NSString*)kCGDisplayStreamMinimumFrameTime : minframetime,
//        (NSString*)kCGDisplayStreamPreserveAspectRatio: @NO
    });
    displayStream = CGDisplayStreamCreateWithDispatchQueue(self.displayID, pixelWidth, pixelHeight, 'BGRA', properties, displayQueue, ^(CGDisplayStreamFrameStatus status, uint64_t displayTime, IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef) {
        if (status == kCGDisplayStreamFrameStatusFrameComplete && frameSurface) {
            // As per CGDisplayStreams header
            IOSurfaceIncrementUseCount(frameSurface);
            // -emitNewFrame: retains the frame
            [self emitNewFrame:frameSurface];
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

- (void)start {
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

- (void)stop {
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

- (IOSurfaceRef)getAndSetFrameSurface:(IOSurfaceRef)new {
    BOOL success = false;
    IOSurfaceRef old;
    do {
        old = updatedSurface;
        success = OSAtomicCompareAndSwapPtrBarrier(old, new, (void * volatile *)&updatedSurface);
    } while (!success);
    return old;
}

- (IOSurfaceRef)copyNewFrame {
    return [self getAndSetFrameSurface:NULL];
}

- (void)emitNewFrame:(IOSurfaceRef)frameSurface {
    CFRetain(frameSurface);
    [self getAndSetFrameSurface:frameSurface];
}

#pragma mark -

- (void)publishFrameSurface {
    IOSurfaceRef frameSurface = [self copyNewFrame];
    if (!frameSurface) {
        return;
    }

    // TODO - send to server

    CFRelease(frameSurface);
}

@end
