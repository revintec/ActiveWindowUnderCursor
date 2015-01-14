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

#define AXMessagingTimeout 0.1
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
static inline void _cc(char*op,int error,char*fn,int ln){
    if(!error)return;
    NSLog(@"%s: %d    at %s(line %d)",(char*)op,error,fn,ln);
    AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert);
    sleep(3);
    exit(error);
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
        CFTypeRef isfg;AXError error=AXUIElementCopyAttributeValue(application,kAXFrontmostAttribute,&isfg);
        if(!error){
            if(kCFBooleanTrue!=isfg)
                cc("set front",AXUIElementSetAttributeValue(application,kAXFrontmostAttribute,kCFBooleanTrue));
            else return true;
        }else if(kAXErrorCannotComplete!=error)cc("get front",error);
        [NSThread sleepForTimeInterval:0.1];
    }return false;
}
void filterSheet(AXUIElementRef elem,CFTypeRef*sheet){
    CFTypeRef children;
    // kAXChildrenAttribute shouldn't return kAXErrorNoValue
    cc("filter sheet children",AXUIElementCopyAttributeValue(elem,kAXChildrenAttribute,&children));
    for(CFIndex i=CFArrayGetCount(children)-1;i>=0;--i){
        CFTypeRef child=CFArrayGetValueAtIndex(children,i);
        CFTypeRef role;cc("filter sheet role",AXUIElementCopyAttributeValue(child,kAXRoleAttribute,&role));
        if(CFEqual(kAXSheetRole,role))
            return filterSheet(*sheet=child,sheet);
    }
}
bool strokeCancel(AXUIElementRef elem){
    CFTypeRef children;AXError error=AXUIElementCopyAttributeValue(elem,kAXChildrenAttribute,&children);
    if(!error){
        for(CFIndex i=CFArrayGetCount(children)-1;i>=0;--i){
            CFTypeRef child=CFArrayGetValueAtIndex(children,i);
            CFTypeRef role;cc("filter cancel role",AXUIElementCopyAttributeValue(child,kAXRoleAttribute,&role));
            if(CFEqual(kAXButtonRole,role)){
                CFTypeRef title;AXError error=AXUIElementCopyAttributeValue(child,kAXTitleAttribute,&title);
                if(kAXErrorAttributeUnsupported!=error)cc("filter cancel title",error);
                if(error)continue;
                if(CFEqual(@"Cancel",title)||CFEqual(@"取消",title)){
                    AXUIElementRef system=AXUIElementCreateSystemWide();
                    cc("AXUIElementSetMessagingTimeout",AXUIElementSetMessagingTimeout(system,1));
                    cc("press cancel",AXUIElementPerformAction(child,kAXPressAction));
                    cc("AXUIElementSetMessagingTimeout",AXUIElementSetMessagingTimeout(system,AXMessagingTimeout));
                    return true;
                }// continue
            }else if(strokeCancel(child))return true;
        }
    }else if(kAXErrorNoValue!=error)cc("filter cancel children",error);
    return false;
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
        AXUIElementRef web=nil,window,application;
        AXUIElementRef system=AXUIElementCreateSystemWide();
        cc("AXUIElementSetMessagingTimeout",AXUIElementSetMessagingTimeout(system,AXMessagingTimeout));
        cc("AXUIElementCopyElementAtPosition",AXUIElementCopyElementAtPosition(system,point.x,point.y,&window));
        pid_t pid;cc("AXUIElementGetPid",AXUIElementGetPid(window,&pid));
        NSRunningApplication*ra=[NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        cc("get NSRunningApplication",ra==nil);
        NSString*appName=[ra localizedName];
        bool safari=[@"Safari" isEqual:appName];
        while(true){
            CFTypeRef role,prole;
            cc("loop get role",AXUIElementCopyAttributeValue(window,kAXRoleAttribute,&role));
            cc("loop get parent",AXUIElementCopyAttributeValue(window,kAXParentAttribute,(CFTypeRef*)&application));
            cc("loop get prole",AXUIElementCopyAttributeValue(application,kAXRoleAttribute,&prole));
            if(CFEqual(kAXWindowRole,role)){
                if(CFEqual(kAXApplicationRole,prole))
                    break;
            }else if(CFEqual(kAXRadioButtonRole,role)){
                if(CFEqual(kAXTabGroupRole,prole)){
                    if(safari){
                        // this way we can't get AXWebArea
                        // so we disable this feature for now
                        cc("loop press tab, NYI(Safari)",true);
                    }else cc("loop press tab",AXUIElementPerformAction(window,kAXPressAction));
                }
            }else if(safari&&CFEqual(@"AXWebArea",role)){
                // AXWebArea may contain other AXWebArea
                // so only the outer most AXWebArea is relevant
                // with this information, undo close tab multiple times is possible in Safari
                // (currently Safari only allow undo the most recent close tab)
                // won't need this in Chrome since it has the Recent Tabs feature built-in
                web=window;
            }window=application;
        }
        if(mode==MODE_WIN_ZOOM){
            if([@"MPlayerX" isEqual:appName]){
                ProcessSerialNumber psn;
                cc("get psn",_GetProcessForPID(pid,&psn));
                cc("set main",AXUIElementSetAttributeValue(window,kAXMainAttribute,kCFBooleanTrue));
                // BUG FIX:  some apps can't receive keystrokes and/or mouseclicks while they're not foreground
                // BUG FIX2: [NSScreen mainScreen] consults the window in focus
                cc("applicationToFrontmost",!applicationToFrontmost(application));
                // END BUG FIX
                CFTypeRef ref;CGRect wrect,srect,prect;
                cc("get frame",AXUIElementCopyAttributeValue(window,(CFStringRef)@"AXFrame",&ref));
                cc("get frame as CGRect",!AXValueGetValue(ref,kAXValueCGRectType,&wrect));
                NSScreen*screen=[NSScreen mainScreen];
                prect=[screen frame];
                srect=[screen visibleFrame];
                srect.origin.y=prect.size.height-prect.origin.y-(srect.size.height+srect.origin.y);
                if((wrect.origin.x>=0&&wrect.origin.y>=0&&
                   wrect.origin.x+wrect.size.width<=srect.origin.x+srect.size.width&&
                   wrect.origin.y+wrect.size.height<=srect.origin.y+srect.size.height)&&
                   ((wrect.origin.x==srect.origin.x&&wrect.size.width==srect.size.width)||
                   (wrect.origin.y==srect.origin.y&&wrect.size.height==srect.size.height))){
                    cc("key ⌘1",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand,kVK_ANSI_1));
                }else cc("key ⌘3",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand,kVK_ANSI_3));
            }else{
                cc("get zoom button",AXUIElementCopyAttributeValue(window,kAXZoomButtonAttribute,(CFTypeRef*)&window));
                AXUIElementRef system=AXUIElementCreateSystemWide();
                cc("AXUIElementSetMessagingTimeout",AXUIElementSetMessagingTimeout(system,1));
                AXError error=AXUIElementPerformAction(window,(CFStringRef)@"AXZoomWindow");
                if(error){
                    if(error!=kAXErrorActionUnsupported)
                        cc("AXZoomWindow",error);
                    CFTypeRef srole;cc("get zoom button srole",AXUIElementCopyAttributeValue(window,kAXSubroleAttribute,&srole));
                    cc("test srole",!CFEqual(kAXZoomButtonSubrole,srole));
                    cc("zoom window",AXUIElementPerformAction(window,kAXPressAction));
                }
                cc("AXUIElementSetMessagingTimeout",AXUIElementSetMessagingTimeout(system,AXMessagingTimeout));
            }
        }else{
            Boolean mayhaveTab;
            if([@[@"QREncoder",@"FileZilla",@"ffplay"]containsObject:appName])mayhaveTab=false;
            else cc("can set main",AXUIElementIsAttributeSettable(window,kAXMainAttribute,&mayhaveTab));
            if(mayhaveTab){
                ProcessSerialNumber psn;
                cc("get psn",_GetProcessForPID(pid,&psn));
                cc("set main",AXUIElementSetAttributeValue(window,kAXMainAttribute,kCFBooleanTrue));
                // WORKAROUND: see FIXME in mouseClickWithButton(...)
                // BUG FIX: some apps can't receive keystrokes and/or mouseclicks while they're not foreground
                // There is, however, another approach: instead of sending CMD-W, click the close button
                // of the tab instead, and if there is no tabs left, click the close button of the window
                cc("applicationToFrontmost",!applicationToFrontmost(application));
                // END BUG FIX
                bool xcode=[@"Xcode" isEqual:appName];
                switch(mode){
                    case MODE_TAB_PREV:
                        if(xcode)cc("key ⌘{",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand|kCGEventFlagMaskShift,kVK_ANSI_LeftBracket));
                        else cc("key ^⇧\\t",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskControl|kCGEventFlagMaskShift,kVK_Tab));
                        break;
                    case MODE_TAB_CLSE:
                    {
                        CFTypeRef sheet=nil;filterSheet(window,&sheet);
                        if(!sheet){
                            if(safari){
                                cc("acquire AXWebArea in Safari",web==nil);
                                CFTypeRef title,url;
                                AXError error=AXUIElementCopyAttributeValue(web,kAXURLAttribute,&url);
                                if(!error){
                                    cc("get AXWebArea title",AXUIElementCopyAttributeValue(web,kAXDescriptionAttribute,&title));
                                    NSLog(@"closing tab: %@\n%@",title,url);
                                }else if(kAXErrorNoValue!=error)cc("get AXWebArea url",error);
                            }cc("key ⌘W",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand,kVK_ANSI_W));
                        }else if(!strokeCancel(sheet))
                            cc("key ⌘.",!strokeKeycodeWithModifier(&psn,kCGEventFlagMaskCommand,kVK_ANSI_Period));
                        break;
                    }
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
                AXError error;CFTypeRef button;
                if((error=AXUIElementCopyAttributeValue(window,kAXCancelButtonAttribute,&button))){
                    if(kAXErrorNoValue!=error)cc("get cancel button",error);
                    cc("get close button",AXUIElementCopyAttributeValue(window,kAXCloseButtonAttribute,&button));
                }cc("close window",AXUIElementPerformAction(button,kAXPressAction));
            }
        }
    }//return 0;
}
