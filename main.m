//
//  main.m
//  pppoe
//
//  Created by Jerry Smith on 1/01/16.
//  Copyright © 2016 Jerry Smith. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "pppoeGUI.h"

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		NSApplication *app = [NSApplication sharedApplication];
		[app setActivationPolicy:NSApplicationActivationPolicyRegular];
		[app setDelegate:[pppoeGUI shared]];
		[app activateIgnoringOtherApps:YES];
		[app run];
	}
	return 0;
}