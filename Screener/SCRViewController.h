//
//  SCRViewController.h
//  Screener
//
//  Created by Jean-Pierre Mouilleseaux on 14 Jan 2014.
//  Copyright (c) 2014 Chorded Constructions. All rights reserved.
//

@import Cocoa;

@interface SCRViewController : NSViewController
@property (nonatomic, weak) IBOutlet NSOpenGLView* glView;
@property (nonatomic, weak) IBOutlet NSPopUpButton* displayPopUpButton;
@end
