# FREEFALL

**Working title:** FREEFALL  
**Version:** 0.3  
**Concept:** A Strava/Slopes-style activity platform for skydiving, built around automatic telemetry, video, analysis, sharing, and collaborative jump media.

---

## Implementation status

The repository now includes an iPhone-first SwiftUI starter and a container-ready
Go demo API. The first slice shows a synthetic jump, synchronized telemetry
scrubbing, jump events, and an altitude chart. Cloud hosting, real GoPro ingestion,
authentication, and media storage are still to be implemented.

See [development instructions](docs/DEVELOPMENT.md) to run the app/backend and
[architecture notes](docs/ARCHITECTURE.md) for the path to real footage and hosting.

---

# 1. Vision

FREEFALL turns a skydive into a rich digital activity.

Instead of manually logging a jump, a user connects a supported device such as a GoPro. FREEFALL imports the footage and telemetry, identifies the jump, analyzes it, and creates an interactive activity containing:

- Video
- GPS trajectory
- Exit and deployment altitude
- Freefall time
- Vertical and 3D speed
- Horizontal speed and distance
- G-force / IMU data
- Canopy flight
- Jump statistics
- Location
- Equipment
- Other jumpers
- Photos and additional video angles

The resulting activity can be analyzed privately or shared publicly in the same way an athlete shares an activity on Strava.

**Core proposition:**

> **Relive your jump.**

FREEFALL is not primarily a digital logbook. It is a platform for **watching, analyzing, sharing, downloading, and discovering skydives**.

---

# 2. Product Principles

## 2.1 The Jump Is the Core Object

The fundamental object is a **Jump**, not a video.

A Jump can contain:

- One or more videos
- One or more telemetry sources
- Multiple participants
- Equipment
- DZ/location
- Weather
- Jump type
- Analysis
- Social interaction

Internally, a Jump should be implemented as a specialized **Activity**, allowing the architecture to support other air sports later.

Potential future activity types:

- BASE
- Wingsuit
- Speedflying
- Paragliding
- Paramotor

The initial product remains explicitly focused on skydiving.

## 2.2 Device-Agnostic Data Model

GoPro is the initial acquisition platform, but GoPro telemetry must not become the internal FREEFALL data model.

Each telemetry source is normalized into timestamped samples.

Canonical units:

- Time: seconds
- Distance: metres
- Altitude: metres
- Speed: metres/second
- Coordinates: WGS84 decimal degrees
- Acceleration: m/s² or normalized G

Future telemetry sources may include:

- GoPro GPMF
- FlySight
- Garmin
- Apple Watch
- iPhone
- Android
- Smart altimeters
- AAD exports
- Insta360
- Other GPS/IMU devices

Multiple sources may contribute data to the same Jump.

---

# 3. Primary User Flow

1. User logs into FREEFALL.
2. User connects a GoPro.
3. FREEFALL displays the GoPro media library.
4. User selects a video.
5. FREEFALL extracts GPMF telemetry.
6. Original media is uploaded.
7. Video is made available to Cloudflare Stream for social playback.
8. Telemetry is normalized and stored separately.
9. FREEFALL analyzes the telemetry.
10. FREEFALL identifies jump phases.
11. A Jump activity is generated.
12. User reviews/edits the Jump.
13. User tags other jumpers.
14. User publishes or keeps the Jump private.
15. Jump receives a shareable URL.
16. Authorized participants can watch and download footage.

Long-term target:

**Connect GoPro → jump → FREEFALL automatically creates the activity.**

---

# 4. GoPro Integration

Use the official Open GoPro API.

Initial functionality:

- Discover/connect camera
- Read camera status
- Browse media library
- Retrieve thumbnails
- Select media
- Download/read media
- Retrieve metadata
- Optionally control recording

Recorded GoPro media may contain:

- GPS position
- GPS altitude
- Ground speed
- 3D speed
- GPS accuracy/fix
- Accelerometer
- Gyroscope
- Orientation
- Gravity
- Camera metadata

GPMF must be extracted while the original media remains available.

---

# 5. Media Architecture

FREEFALL maintains two conceptually different video assets.

## 5.1 Master

The high-quality uploaded GoPro file.

Stored in Cloudflare R2 when retention is enabled.

Purpose:

- Original-quality downloads
- Original-quality clipping
- Telemetry preservation
- Future processing
- Re-rendering
- Archival

## 5.2 Viewing Copy

Cloudflare Stream handles:

