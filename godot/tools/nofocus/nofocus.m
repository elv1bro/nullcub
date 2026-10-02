// DYLD-вставка для оконных проб Godot на macOS: процесс не активируется и не забирает фокус у того, чем занят человек.
// Собирает и подставляет godot/tools/godot_nofocus.sh; бинарь и подпись Godot не трогаются
// (в entitlements официального Godot уже есть allow-dyld-environment-variables и disable-library-validation).
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

static void stub(Class cls, SEL sel, id block) {
	Method m = class_getInstanceMethod(cls, sel);
	if (m) method_setImplementation(m, imp_implementationWithBlock(block));
}

__attribute__((constructor)) static void nofocus_init(void) {
	stub([NSApplication class], @selector(activateIgnoringOtherApps:), ^(id s, BOOL f) {});
	stub([NSApplication class], @selector(activate), ^(id s) {});
	stub([NSRunningApplication class], @selector(activateWithOptions:), ^BOOL(id s, NSUInteger o) { return NO; });
	// Accessory: без иконки в Dock и без права становиться frontmost.
	Method m = class_getInstanceMethod([NSApplication class], @selector(setActivationPolicy:));
	if (m) {
		BOOL (*orig)(id, SEL, NSApplicationActivationPolicy) = (void *)method_getImplementation(m);
		method_setImplementation(m, imp_implementationWithBlock(^BOOL(id s, NSApplicationActivationPolicy p) {
			return orig(s, @selector(setActivationPolicy:), NSApplicationActivationPolicyAccessory);
		}));
	}
}
