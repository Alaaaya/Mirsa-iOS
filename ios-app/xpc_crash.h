//
//  xpc_crash.h
//  AirCard-iOS
//
//  Userspace respring helpers (from Cowabunga / Project Zero xpc w00t).
//

#ifndef xpc_crash_h
#define xpc_crash_h

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Crash an XPC service by name (triggers relaunch of the hosting process).
void xpc_crasher(const char *service_name);

/// Respring via crashing com.apple.backboard.TouchDeliveryPolicyServer
void restartBackboard(void);

/// Respring via crashing com.apple.frontboard.systemappservices
void restartFrontboard(void);

/// Respring via crashing com.apple.springboard.services
void restartSpringboard(void);

#ifdef __cplusplus
}
#endif

#endif /* xpc_crash_h */
