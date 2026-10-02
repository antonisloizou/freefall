#ifndef FREEFALL_GPMF_H
#define FREEFALL_GPMF_H

#include <stdint.h>

typedef struct {
    double time;
    double x;
    double y;
    double z;
} FFMotionSample;

typedef struct {
    FFMotionSample *samples;
    uint32_t count;
} FFMotionSamples;

// Returns 0 on success, including when the file has no matching stream.
int FFExtractMotion(const char *path, uint32_t fourcc, FFMotionSamples *result);
void FFFreeMotion(FFMotionSamples result);

#endif
