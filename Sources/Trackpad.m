#import "Trackpad.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <math.h>
#import <stdlib.h>
#import <stdatomic.h>

// Undocumented MultitouchSupport contact ABI, used by macOS Sequoia.
// These declarations are the only private interface in the application.
typedef struct { float x, y; } TouchPoint;
typedef struct { TouchPoint position, velocity; } TouchVector;
typedef struct {
    int frame;
    double timestamp;
    int identifier, state, finger, hand;
    TouchVector normalized;
    float size, pressure, angle, majorAxis, minorAxis;
    TouchVector absolute;
    float reserved1, reserved2, density;
} TouchContact;

_Static_assert(sizeof(TouchContact) == 96, "Unexpected contact ABI");

typedef void *TouchDevice;
typedef int (*ContactCallback)(TouchDevice, TouchContact *, int, double, int);
typedef CFArrayRef (*CreateDevices)(void);
typedef void (*RegisterCallback)(TouchDevice, ContactCallback);
typedef int (*StartDevice)(TouchDevice, int);
typedef void (*StopDevice)(TouchDevice);
typedef bool (*IsBuiltIn)(TouchDevice);
typedef int (*GetFamily)(TouchDevice, int *);

static void *framework;
static CFMutableArrayRef devices;
static RegisterCallback registerCallback;
static RegisterCallback unregisterCallback;
static StartDevice startDevice;
static StopDevice stopDevice;
static TrackpadSink frameSink;
static atomic_uint generation;

typedef struct {
    TrackpadFrame frame;
    unsigned int generation;
} PendingFrame;

static void deliverFrame(void *context) {
    PendingFrame *pending = context;
    if (frameSink && pending->generation == atomic_load(&generation)) {
        frameSink(pending->frame);
    }
    free(pending);
}

static int receiveContacts(TouchDevice device, TouchContact *contacts,
                           int count, double timestamp, int frame) {
    if (count < 0 || count > 16 || (count > 0 && contacts == NULL)) {
        return 0;
    }

    TrackpadFrame snapshot = { .device = (uintptr_t)device, .timestamp = timestamp };
    for (int i = 0; i < count; i++) {
        TouchContact contact = contacts[i];
        if (contact.state != 3 && contact.state != 4) {
            continue;
        }
        double x = contact.normalized.position.x;
        double y = contact.normalized.position.y;
        if (!isfinite(x) || !isfinite(y) || x < 0 || x > 1 || y < 0 || y > 1) {
            return 0;
        }
        snapshot.count++;
        snapshot.x += x;
        snapshot.y += y;
    }

    if (snapshot.count > 0) {
        snapshot.x /= snapshot.count;
        snapshot.y /= snapshot.count;
    }

    PendingFrame *pending = malloc(sizeof(PendingFrame));
    if (pending == NULL) {
        return 0;
    }
    pending->frame = snapshot;
    pending->generation = atomic_load(&generation);
    dispatch_async_f(dispatch_get_main_queue(), pending, deliverFrame);
    return 0;
}

int TrackpadStart(TrackpadSink sink) {
    TrackpadStop();
    if (framework == NULL) {
        framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
    }
    if (framework == NULL) {
        return -1;
    }

    CreateDevices createDevices = dlsym(framework, "MTDeviceCreateList");
    IsBuiltIn isBuiltIn = dlsym(framework, "MTDeviceIsBuiltIn");
    GetFamily getFamily = dlsym(framework, "MTDeviceGetFamilyID");
    registerCallback = dlsym(framework, "MTRegisterContactFrameCallback");
    unregisterCallback = dlsym(framework, "MTUnregisterContactFrameCallback");
    startDevice = dlsym(framework, "MTDeviceStart");
    stopDevice = dlsym(framework, "MTDeviceStop");
    if (!createDevices || !isBuiltIn || !getFamily || !registerCallback || !unregisterCallback || !startDevice || !stopDevice) {
        return -1;
    }

    CFArrayRef available = createDevices();
    if (available == NULL) {
        return 0;
    }
    devices = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    frameSink = sink;
    for (CFIndex i = 0; i < CFArrayGetCount(available); i++) {
        TouchDevice device = (TouchDevice)CFArrayGetValueAtIndex(available, i);
        int family = 0;
        if (getFamily(device, &family) != 0) {
            continue;
        }
        bool trackpad = (family >= 98 && family <= 111)
            || (family >= 128 && family <= 130)
            || (family == 113 && isBuiltIn(device));
        if (!trackpad) {
            continue;
        }
        registerCallback(device, receiveContacts);
        if (startDevice(device, 0) == 0) {
            CFArrayAppendValue(devices, device);
        } else {
            unregisterCallback(device, receiveContacts);
        }
    }
    CFRelease(available);
    return (int)CFArrayGetCount(devices);
}

void TrackpadStop(void) {
    frameSink = NULL;
    atomic_fetch_add(&generation, 1);
    if (devices == NULL) {
        return;
    }
    for (CFIndex i = 0; i < CFArrayGetCount(devices); i++) {
        TouchDevice device = (TouchDevice)CFArrayGetValueAtIndex(devices, i);
        stopDevice(device);
        unregisterCallback(device, receiveContacts);
    }
    CFRelease(devices);
    devices = NULL;
}
