// DYLD-вставка для оконных проб Godot на macOS (по образцу проекта fgame/tools/godot_bg): процесс не активируется,
// не попадает в Dock и не забирает фокус. Godot при старте сам делает себя обычным приложением (setActivationPolicy:Regular),
// активируется и дёргает TransformProcessType — здесь все эти вызовы превращаются в ничто.
// Собирают и подставляют godot/tools/godot_bg.sh и godot/tools/godot_nofocus.sh.
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void replace(Class cls, SEL sel, IMP imp) {
	Method m = class_getInstanceMethod(cls, sel);
	if (m != NULL) {
		method_setImplementation(m, imp);
	}
}

// Политика всегда «без Dock и без активации», что бы Godot ни просил.
static IMP orig_set_policy;
static BOOL set_policy(id self, SEL sel, NSApplicationActivationPolicy policy) {
	return ((BOOL (*)(id, SEL, NSApplicationActivationPolicy))orig_set_policy)(self, sel, NSApplicationActivationPolicyProhibited);
}

static void no_activate_ignoring(id self, SEL sel, BOOL flag) {}
static void no_activate(id self, SEL sel) {}
static BOOL no_activate_with_options(id self, SEL sel, NSApplicationActivationOptions options) { return NO; }
static void no_make_key(id self, SEL sel) {}
static void order_front_only(id self, SEL sel, id sender) { [self orderFront:sender]; }

// TransformProcessType из «хака» Godot: превращение в обычное приложение — отказываем молча.
extern OSStatus TransformProcessType(const ProcessSerialNumber *psn, UInt32 type);
static OSStatus no_transform(const ProcessSerialNumber *psn, UInt32 type) { return noErr; }
__attribute__((used, section("__DATA,__interpose"))) static struct {
	const void *replacement;
	const void *original;
} interpose_transform = { (const void *)no_transform, (const void *)TransformProcessType };

__attribute__((constructor)) static void nofocus_init(void) {
	Class app = [NSApplication class];
	Method m = class_getInstanceMethod(app, @selector(setActivationPolicy:));
	orig_set_policy = method_getImplementation(m);
	method_setImplementation(m, (IMP)set_policy);
	replace(app, @selector(activateIgnoringOtherApps:), (IMP)no_activate_ignoring);
	replace(app, NSSelectorFromString(@"activate"), (IMP)no_activate);
	replace([NSRunningApplication class], @selector(activateWithOptions:), (IMP)no_activate_with_options);
	replace([NSWindow class], @selector(makeKeyWindow), (IMP)no_make_key);
	replace([NSWindow class], @selector(makeKeyAndOrderFront:), (IMP)order_front_only);
}
