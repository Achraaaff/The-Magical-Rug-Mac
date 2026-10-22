#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>
#import <Carbon/Carbon.h>
#import <ServiceManagement/ServiceManagement.h>
#import <QuartzCore/QuartzCore.h>
#include <memory>
#include <simd/simd.h>
#include <mutex>
#include "RugModel.hpp"

static NSString *const BundleIdentifier=@"com.achraaaff.TheMagicalRug";
static NSString *const StateKey=@"RugStateV1";
struct GPUVertex { simd_float4 position,normal;simd_float2 uv,padding; };
struct Uniforms { simd_float4 viewport; };
@class RugController;
@interface RugPanel : NSPanel @end
@implementation RugPanel
- (BOOL)canBecomeKey { return NO; }
- (BOOL)canBecomeMain { return NO; }
@end
@interface RugView : MTKView
@property(nonatomic,weak) RugController *controller;
@end
@interface RugController : NSObject<MTKViewDelegate> {
    std::unique_ptr<RugModel> _model;
    std::recursive_mutex _mutex;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    id<MTLDepthStencilState> _depth,_shadowDepth;
    id<MTLTexture> _texture;
    NSArray<id<MTLBuffer>> *_vertices;
    id<MTLBuffer> _indices;
    NSUInteger _vertexCount,_indexCount,_frame;
    dispatch_semaphore_t _inFlight;
    CFTimeInterval _lastFrame;
    NSTimer *_hoverTimer;
    EventHotKeyRef _hotKey;
    EventHandlerRef _hotKeyHandler;
    BOOL _hotKeyDown;
    NSNumber *_displayID;
}
@property(nonatomic,strong) RugPanel *window;
@property(nonatomic,strong) RugView *view;
@property(nonatomic,strong) NSMenu *menu;
@property(nonatomic,strong) NSMenuItem *lockItem;
@property(nonatomic,strong) NSMenuItem *loginItem;
- (instancetype)initWithError:(NSError **)error;
- (void)mouseDown:(NSEvent *)event;
- (void)mouseDragged:(NSEvent *)event;
- (void)mouseUp:(NSEvent *)event;
- (void)scroll:(NSEvent *)event;
- (void)contextMenu:(NSEvent *)event;
- (void)toggleLock:(id)sender;
- (void)fold:(id)sender;
- (void)flatten:(id)sender;
- (void)center:(id)sender;
- (void)larger:(id)sender;
- (void)smaller:(id)sender;
- (void)moveToDisplay:(id)sender;
- (void)save;
- (void)toggleLogin:(id)sender;
- (void)updateMenu;
- (void)showWelcome;
- (void)hotKeyEvent:(UInt32)kind;
@end
@implementation RugView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event;return YES; }
- (void)mouseDown:(NSEvent *)event { [self.controller mouseDown:event]; }
- (void)mouseDragged:(NSEvent *)event { [self.controller mouseDragged:event]; }
- (void)mouseUp:(NSEvent *)event { [self.controller mouseUp:event]; }
- (void)scrollWheel:(NSEvent *)event { [self.controller scroll:event]; }
- (void)rightMouseDown:(NSEvent *)event { [self.controller contextMenu:event]; }
@end
static OSStatus HotKeyHandler(EventHandlerCallRef next,EventRef event,void *context) {
    (void)next;EventHotKeyID identifier={};
    if(GetEventParameter(event,kEventParamDirectObject,typeEventHotKeyID,nullptr,sizeof(identifier),nullptr,&identifier)!=noErr)return eventNotHandledErr;
    if(identifier.signature!=0x4D527567||identifier.id!=1)return eventNotHandledErr;
    [(__bridge RugController *)context hotKeyEvent:GetEventKind(event)];return noErr;
}
static NSError *AppError(NSString *description) {
    return [NSError errorWithDomain:BundleIdentifier code:1 userInfo:@{NSLocalizedDescriptionKey:description}];
}
@implementation RugController
- (instancetype)initWithError:(NSError **)error {
    self=[super init];if(!self)return nil;
    NSScreen *screen=NSScreen.screens.firstObject;
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    if(!screen||!device){if(error)*error=AppError(@"A display and a Metal-compatible graphics device are required.");return nil;}
    NSRect frame=screen.frame;_displayID=screen.deviceDescription[@"NSScreenNumber"];
    _model=std::make_unique<RugModel>(frame.size.width,frame.size.height);
    _queue=[device newCommandQueue];_inFlight=dispatch_semaphore_create(3);
    _window=[[RugPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    _window.level=CGWindowLevelForKey(kCGDesktopIconWindowLevelKey)+1;
    _window.opaque=NO;_window.backgroundColor=NSColor.clearColor;_window.hasShadow=NO;
    _window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorStationary|NSWindowCollectionBehaviorIgnoresCycle|NSWindowCollectionBehaviorFullScreenNone;
    _window.ignoresMouseEvents=YES;_window.hidesOnDeactivate=NO;_window.releasedWhenClosed=NO;
    _view=[[RugView alloc] initWithFrame:NSMakeRect(0,0,frame.size.width,frame.size.height) device:device];
    _view.colorPixelFormat=MTLPixelFormatBGRA8Unorm_sRGB;_view.depthStencilPixelFormat=MTLPixelFormatDepth32Float;
    _view.sampleCount=[device supportsTextureSampleCount:4]?4:1;
    _view.clearColor=MTLClearColorMake(0,0,0,0);_view.preferredFramesPerSecond=60;
    _view.paused=YES;_view.enableSetNeedsDisplay=YES;_view.wantsLayer=YES;_view.layer.opaque=NO;
    _view.controller=self;_view.delegate=self;_window.contentView=_view;
    NSURL *resource=NSBundle.mainBundle.resourceURL;
    id<MTLLibrary> shaders=[device newLibraryWithURL:[resource URLByAppendingPathComponent:@"Rug.metallib"] error:error];
    if(!shaders)return nil;
    MTLRenderPipelineDescriptor *descriptor=[MTLRenderPipelineDescriptor new];
    descriptor.vertexFunction=[shaders newFunctionWithName:@"rugVertex"];descriptor.fragmentFunction=[shaders newFunctionWithName:@"rugFragment"];
    descriptor.colorAttachments[0].pixelFormat=_view.colorPixelFormat;descriptor.depthAttachmentPixelFormat=_view.depthStencilPixelFormat;
    descriptor.rasterSampleCount=_view.sampleCount;
    descriptor.colorAttachments[0].blendingEnabled=YES;
    descriptor.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor=MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
    _pipeline=[device newRenderPipelineStateWithDescriptor:descriptor error:error];if(!_pipeline)return nil;
    MTLDepthStencilDescriptor *depth=[MTLDepthStencilDescriptor new];depth.depthCompareFunction=MTLCompareFunctionLess;depth.depthWriteEnabled=YES;
    _depth=[device newDepthStencilStateWithDescriptor:depth];depth.depthWriteEnabled=NO;_shadowDepth=[device newDepthStencilStateWithDescriptor:depth];
    MTKTextureLoader *loader=[[MTKTextureLoader alloc] initWithDevice:device];
    _texture=[loader newTextureWithContentsOfURL:[resource URLByAppendingPathComponent:@"persian.jpg"] options:@{MTKTextureLoaderOptionSRGB:@YES,MTKTextureLoaderOptionOrigin:MTKTextureLoaderOriginTopLeft} error:error];
    if(!_texture)return nil;
    _model=std::make_unique<RugModel>(frame.size.width,frame.size.height,float(_texture.height)/float(_texture.width));
    [self restore];[self ensureBuffers];
    [_window setFrame:frame display:YES];[_window orderFrontRegardless];[self refresh];
    __weak RugController *weakSelf=self;
    _hoverTimer=[NSTimer timerWithTimeInterval:1./30 repeats:YES block:^(NSTimer *timer){(void)timer;[weakSelf pollHover];}];
    [NSRunLoop.mainRunLoop addTimer:_hoverTimer forMode:NSRunLoopCommonModes];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(displaysChanged:) name:NSApplicationDidChangeScreenParametersNotification object:nil];
    EventTypeSpec events[]={{kEventClassKeyboard,kEventHotKeyPressed},{kEventClassKeyboard,kEventHotKeyReleased}};
    OSStatus status=InstallApplicationEventHandler(&HotKeyHandler,2,events,(__bridge void *)self,&_hotKeyHandler);
    EventHotKeyID identifier={0x4D527567,1};
    if(status==noErr)status=RegisterEventHotKey(kVK_ANSI_R,controlKey|optionKey,identifier,GetApplicationEventTarget(),0,&_hotKey);
    if(status!=noErr){NSLog(@"Global shortcut registration failed: %d",int(status));}
    return self;
}
- (void)dealloc {
    [_hoverTimer invalidate];[NSNotificationCenter.defaultCenter removeObserver:self];
    if(_hotKey)UnregisterEventHotKey(_hotKey);if(_hotKeyHandler)RemoveEventHandler(_hotKeyHandler);
}
- (void)ensureBuffers {
    auto &cloth=_model->cloth;NSUInteger count=cloth.count(),indices=cloth.faces.size()*3;
    if(_vertexCount==count&&_indexCount==indices)return;
    NSMutableArray<id<MTLBuffer>> *buffers=[NSMutableArray new];
    for(int i=0;i<3;i++)[buffers addObject:[_view.device newBufferWithLength:count*sizeof(GPUVertex) options:MTLResourceStorageModeShared]];
    _vertices=buffers;std::vector<uint32_t> values;values.reserve(indices);
    for(auto face:cloth.faces)for(int index:face)values.push_back(uint32_t(index));
    _indices=[_view.device newBufferWithBytes:values.data() length:values.size()*sizeof(uint32_t) options:MTLResourceStorageModeShared];
    _vertexCount=count;_indexCount=indices;
}
- (void)refresh {
    _view.paused=_model->sleeping||_model->locked;
    _view.enableSetNeedsDisplay=_view.paused;
    if(_view.paused)[_view setNeedsDisplay:YES];
}
- (void)drawInMTKView:(MTKView *)view {
    @autoreleasepool {
        std::lock_guard<std::recursive_mutex> guard(_mutex);
        if(dispatch_semaphore_wait(_inFlight,DISPATCH_TIME_NOW)!=0)return;
        MTLRenderPassDescriptor *pass=view.currentRenderPassDescriptor;id<CAMetalDrawable> drawable=view.currentDrawable;
        if(!pass||!drawable){dispatch_semaphore_signal(_inFlight);return;}
        CFTimeInterval now=CACurrentMediaTime();float dt=_lastFrame>0?float(now-_lastFrame):1.f/60;_lastFrame=now;
        bool wasSleeping=_model->sleeping;_model->step(dt);[self ensureBuffers];
        id<MTLBuffer> buffer=_vertices[_frame++%3];auto *data=static_cast<GPUVertex *>(buffer.contents);
        auto &cloth=_model->cloth;
        for(int i=0;i<cloth.count();i++){
            auto p=cloth.pos[i],n=cloth.norm[i];
            data[i].position={p.x,p.y,p.z,1};data[i].normal={n.x,n.y,n.z,0};
            data[i].uv={float(i%cloth.nx)/(cloth.nx-1),float(i/cloth.nx)/(cloth.ny-1)};data[i].padding={0,0};
        }
        id<MTLCommandBuffer> command=[_queue commandBuffer];
        if(!command){dispatch_semaphore_signal(_inFlight);return;}
        id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];
        [encoder setRenderPipelineState:_pipeline];[encoder setFrontFacingWinding:MTLWindingClockwise];[encoder setCullMode:MTLCullModeNone];
        [encoder setVertexBuffer:buffer offset:0 atIndex:0];[encoder setFragmentTexture:_texture atIndex:0];
        Uniforms uniforms={{_model->viewportWidth,_model->viewportHeight,std::max(_model->viewportWidth,_model->viewportHeight)*1.5f,1}};
        [encoder setDepthStencilState:_shadowDepth];[encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];[encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:_indexCount indexType:MTLIndexTypeUInt32 indexBuffer:_indices indexBufferOffset:0];
        uniforms.viewport.w=0;[encoder setDepthStencilState:_depth];[encoder setVertexBytes:&uniforms length:sizeof(uniforms) atIndex:1];[encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:1];
        [encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle indexCount:_indexCount indexType:MTLIndexTypeUInt32 indexBuffer:_indices indexBufferOffset:0];
        [encoder endEncoding];[command presentDrawable:drawable];dispatch_semaphore_t semaphore=_inFlight;
        [command addCompletedHandler:^(id<MTLCommandBuffer> completed){if(completed.status==MTLCommandBufferStatusError)NSLog(@"Metal frame: %@",completed.error);dispatch_semaphore_signal(semaphore);}];
        [command commit];
        if(!wasSleeping&&_model->sleeping){dispatch_async(dispatch_get_main_queue(),^{[self save];[self refresh];});}
    }
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size { (void)view;(void)size; }
- (V3)point:(NSEvent *)event {
    NSPoint p=[_view convertPoint:event.locationInWindow fromView:nil];return {float(p.x),float(_view.bounds.size.height-p.y),0};
}
- (void)pollHover {
    std::lock_guard<std::recursive_mutex> guard(_mutex);
    if(_model->locked){_window.ignoresMouseEvents=YES;return;}
    if(_model->mode!=RugModel::Mode::Idle)return;
    NSPoint mouse=NSEvent.mouseLocation;NSRect frame=_window.frame;
    V3 p={float(mouse.x-frame.origin.x),float(frame.size.height-(mouse.y-frame.origin.y)),0};
    bool busy=NSEvent.pressedMouseButtons!=0&&_window.ignoresMouseEvents;
    _window.ignoresMouseEvents=busy||_model->pick(p)<0;
}
- (void)mouseDown:(NSEvent *)event {
    std::lock_guard<std::recursive_mutex> guard(_mutex);
    if(_model->locked)return;
    if(event.clickCount==2){_model->toggleFold();[self refresh];[self save];return;}
    _model->press([self point:event],event.modifierFlags&NSEventModifierFlagOption,event.modifierFlags&NSEventModifierFlagShift);
    [self refresh];
}
- (void)mouseDragged:(NSEvent *)event {std::lock_guard<std::recursive_mutex> guard(_mutex);_model->drag([self point:event]);[self refresh];}
- (void)mouseUp:(NSEvent *)event {(void)event;std::lock_guard<std::recursive_mutex> guard(_mutex);_model->release();[self save];[self refresh];}
- (void)scroll:(NSEvent *)event {std::lock_guard<std::recursive_mutex> guard(_mutex);_model->rotate(float(event.scrollingDeltaY)*(event.hasPreciseScrollingDeltas?.004f:.05f));[self save];[self refresh];}
- (void)contextMenu:(NSEvent *)event {if(!_model->locked){[self updateMenu];[NSMenu popUpContextMenu:self.menu withEvent:event forView:self.view];}}
- (void)hotKeyEvent:(UInt32)kind {
    if(kind==kEventHotKeyReleased){_hotKeyDown=NO;return;}
    if(!_hotKeyDown){_hotKeyDown=YES;[self toggleLock:nil];}
}
- (void)toggleLock:(id)sender {(void)sender;std::lock_guard<std::recursive_mutex> guard(_mutex);_model->setLocked(!_model->locked);if(_model->locked)_window.ignoresMouseEvents=YES;[self save];[self updateMenu];[self refresh];}
- (void)fold:(id)sender {(void)sender;std::lock_guard<std::recursive_mutex> guard(_mutex);_model->toggleFold();[self save];[self refresh];}
- (void)flatten:(id)sender {(void)sender;std::lock_guard<std::recursive_mutex> guard(_mutex);_model->flatten();[self save];[self refresh];}
- (void)center:(id)sender {(void)sender;std::lock_guard<std::recursive_mutex> guard(_mutex);_model->center();[self save];[self refresh];}
- (void)larger:(id)sender {(void)sender;std::lock_guard<std::recursive_mutex> guard(_mutex);_model->resize(1.06f);[self save];[self refresh];}
- (void)smaller:(id)sender {(void)sender;std::lock_guard<std::recursive_mutex> guard(_mutex);_model->resize(.94f);[self save];[self refresh];}
- (void)moveToScreen:(NSScreen *)screen {
    if(!screen)return;std::lock_guard<std::recursive_mutex> guard(_mutex);
    _displayID=screen.deviceDescription[@"NSScreenNumber"];NSRect frame=screen.frame;
    _model->setViewport(frame.size.width,frame.size.height);[_window setFrame:frame display:YES];_view.frame=NSMakeRect(0,0,frame.size.width,frame.size.height);
    [self save];[self refresh];
}
- (void)moveToDisplay:(id)sender {(void)sender;for(NSScreen *screen in NSScreen.screens)if(NSPointInRect(NSEvent.mouseLocation,screen.frame)){[self moveToScreen:screen];break;}}
- (void)displaysChanged:(NSNotification *)note {(void)note;NSScreen *chosen=nil;for(NSScreen *screen in NSScreen.screens)if([screen.deviceDescription[@"NSScreenNumber"] isEqual:_displayID])chosen=screen;[self moveToScreen:chosen?:NSScreen.screens.firstObject];}
- (void)save {
    std::lock_guard<std::recursive_mutex> guard(_mutex);if(!_model)return;
    NSMutableArray *positions=[NSMutableArray arrayWithCapacity:_model->cloth.count()*3];
    for(auto p:_model->cloth.pos){[positions addObject:@(p.x)];[positions addObject:@(p.y)];[positions addObject:@(p.z)];}
    NSDictionary *state=@{@"version":@1,@"width":@(_model->cloth.rw),@"height":@(_model->cloth.rh),@"viewportWidth":@(_model->viewportWidth),@"viewportHeight":@(_model->viewportHeight),@"locked":@(_model->locked),@"folded":@(_model->folded),@"positions":positions};
    [NSUserDefaults.standardUserDefaults setObject:state forKey:StateKey];
}
- (void)restore {
    id value=[NSUserDefaults.standardUserDefaults objectForKey:StateKey];if(![value isKindOfClass:NSDictionary.class])return;
    NSDictionary *state=value;NSArray *numbers=state[@"positions"];
    if(![numbers isKindOfClass:NSArray.class]||numbers.count>30000||numbers.count%3)return;
    for(id number in numbers)if(![number isKindOfClass:NSNumber.class])return;
    for(NSString *key in @[@"width",@"height",@"viewportWidth",@"viewportHeight",@"locked",@"folded"])if(![state[key] isKindOfClass:NSNumber.class])return;
    std::vector<V3> points;points.reserve(numbers.count/3);
    for(NSUInteger i=0;i<numbers.count;i+=3)points.push_back({[numbers[i] floatValue],[numbers[i+1] floatValue],[numbers[i+2] floatValue]});
    if(!_model->restore([state[@"width"] floatValue],[state[@"height"] floatValue],[state[@"viewportWidth"] floatValue],[state[@"viewportHeight"] floatValue],points,[state[@"locked"] boolValue],[state[@"folded"] boolValue]))NSLog(@"Ignored an invalid rug state; using the default pose.");
}
- (void)updateMenu {
    self.lockItem.state=_model->locked?NSControlStateValueOn:NSControlStateValueOff;
    self.loginItem.state=SMAppService.mainAppService.status==SMAppServiceStatusEnabled?NSControlStateValueOn:NSControlStateValueOff;
    for(NSMenuItem *item in self.menu.itemArray){if(item.tag==10)item.enabled=!_model->locked;}
}
- (void)toggleLogin:(id)sender {
    (void)sender;NSError *error=nil;SMAppService *service=SMAppService.mainAppService;
    if(service.status==SMAppServiceStatusEnabled)[service unregisterAndReturnError:&error];else [service registerAndReturnError:&error];
    if(error){NSAlert *alert=[NSAlert new];alert.messageText=@"Could not change automatic startup";alert.informativeText=@"Move the app to Applications and try again, or add it manually in System Settings → General → Login Items.";[alert addButtonWithTitle:@"Open Login Items"];[alert addButtonWithTitle:@"Later"];if([alert runModal]==NSAlertFirstButtonReturn)[SMAppService openSystemSettingsLoginItems];NSLog(@"Login item: %@",error);}
    if(service.status==SMAppServiceStatusRequiresApproval){NSAlert *alert=[NSAlert new];alert.messageText=@"Allow The Magical Rug at login";alert.informativeText=@"Approve The Magical Rug in System Settings → General → Login Items.";[alert addButtonWithTitle:@"Open Login Items"];[alert addButtonWithTitle:@"Later"];if([alert runModal]==NSAlertFirstButtonReturn)[SMAppService openSystemSettingsLoginItems];}
    [self updateMenu];
}
- (void)showWelcome {
    if([NSUserDefaults.standardUserDefaults boolForKey:@"DidShowWelcome"]){if(!_hotKey){NSAlert *a=[NSAlert new];a.messageText=@"The rug shortcut is unavailable";a.informativeText=@"Control–Option–R is in use by another app. You can still lock and unlock the rug from its menu bar menu.";[a runModal];}return;}
    NSAlert *alert=[NSAlert new];alert.messageText=@"The Magical Rug";
    alert.informativeText=@"Drag the middle to move the rug. Drag a corner to lift it over the top. Control–Option–R locks or unlocks it. The rug menu in the menu bar has all the controls.\n\nYour wallpaper and desktop files stay independent.";
    NSButton *login=[NSButton checkboxWithTitle:@"Open automatically when I log in" target:nil action:nil];login.state=NSControlStateValueOn;login.frame=NSMakeRect(0,0,310,24);alert.accessoryView=login;
    [alert addButtonWithTitle:@"Start Using the Rug"];[NSApp activateIgnoringOtherApps:YES];[alert runModal];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"DidShowWelcome"];
    if(login.state==NSControlStateValueOn&&SMAppService.mainAppService.status!=SMAppServiceStatusEnabled)[self toggleLogin:nil];
    if(!_hotKey){NSAlert *a=[NSAlert new];a.messageText=@"Control–Option–R is already in use";a.informativeText=@"Use Lock or Unlock from the rug menu in the menu bar, or free that shortcut in the other app.";[a runModal];}
}
@end

