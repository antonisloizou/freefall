#include "FreefallGPMF.h"
#include "GPMF_common.h"
#include "GPMF_mp4reader.h"
#include "GPMF_parser.h"

#include <stdlib.h>

static int append_samples(
    FFMotionSamples *result,
    GPMF_stream *stream,
    double start,
    double end
) {
    uint32_t count = GPMF_Repeat(stream);
    uint32_t elements = GPMF_ElementsInStruct(stream);
    if (count == 0 || elements < 3) return 0;

    uint32_t value_count = count * elements;
    double *values = malloc(value_count * sizeof(double));
    if (!values) return 2;
    if (GPMF_OK != GPMF_ScaledData(
        stream,
        values,
        value_count * sizeof(double),
        0,
        count,
        GPMF_TYPE_DOUBLE
    )) {
        free(values);
        return 3;
    }

    uint32_t old_count = result->count;
    FFMotionSample *expanded = realloc(
        result->samples,
        (old_count + count) * sizeof(FFMotionSample)
    );
    if (!expanded) {
        free(values);
        return 2;
    }
    result->samples = expanded;
    double interval = (end - start) / count;
    for (uint32_t index = 0; index < count; index++) {
        FFMotionSample sample;
        sample.time = start + (index + 0.5) * interval;
        sample.x = values[index * elements];
        sample.y = values[index * elements + 1];
        sample.z = values[index * elements + 2];
        result->samples[old_count + index] = sample;
    }
    result->count += count;
    free(values);
    return 0;
}

int FFExtractMotion(const char *path, uint32_t fourcc, FFMotionSamples *result) {
    if (!path || !result) return 1;
    result->samples = NULL;
    result->count = 0;

    size_t source = OpenMP4Source(
        (char *)path,
        MOV_GPMF_TRAK_TYPE,
        MOV_GPMF_TRAK_SUBTYPE,
        0
    );
    if (!source) return 0;

    size_t payload_resource = 0;
    uint32_t payload_count = GetNumberPayloads(source);
    int status = 0;
    for (uint32_t payload_index = 0; payload_index < payload_count; payload_index++) {
        uint32_t payload_size = GetPayloadSize(source, payload_index);
        payload_resource = GetPayloadResource(source, payload_resource, payload_size);
        uint32_t *payload = GetPayload(source, payload_resource, payload_index);
        double start = 0;
        double end = 0;
        if (!payload || GPMF_OK != GetPayloadTime(source, payload_index, &start, &end)) {
            continue;
        }

        GPMF_stream stream = {0};
        if (GPMF_OK != GPMF_Init(&stream, payload, payload_size)) continue;
        while (GPMF_OK == GPMF_FindNext(
            &stream,
            GPMF_KEY_STREAM,
            GPMF_RECURSE_LEVELS | GPMF_TOLERANT
        )) {
            if (GPMF_OK != GPMF_FindNext(
                &stream,
                fourcc,
                GPMF_RECURSE_LEVELS | GPMF_TOLERANT
            )) continue;
            status = append_samples(result, &stream, start, end);
            if (status != 0) break;
        }
        if (status != 0) break;
    }

    FreePayloadResource(source, payload_resource);
    CloseSource(source);
    if (status != 0) {
        FFFreeMotion(*result);
        result->samples = NULL;
        result->count = 0;
    }
    return status;
}

void FFFreeMotion(FFMotionSamples result) {
    free(result.samples);
}
