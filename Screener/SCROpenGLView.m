//
//  SCROpenGLView.m
//  Screener
//
//  Created by Jean-Pierre Mouilleseaux on 15 Jan 2014.
//  Copyright (c) 2014 Chorded Constructions. All rights reserved.
//

#import "SCROpenGLView.h"
@import OpenGL.GL;

@implementation SCROpenGLView

- (void)awakeFromNib {
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersionLegacy,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFAAccelerated,
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
}

- (void)prepareOpenGL {
    [super prepareOpenGL];

    // TODO - initialize anything special

    NSLog(@"GL_VENDOR: %s", glGetString(GL_VENDOR));
    NSLog(@"GL_RENDERER: %s", glGetString(GL_RENDERER));
    NSLog(@"GL_VERSION: %s", glGetString(GL_VERSION));
    NSLog(@"GL_SHADING_LANGUAGE_VERSION: %s", glGetString(GL_SHADING_LANGUAGE_VERSION));

    NSLog(@"GL_EXTENSIONS:");
    NSString* extensionsString = [@((char*)glGetString(GL_EXTENSIONS)) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray* extensions = [extensionsString componentsSeparatedByString:@" "];
    [extensions enumerateObjectsUsingBlock:^(NSString* extension, NSUInteger idx, BOOL *stop) {
        NSLog(@"  %@", extension);
    }];
}

- (void)reshape {
    glViewport(0, 0, [self bounds].size.width, [self bounds].size.height);
    [self drawRect:[self bounds]];
}

- (void)drawRect:(NSRect)dirtyRect {
    // NB - apparently only occurs on -reshape
    [self drawFrame:NULL];
}

#pragma mark -

- (void)drawFrame:(IOSurfaceRef)surface {
    [[self openGLContext] makeCurrentContext];

    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);

    if (surface) {
        // generate texture
        glPushAttrib(GL_TEXTURE_BIT);

        GLuint surfaceTexture;
        glGenTextures(1, &surfaceTexture);
        glEnable(GL_TEXTURE_RECTANGLE_ARB);
        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, surfaceTexture);

        GLsizei width = (GLsizei)IOSurfaceGetWidth(surface);
        GLsizei height = (GLsizei)IOSurfaceGetHeight(surface);

        GLenum internalFormat, format, type;
        OSType pixelFormat = IOSurfaceGetPixelFormat(surface);
        if (pixelFormat == kCVPixelFormatType_32BGRA) {
            internalFormat = GL_RGB;
            format = GL_BGRA;
            type = GL_UNSIGNED_INT_8_8_8_8_REV;
        } else if (pixelFormat == kCVPixelFormatType_32ARGB) {
            internalFormat = GL_RGB;
            format = GL_RGB;
            type = GL_UNSIGNED_INT_8_8_8_8;
        } else {
            NSLog(@"ERROR - unhandled IOSurface pixel format - %d", pixelFormat);
            exit(EXIT_FAILURE);
        }
        CGLError error = CGLTexImageIOSurface2D([[self openGLContext] CGLContextObj], GL_TEXTURE_RECTANGLE_ARB, internalFormat, width, height, format, type, surface, 0);

        glBindTexture(GL_TEXTURE_RECTANGLE_ARB, 0);
        glDisable(GL_TEXTURE_RECTANGLE_ARB);

        glPopAttrib();

        if (error != kCGLNoError) {
            NSLog(@"ERROR - failed to create texture from IOSurfaceRef - %d", error);
        } else {
            // display texture, repurposed from https://code.google.com/p/iosurfacetest/source/browse/trunk/Classes/IOSurfaceTestView.m
            GLfloat textureMatrix[16] = {0.0f};
            GLint saveMatrixMode;

            // reverses and normalizes the texture
            textureMatrix[0] = (GLfloat)width;
            textureMatrix[5] = -(GLfloat)height;
            textureMatrix[10] = 1.0f;
            textureMatrix[13] = (GLfloat)height;
            textureMatrix[15] = 1.0f;

            glGetIntegerv(GL_MATRIX_MODE, &saveMatrixMode);
            glMatrixMode(GL_TEXTURE);
            glPushMatrix();
            glLoadMatrixf(textureMatrix);
            glMatrixMode(saveMatrixMode);

            glEnable(GL_TEXTURE_RECTANGLE_ARB);
            glBindTexture(GL_TEXTURE_RECTANGLE_ARB, surfaceTexture);
            glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);

            // draw textured quad
            glBegin(GL_QUADS);
                glTexCoord2f(0.0f, 0.0f);
                glVertex3f(-1.0f, -1.0f, 0.0f);
                glTexCoord2f(1.0f, 0.0f);
                glVertex3f(1.0f, -1.0f, 0.0f);
                glTexCoord2f(1.0f, 1.0f);
                glVertex3f(1.0f, 1.0f, 0.0f);
                glTexCoord2f(0.0f, 1.0f);
                glVertex3f(-1.0f, 1.0f, 0.0f);
            glEnd();

            // restore texturing settings
            glBindTexture(GL_TEXTURE_RECTANGLE_ARB, 0);
            glDisable(GL_TEXTURE_RECTANGLE_ARB);

            glGetIntegerv(GL_MATRIX_MODE, &saveMatrixMode);
            glMatrixMode(GL_TEXTURE);
            glPopMatrix();
        }

        if (surfaceTexture != 0) {
            glDeleteTextures(1, &surfaceTexture);
        }
    } else {
        glColor3f(1.0f, 0.85f, 0.35f);
        glBegin(GL_TRIANGLES);
            glVertex3f(0.0f, 0.6f, 0.0f);
            glVertex3f(-0.2, -0.3f, 0.0f);
            glVertex3f(0.2f, -0.3f,0.0f);
        glEnd();
    }

    [[self openGLContext] flushBuffer];

    // NB - no idea what this means but I've found that this flush is needed and Apple's sample code had the following comment
    //  This flush is necessary to ensure proper behavior if the MT engine is enabled.
    glFlush();
}

@end
