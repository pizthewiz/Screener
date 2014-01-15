//
//  SCROpenGLView.m
//  Screener
//
//  Created by Jean-Pierre Mouilleseaux on 15 Jan 2014.
//  Copyright (c) 2014 Chorded Constructions. All rights reserved.
//

#import "SCROpenGLView.h"

@implementation SCROpenGLView

- (void)awakeFromNib {
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        NSOpenGLPFADepthSize, 24,
        0
    };
    NSOpenGLPixelFormat* pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    if (!pixelFormat) {
        NSLog(@"ERROR - failed to create pixel format");
        exit(EXIT_FAILURE);
    }
    NSOpenGLContext* context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
    if (!context) {
        NSLog(@"ERROR - failed to create OpenGL context");
        exit(EXIT_FAILURE);
    }

    [self setPixelFormat:pixelFormat];
    [self setOpenGLContext:context];

    // NB - crash on legacy OpenGL function use
    CGLEnable([context CGLContextObj], kCGLCECrashOnRemovedFunctions);
}

- (void) prepareOpenGL {
	[super prepareOpenGL];

    [[self openGLContext] makeCurrentContext];

    GLint swapInt = 1;
	[[self openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
}


- (void)drawView {
    [[self openGLContext] makeCurrentContext];

    // TODO - draw

	CGLFlushDrawable([[self openGLContext] CGLContextObj]);
	CGLUnlockContext([[self openGLContext] CGLContextObj]);
}

@end
