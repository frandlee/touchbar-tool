#import "Bridge.h"
#import <objc/runtime.h>
#include <string.h>

// Private API: inspect class method signatures before calling their IMPs.
// The two-argument form follows MTMR's Control Strip-preserving path.
static Method checked(NSString *name, unsigned int count) {
    Method m = class_getClassMethod([NSTouchBar class], NSSelectorFromString(name));
    if (!m || method_getNumberOfArguments(m) != count) return NULL;
    char type[64];
    method_getReturnType(m, type, sizeof(type));
    if (strcmp(type, "v") != 0) return NULL;
    for (unsigned int i = 2; i < count; ++i) {
        method_getArgumentType(m, i, type, sizeof(type));
        if (strcmp(type, "@") != 0) return NULL;
    }
    return m;
}
static NSString *presentName(void) {
    for (NSString *name in @[@"presentSystemModalTouchBar:systemTrayItemIdentifier:",
                              @"presentSystemModalFunctionBar:systemTrayItemIdentifier:"])
        if (checked(name, 4)) return name;
    return nil;
}
static NSString *dismissName(void) {
    for (NSString *name in @[@"dismissSystemModalTouchBar:", @"dismissSystemModalFunctionBar:"])
        if (checked(name, 3)) return name;
    return nil;
}
BOOL CTBAvailable(void) { return presentName() != nil && dismissName() != nil; }
BOOL CTBPresent(NSTouchBar *bar) {
    NSString *name = presentName();
    if (!name || !dismissName()) return NO;
    @try {
        ((void (*)(id, SEL, id, id))method_getImplementation(checked(name, 4)))
            ([NSTouchBar class], NSSelectorFromString(name), bar, nil);
        return YES; // Invocation only; does not prove visible hardware output.
    } @catch (NSException *exception) { return NO; }
}
BOOL CTBDismiss(NSTouchBar *bar) {
    NSString *name = dismissName();
    if (!name) return NO;
    @try {
        ((void (*)(id, SEL, id))method_getImplementation(checked(name, 3)))
            ([NSTouchBar class], NSSelectorFromString(name), bar);
        return YES;
    } @catch (NSException *exception) { return NO; }
}
