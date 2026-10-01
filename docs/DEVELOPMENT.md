# Run FREEFALL

This first slice contains a native iPhone client and a container-ready, read-only
Go demo API. All jump data is synthetic. There is no GoPro import, attached video,
authentication, database, upload, or cloud deployment yet.

## Backend

```sh
cd backend
go run ./cmd/api
```

The default port is 8080; set `PORT` for your hosting environment.

Endpoints:

- `GET /healthz`
- `GET /v1/jumps`
- `GET /v1/jumps/demo-jump`
- `GET /v1/jumps/demo-jump/telemetry`

Telemetry uses seconds, metres, and metres per second. Its `timeOffset` specifies
`videoTime = sampleTime + timeOffset`. The altitude reference is explicit. Demo
altitude is above the drop zone; real GoPro GPS altitude needs separate datum and
ground elevation handling. The client refuses to interpolate across gaps longer
than two seconds or beyond the available data.

## iPhone

Requires full Xcode with the iOS SDK, supporting Swift 6 and iOS 17 or later.

1. Open `ios/Freefall.xcodeproj` in Xcode.
2. Select the Freefall target and an iPhone simulator.
3. Run the API on your Mac, then run the app.
4. Open the demo jump and scrub or tap Exit, Deployment, and Landing.

The app displays synthetic altitude/speed and an altitude chart. When a jump has
a video URL, AVPlayer supplies the replay clock for playback, pause, and seeking.
The demo has no video and uses manual scrubbing.

For a physical phone, set `API_BASE_URL` in `ios/Freefall/Config.xcconfig` to a
hosted HTTPS URL and select your Apple development team for signing. The default
localhost URL is for the simulator. Preserve the slash substitutions in xcconfig.
The plist permits local networking for development; it does not permit arbitrary
insecure HTTP hosts. No GoPro/Bluetooth/Photos permission is requested yet.

## Checks

```sh
cd backend
go test ./...
go vet ./...
```

```sh
cd ios/FreefallCore
swift run FreefallCoreChecks
```

The executable checks use preconditions in a debug build and can run on macOS
without the iOS SDK or XCTest/Swift Testing. That does not verify
the SwiftUI app: build and run the iPhone target in Xcode separately.

## Hosting

Build from the backend directory:

```sh
docker build -t freefall-api .
docker run --rm -p 8080:8080 -e PORT=8080 freefall-api
```

Deploy this image on a container host, configure `PORT`, terminate TLS at the
host/load balancer, and use `/healthz` for health checks. The image runs as a
non-root user. No cloud resources are provisioned by this repository.

A hosting account/environment and HTTPS endpoint are still needed for an actual
deployment. Do not submit this demo as a complete product.