- Transcoding
- Adaptive bitrate
- HLS/DASH
- Global delivery
- Social playback

Stream is optimized for viewing rather than preservation of the camera master.

Architecture:

```text
                   GoPro Master
                        │
              ┌─────────┴─────────┐
              │                   │
              ▼                   ▼
             R2                 Stream
       original-quality       viewing copy
             │                 ≤1080p
             │                   │
             ▼                   ▼
     original downloads     social playback
     on-demand clips        telemetry player
```

---

# 6. Telemetry Architecture

GPMF is extracted and normalized independently from video delivery.

Example normalized sample:

```json
{
  "t": 37.42,
  "gps": {
    "lat": 45.1234,
    "lon": 6.1234,
    "altitude": 3782
  },
  "velocity": {
    "ground": 18.4,
    "vertical": -52.8,
    "speed3d": 54.3
  },
  "motion": {
    "g": 1.08
  }
}
```

Different streams may retain different sampling rates.

For example:

```text
GPS       ~10 Hz
Accel     high frequency
Gyro      high frequency
Events    sparse
```

The application should not unnecessarily expand all sensor streams into one fixed-rate dataset.

---

# 7. Interactive Player

The video timeline is authoritative.

```text
video.currentTime
       │
       ▼
TelemetryEngine.at(time)
       │
       ▼
PlayerState
       │
       ├── overlays
       ├── graphs
       └── map
```

The telemetry engine interpolates between samples.

Synchronization must work during:

- Playback
- Pause
- Seeking
- Playback-rate changes

Initial overlays:

- Altitude
- 3D speed
- Vertical speed

Later:

- G-force
- Heading
- Ground speed
- GPS position
- Freefall time
- Event indicators

---

# 8. Replay Modes

## Minimal

- Altitude
- Speed
- Freefall time
- Major events

## Analysis

- Altitude
- Vertical speed
- 3D speed
- Ground speed
- G-force
- Heading
- Graphs

## Map

- Exit
- GPS trajectory
- Deployment
- Canopy track
- Landing

## Cinematic

Dynamic event graphics such as:

```text
EXIT
13,200 ft
```

```text
MAX SPEED
287 km/h
```

```text
DEPLOYMENT
3,400 ft
```

---

# 9. Jump Events

FREEFALL stores important moments as timestamps rather than generating separate media files.

Example:

```text
VIDEO START      0.00

EXIT           522.42
DEPLOYMENT     581.71
LANDING        872.30

VIDEO END      910.20
```

These events define logical sections.

```text
PLANE
0 → EXIT

FREEFALL
EXIT → DEPLOYMENT

CANOPY
DEPLOYMENT → LANDING

AFTER LANDING
LANDING → END
```

These sections are metadata.

**They are not permanently stored as separate video files.**

---

# 10. Automatic Jump Analysis

FREEFALL should detect:

```text
Aircraft
   ↓
Exit
   ↓
Freefall
   ↓
Deployment
   ↓
Canopy
   ↓
Landing
```

Potential detection inputs:

- Altitude change
- Vertical velocity
- 3D velocity
- Acceleration
- GPS movement
- Sustained movement patterns

All detected events must allow manual correction.

Derived metrics include:

### Exit

- Time
- Altitude
- GPS position

### Freefall

- Duration
- Maximum 3D speed
- Maximum vertical speed
- Average vertical speed
- Horizontal distance
- Trajectory

### Deployment

- Time
- Altitude
- Deceleration profile

### Canopy

- Duration
- Distance
- Speed
- Descent rate
- Flight path

### Landing

- Time
- Coordinates
- Potential landing speed

---

# 11. Shared Jumps

Multiple users may participate in the same physical Jump.

Matching signals may include:

- GPS location
- Exit time
- DZ
- Aircraft/load
- User tagging

```text
                 JUMP
                   │
        ┌──────────┼──────────┐
        │          │          │
     Antonis    Jumper B   Jumper C
        │          │          │
     GoPro A     GoPro B    FlySight
        │          │          │
        └──────────┼──────────┘
                   │
             Shared activity
```

Future versions may synchronize multiple camera angles against one shared timeline.

---

# 12. Media Sharing & Permissions

Public viewing and downloading are separate permissions.

Potential settings:

```text
Visibility
● Public

Downloads
☑ Confirmed jump participants
☐ Everyone

Original quality
☑ Participants
☐ Public
```

## Owner

The uploader can download retained media.

## Confirmed Participant