@interface AppDelegate : NSObject<NSApplicationDelegate,NSMenuDelegate>
@property(nonatomic,strong) RugController *controller;
@property(nonatomic,strong) NSStatusItem *statusItem;
@end
@implementation AppDelegate
- (NSMenuItem *)add:(NSString *)title action:(SEL)action menu:(NSMenu *)menu {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];item.target=self.controller;[menu addItem:item];return item;
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;NSError *error=nil;self.controller=[[RugController alloc] initWithError:&error];
    if(!self.controller){NSAlert *alert=[NSAlert new];alert.messageText=@"The Magical Rug could not start";alert.informativeText=error.localizedDescription?:@"The graphics renderer could not be initialized.";[alert runModal];[NSApp terminate:nil];return;}
    NSMenu *menu=[NSMenu new];menu.autoenablesItems=NO;menu.delegate=self;
    NSMenuItem *heading=[[NSMenuItem alloc] initWithTitle:@"The Magical Rug" action:nil keyEquivalent:@""];heading.enabled=NO;[menu addItem:heading];
    self.controller.lockItem=[self add:@"Lock or Unlock    ⌃⌥R" action:@selector(toggleLock:) menu:menu];
    for(NSArray *entry in @[@[@"Fold or Flatten",NSStringFromSelector(@selector(fold:))],@[@"Flatten Rug",NSStringFromSelector(@selector(flatten:))],@[@"Center Rug",NSStringFromSelector(@selector(center:))],@[@"Make Larger",NSStringFromSelector(@selector(larger:))],@[@"Make Smaller",NSStringFromSelector(@selector(smaller:))]]){[self add:entry[0] action:NSSelectorFromString(entry[1]) menu:menu].tag=10;}
    [menu addItem:NSMenuItem.separatorItem];[self add:@"Move to This Display" action:@selector(moveToDisplay:) menu:menu].tag=10;
    self.controller.loginItem=[self add:@"Open at Login" action:@selector(toggleLogin:) menu:menu];
    NSMenuItem *help=[[NSMenuItem alloc] initWithTitle:@"Installation and Help" action:@selector(help:) keyEquivalent:@""];help.target=self;[menu addItem:help];
    [menu addItem:NSMenuItem.separatorItem];NSMenuItem *quit=[[NSMenuItem alloc] initWithTitle:@"Quit The Magical Rug" action:@selector(terminate:) keyEquivalent:@"q"];quit.target=NSApp;[menu addItem:quit];
    self.controller.menu=menu;
    self.statusItem=[NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    NSImage *image=[NSImage imageWithSystemSymbolName:@"rectangle.on.rectangle" accessibilityDescription:@"The Magical Rug"];
    self.statusItem.button.image=image;self.statusItem.button.toolTip=@"The Magical Rug";self.statusItem.menu=menu;
    [self.controller updateMenu];[self.controller showWelcome];
}
- (void)menuWillOpen:(NSMenu *)menu {(void)menu;[self.controller updateMenu];}
- (void)help:(id)sender {(void)sender;NSURL *url=[NSBundle.mainBundle URLForResource:@"INSTALL" withExtension:@"html"];if(url)[NSWorkspace.sharedWorkspace openURL:url];}
- (void)applicationWillTerminate:(NSNotification *)note {(void)note;[self.controller save];}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)visible {(void)sender;(void)visible;[self.statusItem.menu update];return NO;}
@end
int main(int argc,const char *argv[]) {
    (void)argc;(void)argv;@autoreleasepool{NSApplication *app=NSApplication.sharedApplication;app.activationPolicy=NSApplicationActivationPolicyAccessory;__attribute__((objc_precise_lifetime)) AppDelegate *delegate=[AppDelegate new];app.delegate=delegate;[app run];}return 0;
}
