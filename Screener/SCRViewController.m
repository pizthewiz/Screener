//
//  SCRViewController.m
//  Screener
//
//  Created by Jean-Pierre Mouilleseaux on 14 Jan 2014.
//  Copyright (c) 2014-2015 Chorded Constructions. All rights reserved.
//

#import "SCRViewController.h"
@import Quartz;
#import <Syphon/Syphon.h>

static CGDirectDisplayID const kSCRDisplayIDNone = 0;
static void* SelectionIndexContext = &SelectionIndexContext;

@interface SCRViewController ()
@property (nonatomic) dispatch_queue_t displayQueue;
@property (nonatomic) CGDirectDisplayID display;
@property (nonatomic) CGDisplayStreamRef displayStream;
@property (nonatomic) IOSurfaceRef updatedSurface;
@property (nonatomic, strong) SyphonServer* server;
@property (nonatomic, strong) id activity;
@end

@implementation SCRViewController

- (void)awakeFromNib {
    [self.labelTextField setStringValue:[NSString stringWithFormat:@"%@:", NSLocalizedString(@"Display", nil)]];

    self.displayQueue = dispatch_queue_create("com.chordedconstructions.ScreenerCaptureQueue", DISPATCH_QUEUE_SERIAL);
    if (!self.displayQueue) {
        NSLog(@"ERROR - failed to create display queue");
        exit(EXIT_FAILURE);
    }

    [self setupDisplayList];
    CGDisplayRegisterReconfigurationCallback(DisplayReconfigurationCallback, (__bridge void*)(self));

    self.display = UINT32_MAX;
    [self.displayArrayController addObserver:self forKeyPath:@"selectionIndex" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionInitial context:SelectionIndexContext];
}

- (void)dealloc {
    [self.displayArrayController removeObserver:self forKeyPath:@"selectionIndex" context:SelectionIndexContext];

    // reuse cleanup from -selectDisplay:
    [self selectDisplay:kSCRDisplayIDNone];

    [self.server stop];
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
    [displayList addObject:@{@"name": [NSString stringWithFormat:@"- %@ -", NSLocalizedString(@"NONE", @"Display name for null selection")], @"id": @(kSCRDisplayIDNone)}];

    for (NSUInteger idx = 0; idx < displayCount; idx++) {
        CGDirectDisplayID display = displays[idx];

        // NB - IODisplayCreateInfoDictionary has been un-deprecated 👏
        NSDictionary* deviceInfo = (__bridge_transfer NSDictionary*)IODisplayCreateInfoDictionary(CGDisplayIOServicePort(display), kIODisplayOnlyPreferredName);
        NSDictionary* localizedNames = deviceInfo[@kDisplayProductName];
        NSString* screenName = ([localizedNames count] > 0) ? localizedNames[[localizedNames allKeys].firstObject] : NSLocalizedString(@"Unknown", @"Display name for unknown device");
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

    if ([self.glView openGLContext]) {
        NSString* name = display != kSCRDisplayIDNone ? displayDescriptor[@"name"] : NSLocalizedString(@"NONE", @"Display name for null selection");
        if (!self.server) {
            self.server = [[SyphonServer alloc] initWithName:name context:[[self.glView openGLContext] CGLContextObj] options:nil];
        } else {
            self.server.name = name;
        }
    }

    [self selectDisplay:display];
    [self startDisplayStream];
}

#pragma mark -

- (void)selectDisplay:(CGDirectDisplayID)display {
    [self stopDisplayStream];

    if (self.displayStream) {
        CFRelease(self.displayStream);
        self.displayStream = NULL;
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
    self.displayStream = CGDisplayStreamCreateWithDispatchQueue(self.display, pixelWidth, pixelHeight, 'BGRA', (__bridge CFDictionaryRef)properties, self.displayQueue, ^(CGDisplayStreamFrameStatus status, uint64_t displayTime, IOSurfaceRef frameSurface, CGDisplayStreamUpdateRef updateRef) {
        if (status == kCGDisplayStreamFrameStatusFrameComplete && frameSurface) {
            [self emitFrame:frameSurface];
            [self publishFrame];
        }
    });
}

#pragma mark -

- (void)startDisplayStream {
    if (!self.displayStream) {
        return;
    }

    // start stream
    CGError error = CGDisplayStreamStart(self.displayStream);
    if (error != kCGErrorSuccess) {
        NSLog(@"ERROR - failed to start display stream with error %d", error);
        exit(EXIT_FAILURE);
    }

    // start activity
    if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)]) {
        self.activity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated reason:@"Display capture in-progress"];
    }
}

- (void)stopDisplayStream {
    if (!self.displayStream) {
        return;
    }

    // stop stream
    CGError error = CGDisplayStreamStop(self.displayStream);
    if (error != kCGErrorSuccess) {
        NSLog(@"ERROR - failed to stop display stream with error %d", error);
        exit(EXIT_FAILURE);
    }

    // stop activity
    if (self.activity) {
        [[NSProcessInfo processInfo] endActivity:self.activity];
        self.activity = nil;
    }
}

#pragma mark -

- (IOSurfaceRef)getAndSetFrame:(IOSurfaceRef)surface {
    BOOL status = NO;
    IOSurfaceRef oldSurface;
    do {
        oldSurface = self.updatedSurface;
        status = OSAtomicCompareAndSwapPtrBarrier(oldSurface, surface, (void * volatile *)&_updatedSurface);
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

    GLuint surfaceTexture = [self.glView createTextureForSurface:frame];
    [self.glView drawScene];
    if (surfaceTexture != 0) {
        [self.server publishFrameTexture:surfaceTexture textureTarget:GL_TEXTURE_RECTANGLE_EXT imageRegion:NSMakeRect(0.0f, 0.0f, self.glView.surfaceSize.width, self.glView.surfaceSize.height) textureDimensions:self.glView.surfaceSize flipped:YES];
    }
    [self.glView releaseTexture];

    CFRelease(frame);
}

@end
