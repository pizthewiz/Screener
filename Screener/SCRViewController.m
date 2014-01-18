//
//  SCRViewController.m
//  Screener
//
//  Created by Jean-Pierre Mouilleseaux on 14 Jan 2014.
//  Copyright (c) 2014 Chorded Constructions. All rights reserved.
//

#import "SCRViewController.h"
@import Quartz;

static CGDirectDisplayID const kSCRDisplayIDNone = 0;
static void* SelectionIndexContext = &SelectionIndexContext;

@interface SCRViewController () {
    CVDisplayLinkRef displayLink;
    dispatch_queue_t displayQueue;
    CGDisplayStreamRef displayStream;
    IOSurfaceRef updatedSurface;
}
@property (nonatomic) CGDirectDisplayID display;
@end

@implementation SCRViewController

- (void)awakeFromNib {
    displayQueue = dispatch_queue_create("com.chordedconstructions.ScreenerCaptureQueue", DISPATCH_QUEUE_SERIAL);
    if (!displayQueue) {
        NSLog(@"ERROR - failed to create display queue");
        exit(EXIT_FAILURE);
    }

    [self setupDisplayList];
    CGDisplayRegisterReconfigurationCallback(DisplayReconfigurationCallback, (__bridge void*)(self));

    [self.displayArrayController addObserver:self forKeyPath:@"selectionIndex" options:NSKeyValueObservingOptionNew context:SelectionIndexContext];
}

- (void)dealloc {
    [self.displayArrayController removeObserver:self forKeyPath:@"selectionIndex" context:SelectionIndexContext];

    // reuse cleanup from -selectDisplay:
    [self selectDisplay:kSCRDisplayIDNone];
}

#pragma mark -

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context {
    if (context == SelectionIndexContext) {
        [self displaySelectionDidChange:nil];
    }
}

#pragma mark -

void DisplayReconfigurationCallback(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void* userInfo) {
    // only pay attention to add and remove notices
    if (flags & kCGDisplayBeginConfigurationFlag || !(flags & kCGDisplayAddFlag || flags & kCGDisplayRemoveFlag)) {
        return;
    }
    [(__bridge SCRViewController*)userInfo setupDisplayList];
}

- (void)setupDisplayList {
    uint32_t displayCount;
    CGError error = CGGetOnlineDisplayList(0, NULL, &displayCount);
    if (error != kCGErrorSuccess) {
        NSLog(@"ERROR - failed to get online display list");
        exit(EXIT_FAILURE);
    }
    CGDirectDisplayID* displays = (CGDirectDisplayID*)calloc(displayCount, sizeof(CGDirectDisplayID));
    error = CGGetOnlineDisplayList(displayCount, displays, &displayCount);
    if (error != kCGErrorSuccess) {
        NSLog(@"ERROR - failed to get online display list");
        exit(EXIT_FAILURE);
    }

    NSMutableArray* displayList = [[NSMutableArray alloc] init];
    [displayList addObject:@{@"name": @"- NONE -", @"id": @(kSCRDisplayIDNone)}];

    for (NSUInteger idx = 0; idx < displayCount; idx++) {
        CGDirectDisplayID display = displays[idx];

        // ignore deprecated warning on CGDisplayIOServicePort, no replacement has been provided!
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        NSDictionary* deviceInfo = (__bridge_transfer NSDictionary*)IODisplayCreateInfoDictionary(CGDisplayIOServicePort(display), kIODisplayOnlyPreferredName);
#pragma clang diagnostic pop

        NSDictionary* localizedNames = deviceInfo[@kDisplayProductName];
        NSString* screenName = ([localizedNames count] > 0) ? localizedNames[[localizedNames allKeys][0]] : @"Unknown";
        [displayList addObject:@{@"name": screenName, @"id": @(display)}];
    }
    free(displays);

    [self.displayArrayController setContent:displayList];
}

- (void)displaySelectionDidChange:(id)sender {
    NSDictionary* displayDescriptor = [self.displayArrayController.selectedObjects firstObject];
    CGDirectDisplayID display = [displayDescriptor[@"id"] unsignedIntValue];

    // bail if the selection hasn't changed
    if (self.display == display) {
        return;
    }

    [self selectDisplay:display];
    [self startDisplayStream];
}

#pragma mark -

- (void)selectDisplay:(CGDirectDisplayID)display {
    [self stopDisplayStream];

    if (displayStream) {
        CFRelease(displayStream);
        displayStream = NULL;
    }

    if (displayLink) {
        CVDisplayLinkRelease(displayLink);
        displayLink = NULL;
    }

    self.display = display;

    if (self.display == kSCRDisplayIDNone) {
        // poke the view to refresh
        [self.glView drawRect:NSZeroRect];
        return;
    }

    // create stream
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(self.display);
    size_t pixelWidth = CGDisplayModeGetPixelWidth(mode);
    size_t pixelHeight = CGDisplayModeGetPixelHeight(mode);
    CGDisplayModeRelease(mode);
    mode = NULL;

    NSDictionary* properties = (@{
//        (NSString*)kCGDisplayStreamQueueDepth: @20,
//        (NSString*)kCGDisplayStreamMinimumFrameTime: @(1.0f/30.0f),
//        (NSString*)kCGDisplayStreamShowCursor: (NSObject*)kCFBooleanFalse,
    });
    displayStream = CGDisplayStreamCreateWithDispatchQueue(self.display, pixelWidth, pixelHeight, 'BGRA', (__bridge CFDictionaryRef)properties, displayQueue, ^(CGDisplayStreamFrameStatus status, uint64_t displayTime, IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef) {
        if (status == kCGDisplayStreamFrameStatusFrameComplete && frameSurface) {
            [self emitFrame:frameSurface];
        }
    });

    // create display link
    CVReturn error = CVDisplayLinkCreateWithCGDisplay(self.display, &displayLink);
    if (error != kCVReturnSuccess) {
        NSLog(@"ERROR - failed to create display link with error %d", error);
        displayLink = NULL;
        exit(EXIT_FAILURE);
    }
    error = CVDisplayLinkSetOutputCallback(displayLink, DisplayLinkCallback, (__bridge void*)(self));
    if (error != kCVReturnSuccess) {
        NSLog(@"ERROR - failed to link display link to callback with error %d", error);
        displayLink = NULL;
        exit(EXIT_FAILURE);
    }
}

#pragma mark -

CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp* inNow, const CVTimeStamp* inOutputTime, CVOptionFlags flagsIn, CVOptionFlags* flagsOut, void* displayLinkContext) {
    [(__bridge SCRViewController*)displayLinkContext publishFrame];
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

- (void)publishFrame {
    IOSurfaceRef frame = [self copyFrame];
    if (!frame) {
        return;
    }

    [self.glView drawFrame:frame];
    // TODO - publish to syphon

    CFRelease(frame);
}

@end
