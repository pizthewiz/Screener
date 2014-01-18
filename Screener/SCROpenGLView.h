//
//  SCROpenGLView.h
//  Screener
//
//  Created by Jean-Pierre Mouilleseaux on 15 Jan 2014.
//  Copyright (c) 2014 Chorded Constructions. All rights reserved.
//

@import Cocoa;

@interface SCROpenGLView : NSOpenGLView
@property (nonatomic, readonly) GLuint surfaceTexture;
@property (nonatomic) CGSize surfaceSize;
- (GLuint)createTextureForSurface:(IOSurfaceRef)surface;
- (void)releaseTexture;
- (void)drawScene;
@end
