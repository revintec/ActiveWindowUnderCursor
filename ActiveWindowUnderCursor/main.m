//
//  main.m
//  ActiveWindowUnderCursor
//
//  Created by revin on Dec.1,2014.
//  Copyright (c) 2014 revin. All rights reserved.
//

#import <AppKit/AppKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Carbon/Carbon.h>

BOOL carbonScreenPointFromCocoaScreenPoint(NSPoint*cocoaPoint){
    NSScreen*foundScreen=nil;
    for(NSScreen*screen in [NSScreen screens]){
        if(NSPointInRect(*cocoaPoint,[screen frame])){
            foundScreen=screen;
            break;
        }
    }if(!foundScreen)return false;
    CGFloat screenHeight=[foundScreen frame].size.height;
    cocoaPoint->y=screenHeight-cocoaPoint->y-1;
    return true;
}
static inline void cc(error){
    if(!error)return;
    AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert);
    sleep(3);
    exit(1);
}
BOOL strokeKeycodeWithCMD(ProcessSerialNumber*psn,CGKeyCode key){
    CGEventRef kd=CGEventCreateKeyboardEvent(nil,key,true);
    CGEventRef ku=CGEventCreateKeyboardEvent(nil,key,false);
    if(!kd||!ku){
        if(kd)CFRelease(kd);
        if(ku)CFRelease(ku);
        return false;
    }
    CGEventSetFlags(kd,kCGEventFlagMaskCommand);
    CGEventSetFlags(ku,kCGEventFlagMaskCommand);
    CGEventPostToPSN(psn,kd);
    CGEventPostToPSN(psn,ku);
    CFRelease(kd);CFRelease(ku);
    return true;
}
int main(int argc,const char*argv[]){
    @autoreleasepool{
        cc(!AXIsProcessTrusted());
        NSPoint point=[NSEvent mouseLocation];
        cc(!carbonScreenPointFromCocoaScreenPoint(&point));
        AXUIElementRef window,application;
        cc(AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),point.x,point.y,&window));
        while(true){
            CFTypeRef role,prole;
            cc(AXUIElementCopyAttributeValue(window,kAXRoleAttribute,&role));
            cc(AXUIElementCopyAttributeValue(window,kAXParentAttribute,(CFTypeRef*)&application));
            cc(AXUIElementCopyAttributeValue(application,kAXRoleAttribute,&prole));
            if([(NSString*)kAXWindowRole isEqual:(__bridge id)(role)]){
                if([(NSString*)kAXApplicationRole isEqual:(__bridge id)(prole)])
                    break;
            }else if([(NSString*)kAXRadioButtonRole isEqual:(__bridge id)(role)]){
                if([(NSString*)kAXTabGroupRole isEqual:(__bridge id)(prole)])
                    cc(AXUIElementPerformAction(window,kAXPressAction));
            }window=application;
        }
        pid_t pid;ProcessSerialNumber psn;
        cc(AXUIElementGetPid(application,&pid));
        cc(GetProcessForPID(pid,&psn));
        cc(AXUIElementSetAttributeValue(window,kAXMainAttribute,kCFBooleanTrue));
        
        // BUG FIX: some apps can't receive keystrokes while they're not foreground
        // There is, however, another approach: instead of sending CMD-W, click the close button
        // of the tab instead, and if there is no tabs left, click the close button of the window
        for(int i=0;i<10;++i){// delay at most 10 times to prevent dead loop
            CFTypeRef isfg;cc(AXUIElementCopyAttributeValue(application,kAXFrontmostAttribute,&isfg));
            if(kCFBooleanTrue!=isfg)
                cc(AXUIElementSetAttributeValue(application,kAXFrontmostAttribute,kCFBooleanTrue));
            else break;
            [NSThread sleepForTimeInterval:0.1];
        }
        
        strokeKeycodeWithCMD(&psn,kVK_ANSI_W);
        return 0;
    }
}
