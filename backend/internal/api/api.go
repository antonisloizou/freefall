package api

import (
	"encoding/json"
	"math"
	"net/http"
)

// Demo data is public and synthetic. Production data must use authenticated,
// owner-scoped storage before private activities are introduced.
type Event struct {
	Kind string  `json:"kind"`
	Time float64 `json:"time"`
}
type Jump struct {
	ID         string  `json:"id"`
	Title      string  `json:"title"`
	Location   string  `json:"location"`
	RecordedAt string  `json:"recordedAt"`
	Visibility string  `json:"visibility"`
	Demo       bool    `json:"demo"`
	VideoURL   *string `json:"videoURL"`
	Duration   float64 `json:"duration"`
	Events     []Event `json:"events"`
}
type Sample struct {
	Time          float64 `json:"time"`
	Altitude      float64 `json:"altitude"`
	VerticalSpeed float64 `json:"verticalSpeed"`
	Speed3D       float64 `json:"speed3D"`
}
type Telemetry struct {
	JumpID            string   `json:"jumpID"`
	TimeOffset        float64  `json:"timeOffset"`
	AltitudeReference string   `json:"altitudeReference"`
	Samples           []Sample `json:"samples"`
}

var demo = Jump{
	ID: "demo-jump", Title: "Relive your jump", Location: "Demo drop zone",
	RecordedAt: "2026-09-26T09:00:00Z", Visibility: "public", Demo: true,
	Duration: 240,
	Events:   []Event{{Kind: "exit", Time: 15}, {Kind: "deployment", Time: 75}, {Kind: "landing", Time: 225}},
}

func NewHandler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /v1/jumps", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, []Jump{demo})
	})
	mux.HandleFunc("GET /v1/jumps/{id}", func(w http.ResponseWriter, r *http.Request) {
		if r.PathValue("id") != demo.ID {
			http.NotFound(w, r)
			return
		}
		writeJSON(w, demo)
	})
	mux.HandleFunc("GET /v1/jumps/{id}/telemetry", func(w http.ResponseWriter, r *http.Request) {
		if r.PathValue("id") != demo.ID {
			http.NotFound(w, r)
			return
		}
		writeJSON(w, demoTelemetry())
	})
	return mux
}

func writeJSON(w http.ResponseWriter, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	_ = json.NewEncoder(w).Encode(value)
}

// SI units, seconds relative to video start, altitude above the demo DZ.
// Real GPS altitude will require an explicit datum and ground reference.
func demoTelemetry() Telemetry {
	samples := make([]Sample, 0, 241)
	for i := 0; i <= 240; i++ {
		t := float64(i)
		altitude, vertical, horizontal := 4000.0, 0.0, 30.0
		switch {
		case t >= 225:
			altitude, vertical, horizontal = 0, 0, 0
		case t >= 75:
			altitude, vertical, horizontal = 1000*(225-t)/150, -1000.0/150, 10
		case t >= 15:
			altitude, vertical, horizontal = 4000-50*(t-15), -50, 15
		}
		samples = append(samples, Sample{Time: t, Altitude: altitude, VerticalSpeed: vertical, Speed3D: math.Hypot(vertical, horizontal)})
	}
	return Telemetry{JumpID: demo.ID, TimeOffset: 0, AltitudeReference: "above_drop_zone", Samples: samples}
}
