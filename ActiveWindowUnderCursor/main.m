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

static inline OSStatus _GetProcessForPID(pid_t pid,ProcessSerialNumber*psn){
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return GetProcessForPID(pid,psn);
#pragma clang diagnostic pop
}
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
static inline void _cc(char*op,long error,char*fn,int ln){
    if(!error)return;
    NSLog(@"%s: %ld    at %s(line %d)",(char*)op,error,fn,ln);
    AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert);
    sleep(3);
    exit(1);
}
#define cc(op,error) _cc(op,error,(char*)__PRETTY_FUNCTION__,__LINE__)
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
static inline bool applicationToFrontmost(AXUIElementRef application){
    for(int i=0;i<10;++i){// delay at most 10 times to prevent dead loop
        CFTypeRef isfg;cc("get front",AXUIElementCopyAttributeValue(application,kAXFrontmostAttribute,&isfg));
        if(kCFBooleanTrue!=isfg)
            cc("set front",AXUIElementSetAttributeValue(application,kAXFrontmostAttribute,kCFBooleanTrue));
        else return true;
        [NSThread sleepForTimeInterval:0.1];
    }return false;
}
#define MODE_TAB_PREV 1
#define MODE_TAB_NEXT 2
#define MODE_TAB_CLSE 3
#define MODE_TAB_MIDD 4
#define MODE_WIN_ZOOM 5
int main(int argc,const char*argv[]){
    @autoreleasepool{
        cc("accessibility perm",!AXIsProcessTrusted());
        cc("command args",argc!=2);
        int mode=argv[1][0];
        printf("argc: %d\n",argc);
        switch(mode){
            case '<':mode=MODE_TAB_PREV;break;
            case 'x':mode=MODE_TAB_CLSE;break;
            case '_':cc("unsupported mode",mode);mode=MODE_TAB_MIDD;break; // CenterMouse click just not working...
            case '>':mode=MODE_TAB_NEXT;break;
            case '+':mode=MODE_WIN_ZOOM;break;
            case  0:cc("ascii \\0",true);
            default:cc("unknown mode",mode);
        }
        NSPoint point=[NSEvent mouseLocation];
        cc("coordinate conversion",!carbonScreenPointFromCocoaScreenPoint(&point));
        AXUIElementRef sheet=nil,window,application;
        cc("AXUIElementCopyElementAtPosition",AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),point.x,point.y,&window));
        while(true){
            CFTypeRef role,prole;
            cc("loop get role",AXUIElementCopyAttributeValue(window,kAXRoleAttribute,&role));
            cc("loop get parent",AXUIElementCopyAttributeValue(window,kAXParentAttribute,(CFTypeRef*)&application));
            cc("loop get prole",AXUIElementCopyAttributeValue(application,kAXRoleAttribute,&prole));
            if([(NSString*)kAXWindowRole isEqual:(__bridge id)(role)]){
                if([(NSString*)kAXApplicationRole isEqual:(__bridge id)(prole)])
                    break;
            }else if([(NSString*)kAXRadioButtonRole isEqual:(__bridge id)(role)]){
                if([(NSString*)kAXTabGroupRole isEqual:(__bridge id)(prole)])
                    cc("loop press tab",AXUIElementPerformAction(window,kAXPressAction));
            }else if([(NSString*)kAXSheetRole isEqual:(__bridge id)(role)]){
                if([(NSString*)kAXWindowRole isEqual:(__bridge id)(prole)])
                    sheet=window;
            }window=application;
        }
        CFTypeRef t;cc("get title",AXUIElementCopyAttributeValue(application,kAXTitleAttribute,&t));
        NSString*title=(__bridge NSString*)(t);
        if(mode==MODE_WIN_ZOOM){
            if([@"MPlayerX" isEqual:title]){
                pid_t pid;ProcessSerialNumber psn;
                cc("get pid",AXUIElementGetPid(application,&pid));
                cc("get psn",_GetProcessForPID(pid,&psn));
                cc("set main",AXUIElementSetAttributeValue(window,kAXMainAttribute,kCFBooleanTrue));
                // BUG FIX:  some apps can't receive keystrokes and/or mouseclicks while they're not foreground
                // BUG FIX2: [NSScreen mainScreen] consults the window in focus
                applicationToFrontmost(application);
                // END BUG FIX
                CFTypeRef ref;CGRect wrect,srect,prect;
                cc("get frame",AXUIElementCopyAttributeValue(window,(CFStringRef)@"AXFrame",&ref));
                cc("get frame as CGRect",!AXValueGetValue(ref,kAXValueCGRectType,&wrect));
                NSScreen*screen=[NSScreen mainScreen];
                prect=[screen frame];
                srect=[screen visibleFrame];
                srect.origin.y=prect.size.height-prect.origin.y-(srect.size.height+srect.origin.y);
                if((wrect.origin.x==srect.origin.x&&wrect.size.width==srect.size.width)||
                   (wrect.origin.y==srect.origin.y&&wrect.size.height==srect.size.height)){
                    cc("key ⌘1",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand,kVK_ANSI_1));
                }else cc("key ⌘3",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand,kVK_ANSI_3));
            }else{
                cc("get zoom button",AXUIElementCopyAttributeValue(window,kAXZoomButtonAttribute,(CFTypeRef*)&window));
                AXError error=AXUIElementPerformAction(window,(CFStringRef)@"AXZoomWindow");
                if(error){
                    if(error!=kAXErrorActionUnsupported)
                        cc("AXZoomWindow",error);
                    CFTypeRef srole;cc("get zoom button srole",AXUIElementCopyAttributeValue(window,kAXSubroleAttribute,&srole));
                    cc("test srole",![(NSString*)kAXZoomButtonSubrole isEqual:(__bridge id)(srole)]);
                    cc("zoom window",AXUIElementPerformAction(window,kAXPressAction));
                }
            }
        }else{
            Boolean attw;
            if(!sheet){
                NSArray*items=@[@"QREncoder",@"FileZilla"];
                if([items containsObject:title])attw=false;
                else cc("can set main",AXUIElementIsAttributeSettable(window,kAXMainAttribute,&attw));
            }else attw=true;
            if(attw){
                pid_t pid;ProcessSerialNumber psn;
                cc("get pid",AXUIElementGetPid(application,&pid));
                cc("get psn",_GetProcessForPID(pid,&psn));
                cc("set main",AXUIElementSetAttributeValue(window,kAXMainAttribute,kCFBooleanTrue));
                // WORKAROUND: see FIXME in mouseClickWithButton(...)
                // BUG FIX: some apps can't receive keystrokes and/or mouseclicks while they're not foreground
                // There is, however, another approach: instead of sending CMD-W, click the close button
                // of the tab instead, and if there is no tabs left, click the close button of the window
                applicationToFrontmost(application);
                // END BUG FIX
                bool xcode=[@"Xcode" isEqual:title];
                switch(mode){
                    case MODE_TAB_PREV:
                        if(xcode)cc("key ⌘{",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand|kCGEventFlagMaskShift,kVK_ANSI_LeftBracket));
                        else cc("key ^⇧\\t",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskControl|kCGEventFlagMaskShift,kVK_Tab));
                        break;
                    case MODE_TAB_CLSE:
                        if(sheet)cc("key ⌘.",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand,kVK_ANSI_Period));
                        else cc("key ⌘W",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand,kVK_ANSI_W));
                        break;
                    case MODE_TAB_MIDD:
                        // cc !mouseClickWithButton(&psn,&point,kCGMouseButtonCenter);
                        break;
                    case MODE_TAB_NEXT:
                        if(xcode)cc("key ⌘}",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand|kCGEventFlagMaskShift,kVK_ANSI_RightBracket));
                        else cc("key ^\\t",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskControl,kVK_Tab));
                        break;
                    case  0:cc("mode \\0",true);
                    default:cc("unknown mode",mode);
                }
            }else if(mode==MODE_TAB_CLSE){
                cc("get close button",AXUIElementCopyAttributeValue(window,kAXCloseButtonAttribute,(CFTypeRef*)&window));
                cc("close window",AXUIElementPerformAction(window,kAXPressAction));
            }
        }
    }//return 0;
}
