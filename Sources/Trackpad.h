#pragma once

#include <stdint.h>

typedef struct {
    uintptr_t device;
    int count;
    double x;
    double y;
    double timestamp;
} TrackpadFrame;

typedef void (*TrackpadSink)(TrackpadFrame frame);

// Returns the number of devices, or -1 if the private interface is unavailable.
int TrackpadStart(TrackpadSink sink);
void TrackpadStop(void);
