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
    cocoaPoint->y=screenHeight-cocoaPoint->y;
    return true;
}
static inline void cc(error){
    if(!error)return;
    AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert);
    sleep(3);
    exit(1);
}
BOOL strokeKeycodeWithModifier(ProcessSerialNumber*psn,CGEventFlags modifiers,CGKeyCode key){
    CGEventRef kd=CGEventCreateKeyboardEvent(nil,key,true);
    CGEventRef ku=CGEventCreateKeyboardEvent(nil,key,false);
    if(!kd||!ku){
        if(kd)CFRelease(kd);
        if(ku)CFRelease(ku);
        return false;
    }
    CGEventSetFlags(kd,modifiers);
    CGEventSetFlags(ku,modifiers);
    CGEventPostToPSN(psn,kd);
    CGEventPostToPSN(psn,ku);
    CFRelease(kd);CFRelease(ku);
    return true;
}
//void smallAlert(){
//    NSSound*snd=[NSSound soundNamed:@"Blow"];[snd play];
//    [NSThread sleepForTimeInterval:[snd duration]];
//}
/** FIXME: CGEventPostToPSN not working, so the target window must be foreground */
//BOOL mouseClickWithButton(ProcessSerialNumber*psn,CGPoint*point,CGMouseButton button){
//    CGEventRef kd=CGEventCreateMouseEvent(nil,kCGEventOtherMouseDown,*point,button);
//    CGEventRef ku=CGEventCreateMouseEvent(nil,kCGEventOtherMouseUp,*point,button);
//    if(!kd||!ku){
//        if(kd)CFRelease(kd);
//        if(ku)CFRelease(ku);
//        return false;
//    }
//    // CGEventCreateMouseEvent(src=CGEventSourceCreate(...),...);             not helping
//    // CGEventRef kx=CGEventCreateMouseEvent(src,kCGEventMouseMove,*point,0); not helping
////    CGEventPostToPSN(psn,kx);
////    CGEventPostToPSN(psn,kd);
////    CGEventPostToPSN(psn,ku);
//    CGEventTapLocation loc=kCGSessionEventTap;
//    CGEventPost(loc,kd);
//    CGEventPost(loc,ku);
//    CFRelease(kd);CFRelease(ku);
//    return true;
//}
int main(int argc,const char*argv[]){
#define MODE_TAB_PREV 1
#define MODE_TAB_NEXT 2
#define MODE_TAB_CLSE 3
#define MODE_TAB_MIDD 4
    @autoreleasepool{
        cc(argc!=2||!AXIsProcessTrusted());
        int mode;
        printf("argc: %d\n",argc);
        switch(argv[1][0]){
            case '<':mode=MODE_TAB_PREV;break;
            case 'x':mode=MODE_TAB_CLSE;break;
            case '_':cc(true);mode=MODE_TAB_MIDD;break; // CenterMouse click just not working...
            case '>':mode=MODE_TAB_NEXT;break;
            default:cc(true);mode=0;// mode=0 is used to prevent "uninitialized variable mode" warnings
        }
        NSPoint point=[NSEvent mouseLocation];
        cc(!carbonScreenPointFromCocoaScreenPoint(&point));
        AXUIElementRef sheet=nil,window,application;
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
            }else if([(NSString*)kAXSheetRole isEqual:(__bridge id)(role)]){
                if([(NSString*)kAXWindowRole isEqual:(__bridge id)(prole)])
                    sheet=window;
            }window=application;
        }
        Boolean attw;
        if(!sheet){
            CFTypeRef title;cc(AXUIElementCopyAttributeValue(application,kAXTitleAttribute,&title));
            NSArray*items=@[@"QREncoder",@"FileZilla"];
            if([items containsObject:(__bridge id)(title)])attw=false;
            else cc(AXUIElementIsAttributeSettable(window,kAXMainAttribute,&attw));
        }else attw=true;
        if(attw){
            pid_t pid;ProcessSerialNumber psn;
            cc(AXUIElementGetPid(application,&pid));
            cc(GetProcessForPID(pid,&psn));
            cc(AXUIElementSetAttributeValue(window,kAXMainAttribute,kCFBooleanTrue));
            // WORKAROUND: see FIXME in mouseClickWithButton(...)
            // BUG FIX: some apps can't receive keystrokes and/or mouseclicks while they're not foreground
            // There is, however, another approach: instead of sending CMD-W, click the close button
            // of the tab instead, and if there is no tabs left, click the close button of the window
            for(int i=0;i<10;++i){// delay at most 10 times to prevent dead loop
                CFTypeRef isfg;cc(AXUIElementCopyAttributeValue(application,kAXFrontmostAttribute,&isfg));
                if(kCFBooleanTrue!=isfg)
                    cc(AXUIElementSetAttributeValue(application,kAXFrontmostAttribute,kCFBooleanTrue));
                else break;
                [NSThread sleepForTimeInterval:0.1];
            }// END BUG FIX
            switch(mode){
                case MODE_TAB_PREV:
                    strokeKeycodeWithModifier(&psn,kCGEventFlagMaskControl|kCGEventFlagMaskShift,kVK_Tab);
                    break;
                case MODE_TAB_CLSE:
                    strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand,sheet?kVK_ANSI_Period:kVK_ANSI_W);
                    break;
                case MODE_TAB_MIDD:
                    mouseClickWithButton(&psn,&point,kCGMouseButtonCenter);
                    break;
                case MODE_TAB_NEXT:
                    strokeKeycodeWithModifier(&psn,kCGEventFlagMaskControl,kVK_Tab);
                    break;
                default:cc(mode);
            }
        }else if(mode==MODE_TAB_CLSE){
            cc(AXUIElementCopyAttributeValue(window,kAXCloseButtonAttribute,(CFTypeRef*)&window));
            cc(AXUIElementPerformAction(window,kAXPressAction));
        }
    }//return 0;
}
