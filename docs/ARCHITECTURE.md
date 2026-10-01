# iPhone-first foundation

The product specification remains in README.md. Implementation starts with:

- Native SwiftUI iPhone app, AVPlayer replay, Swift Charts telemetry.
- Shared Swift core for API models and telemetry interpolation.
- Go HTTP API, deployable as a standalone container.
- Planned PostgreSQL metadata, Cloudflare R2 masters/telemetry, Cloudflare Stream
  playback, and separate processing workers.

The client owns camera connectivity and media acquisition. The server owns access
control, ingestion state, processing, and short-lived media URLs. Original media
should transfer directly to storage using authorized resumable uploads, rather
than through API memory. Processing jobs must survive app closure.

Heavy GPMF/FFmpeg work belongs in a background worker with a durable job queue;
container workers are distinct from Cloudflare Workers. Stream encoding completion
must be reflected in media state before playback is offered. The jump remains an
Activity specialization, with device-independent telemetry and source provenance.

## First real-footage milestone

1. Obtain one GPS-enabled GoPro skydive MP4 and inspect its tracks/timestamps.
2. Parse GPMF into source-specific normalized streams, retaining fix/accuracy and
   altitude datum. Account for chaptered camera files and missing GPS.
3. Import a local file on iPhone and prove synchronized video, altitude, and speed.
4. Validate phase detection with manual corrections and measured confidence.
5. Add authentication and PostgreSQL with owner-scoped private activities.
6. Add R2 uploads, durable processing, Stream playback, and hosted HTTPS API.
7. Measure range-read clipping efficiency and GPMF timestamp preservation using
   real footage before promising original-quality freefall clips.
8. Add participant confirmation, sharing, signed downloads, and expiring clips.

Private jumps must become the default when real user data is introduced. Public
viewing must not imply downloading rights. The current demo endpoints expose only
synthetic data and must not be repurposed to serve private data without auth.

## Decisions still to make

- API/worker host and region, deployment account, and domain.
- Authentication provider and Apple sign-in flow.
- Supported GoPro models and real test footage.
- Retention policy, quotas, and upload recovery behavior.

These do not block the read-only demo. They precede real-user cloud ingestion.