A confirmed participant may download media when participant downloads are enabled.

## Public

Anyone able to view a public Jump may download media only when public downloads are explicitly enabled.

Private media must never rely on permanent publicly accessible object URLs.

Use authorization plus short-lived signed URLs.

---

# 13. Download Experience

A user should not need to download a complete multi-gigabyte GoPro file merely to obtain the useful portion.

Example:

```text
DOWNLOAD

● Freefall
  Exit -5s → Deployment +10s
  Original 5.3K
  ~800 MB

○ Exit → Landing
  Original 5.3K
  ~2.4 GB

○ Canopy
  Original 5.3K
  ~1.6 GB

○ Full original
  5.3K
  6.0 GB

○ Custom range
```

Possible additional download:

```text
Freefall
1080p
with FREEFALL telemetry overlay
```

Default padding should be configurable.

Initial suggestion:

```text
Freefall download:
EXIT -5 seconds
→
DEPLOYMENT +10 seconds
```

---

# 14. Master + Logical Range Model

FREEFALL must avoid permanently storing every possible derivative.

Do **not** create permanent:

```text
plane.mp4
freefall.mp4
canopy.mp4
after-landing.mp4
```

Instead retain:

```text
GX010123.MP4
```

plus:

```json
{
  "exit": 522.42,
  "deployment": 581.71,
  "landing": 872.30
}
```

A requested clip is simply:

```text
MASTER
+
START
+
END
+
DOWNLOAD PROFILE
```

For example:

```text
source: GX010123
start: 517.42
end:   591.71
profile: original
```

This preserves a **single permanent master**.

---

# 15. Original-Quality On-Demand Clipping

Original-quality clips should be generated from the R2 master rather than from Cloudflare Stream.

Cloudflare Stream derivatives are limited to Stream's transcoded quality.

The original-quality pipeline is:

```text
R2 MASTER
6 GB / 5.3K
     │
     │ HTTP range reads
     ▼
Clip Worker
FFmpeg
     │
     │ stream copy
     ▼
Original-quality clip
     │
     ▼
Authorized user
```

FFmpeg should use stream copying where possible rather than re-encoding.

Conceptually:

```bash
ffmpeg \
  -ss START \
  -i SIGNED_R2_URL \
  -t DURATION \
  -map 0 \
  -c copy \
  OUTPUT.mp4
```

Benefits:

- Original resolution
- Original codec
- Original bitrate
- No generation quality loss
- Very low processing cost compared with transcoding

---

# 16. R2 Range Reads

R2 supports HTTP byte-range access.

The clip worker should access the master through a short-lived authenticated/presigned URL.

FFmpeg can seek against a range-capable HTTP source.

Therefore extracting one minute from a 6 GB GoPro file should **not inherently require downloading all 6 GB into the worker first**.

Conceptual flow:

```text
              R2
       6 GB GoPro master
               │
        requested ranges
               │
               ▼
          FFmpeg worker
               │
               ▼
           clip output
```

Actual byte-read behavior must be measured against real GoPro files during the prototype.

---

# 17. Ephemeral Clip Generation

Derived original-quality clips are temporary artifacts.

Preferred production behavior:

```text
R2 MASTER
    │
    ▼
FFmpeg
    │
    ▼
ephemeral worker disk
    │
    ▼
HTTP download
    │
    ▼
DELETE
```

For example:

```text
Permanent storage:

GX010123.MP4        6.0 GB

Temporary:

/tmp/freefall.mp4   0.8 GB

after delivery:

/tmp/freefall.mp4   DELETED
```

The temporary file does not count toward long-term user storage.

This allows FFmpeg to create a conventional finalized MP4 with maximum compatibility.

---

# 18. Direct Streaming Alternative

A future optimization may eliminate the temporary output file.

FFmpeg can output fragmented MP4:

```text
R2
 │
 ▼
FFmpeg
 │
 │ fragmented MP4
 ▼
HTTP response
 │
 ▼
User
```

Potential FFmpeg configuration:

```bash
-movflags frag_keyframe+empty_moov
-f mp4
pipe:1
```

Advantages:

- No temporary output file
- Download can begin immediately
- Very low storage overhead

Disadvantage:

Fragmented MP4 may have lower compatibility with some:

- Video editors
- Mobile applications
- Social platforms
- Legacy players

Therefore direct fMP4 streaming should be considered an optimization, not an MVP requirement.

---

# 19. Temporary Clip Cache

When several participants request the same clip, FREEFALL should avoid repeating identical processing.

