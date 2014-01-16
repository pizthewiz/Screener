//
//  SCRViewController.h
//  Screener
//
//  Created by Jean-Pierre Mouilleseaux on 14 Jan 2014.
//  Copyright (c) 2014 Chorded Constructions. All rights reserved.
//

@import Cocoa;
#import "SCROpenGLView.h"

@interface SCRViewController : NSViewController
@property (nonatomic, weak) IBOutlet SCROpenGLView* glView;
@property (nonatomic, weak) IBOutlet NSArrayController* displayArrayController;
@property (nonatomic, weak) IBOutlet NSPopUpButton* displayPopUpButton;
- (IBAction)displayPopUpButtonDidChange:(id)sender;
@end