Example:

A 10-way generates:

```text
source:
GX010123

range:
EXIT -5s
→
DEPLOYMENT +10s

profile:
ORIGINAL
```

The request can be deterministically hashed.

```text
hash(
  media_id +
  start +
  end +
  profile
)
```

First request:

```text
request
   │
   ▼
FFmpeg
   │
   ├──► first downloader
   │
   ▼
temporary R2 cache
```

Subsequent requests:

```text
temporary R2 cache
       │
       ├──► Jumper B
       ├──► Jumper C
       ├──► Jumper D
       └──► Jumper E
```

Suggested TTL:

**24 hours**

After expiration:

```text
R2 lifecycle rule
       │
       ▼
DELETE
```

This keeps permanent storage minimal while avoiding redundant clipping jobs.

---

# 20. GPMF Preservation in Downloaded Clips

FREEFALL should investigate preserving the original GoPro telemetry track when generating original-quality clips.

Desired result:

```text
FREEFALL_Freefall_1247.mp4

Video       ✓
Audio       ✓
GoPro GPMF  ✓
```

This would mean downloaded FREEFALL clips remain telemetry-bearing media.

Potential benefits:

- Re-import into FREEFALL
- Third-party telemetry analysis
- GoPro-compatible workflows
- Future processing
- No loss of original sensor information

The prototype must verify whether stream-copy clipping preserves valid GPMF timestamps and whether the resulting telemetry can still be parsed correctly.

---

# 21. Download Profiles

A download request should use a defined profile.

Potential profiles:

## ORIGINAL

```text
Resolution: source
Codec: source
Video: stream copy
Audio: stream copy
Telemetry: preserve where possible
```

## 1080P

Source:

Cloudflare Stream or generated derivative.

Optimized for:

- Sharing
- Mobile use
- Smaller download

## OVERLAY

Rendered video containing selected FREEFALL telemetry.

Potential options:

- 1080p
- 4K Pro

Requires transcoding/rendering.

---

# 22. Video Export

Interactive overlays remain preferable inside FREEFALL.

Users may additionally generate conventional videos containing burned-in telemetry.

```text
video
  +
telemetry
  +
theme
  │
  ▼
render worker
  │
  ▼
MP4
```

Formats:

- 16:9
- 9:16
- 1:1

Themes:

- Minimal
- Technical
- Cinematic
- Map
- Custom

---

# 23. Infrastructure

```text
                       FREEFALL
                           │
            ┌──────────────┴──────────────┐
            │                             │
           API                        PostgreSQL
            │
     ┌──────┼───────────┐
     │      │           │
     ▼      ▼           ▼
    R2    Stream      Workers
 master   viewing      │
 assets                ├── GPMF
 telemetry             ├── analysis
 cache                 ├── clipping
                       └── exports
```

---

# 24. Backend Domain Model

```text
User
 ├── Profile
 ├── Equipment
 └── Activities

Activity
 └── Jump
      ├── Participants
      ├── Media
      ├── TelemetrySources
      ├── Events
      ├── Analysis
      ├── Equipment
      ├── Location
      ├── Comments
      └── Reactions

Media
 ├── MasterAsset
 ├── StreamAsset
 └── TemporaryDerivatives
```

---

# 25. Download Authorization

Conceptual policy:

```text
canDownload(user, media):

    if user == media.owner:
        ALLOW

    if user is confirmed participant
       AND media.participantDownloads:
        ALLOW

    if jump.visibility == PUBLIC
       AND media.publicDownloads:
        ALLOW

    DENY
```

After authorization:

```text
API
 │
 ▼
clip request
 │
 ├── cached? ──► signed R2 URL
 │
 └── uncached
       │
       ▼
    clip worker
       │
       ▼
    download
```

---

# 26. Infrastructure Economics

Permanent storage should primarily consist of:

```text
Master media
Telemetry
Application assets
```

It should **not** scale according to the number of logical video sections.

Therefore:

```text
6 GB master
```

should remain approximately:

```text
6 GB permanent storage
```

rather than:

```text
6 GB master
+ plane
+ freefall
+ canopy
+ after landing
+ custom clips
```

Temporary derivatives should expire automatically.

---

# 27. Free vs Pro Direction

Potential model:

## Free

- Interactive Jump
- 1080p Stream playback
- Telemetry
- Social sharing
- Limited master retention
- 1080p downloads
- Participant sharing

## Pro

- Long-term original retention
- Original 4K/5.3K clipping
- Original participant downloads
- Advanced telemetry
- 4K exports
- Overlay exports
- Increased storage

Exact monetization remains TBD.

---

# 28. MVP

The first usable product should:

> **Turn a GoPro skydive into a beautiful interactive activity.**

Required:

1. Authentication
2. GoPro import
3. GPMF extraction
4. Telemetry normalization
5. Master upload
6. Stream upload
7. Interactive video player
8. Altitude overlay
9. Speed overlay
10. Graphs
11. Exit/deployment/landing events
12. Jump activity
13. Sharing
14. Participant tagging
15. Download authorization
16. Original-quality freefall clipping

Not initially required:

- Full electronic logbook
- Signatures
- Manifest integration
- Leaderboards
- Challenges
- Clubs
- Multi-camera synchronization
- Non-GoPro sensors
- AI editing

---

# 29. Prototype Engineering Plan

## P0 — Local Telemetry

Take one real GoPro skydive MP4.

Deliver:

- Extract GPMF
- Normalize telemetry
- Play video
- Synchronize altitude
- Synchronize speed

## P1 — Cloud Playback

Add:

- Cloudflare Stream
- HLS playback
- Same synchronized telemetry

## P2 — Jump Analysis

Add:

- Exit detection
- Deployment detection
- Landing detection
- Graphs
- Headline metrics

## P3 — Original-Quality Clipping

Take a real approximately 6 GB GoPro file.

Serve it through a range-capable HTTP endpoint representing R2.

Test:

### Experiment 1 — Range Efficiency

Extract approximately 60–90 seconds from the middle of the video.

Measure:

- Bytes requested
- Number of HTTP range requests
- Processing time
- Memory
- CPU
- Percentage of master transferred

Goal:

Verify that FFmpeg does not need to read an unreasonable proportion of the complete master.

### Experiment 2 — Stream Copy Integrity

Generate:

```text
EXIT -5s
→
DEPLOYMENT +10s
```

using stream copy.

Verify:

- Resolution unchanged
- Codec unchanged
- Bitrate effectively unchanged
- No re-encoding
- Audio synchronization
- Playback compatibility

### Experiment 3 — GPMF Preservation

Include GoPro metadata tracks.

Verify:

- GPMF remains present
- Telemetry parser recognizes output
- GPS timestamps remain correct
- Sensor data aligns with trimmed video time

### Experiment 4 — Output Strategy

Compare:

**A. Conventional MP4 via ephemeral disk**

against:

**B. Fragmented MP4 streamed directly**

Test with:

- iPhone
- Android
- Safari
- Chrome
- QuickTime
- VLC
- Common video editors
- Instagram upload
- TikTok upload
- WhatsApp sharing

Decision:

Choose direct streaming only if compatibility is sufficiently broad.

Otherwise use ephemeral disk.

---

# 30. Expected Production Clipping Architecture

Unless P3 testing strongly favors direct fragmented MP4 streaming, the preferred architecture is:

```text
User requests:
"Freefall — Original"

        │
        ▼

FREEFALL authorization

        │
        ▼

Check temporary cache

     ┌──┴──┐
    HIT   MISS
     │      │
     │      ▼
     │    Worker
     │      │
     │   R2 range reads
     │      │
     │    FFmpeg
     │      │
     │   /tmp clip
     │      │
     │   upload temporary
     │      │
     └──────┤
            ▼
       signed R2 URL
            │
            ▼
          USER

            │
         24 hours
            │
            ▼
          DELETE
```

This provides:

- Original camera quality
- No permanent derivative duplication
- High compatibility
- Efficient repeated downloads
- Predictable storage
- Low processing overhead

---

# 31. First Engineering Milestone

The first serious technical milestone remains deliberately small.

Take one real GPS-enabled GoPro skydive MP4 and demonstrate:

```text
┌────────────────────────────────┐
│                                │
│          YOUR JUMP             │
│                                │
│  12,410 ft       ↓ 191 km/h    │
│                                │
└────────────────────────────────┘

         ALTITUDE / SPEED
───────────────╲________________
```

Then demonstrate:

```text
DOWNLOAD
Freefall — Original 5.3K
Exit -5s → Deployment +10s
```

without permanently storing another copy of the footage.

If both experiences work well, the two most important technical foundations of FREEFALL are validated:

1. **Interactive telemetry-driven playback**
2. **Efficient collaborative access to original-quality jump footage**

Everything else can be built around those foundations.