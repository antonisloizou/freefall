package api

import (
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDemoContract(t *testing.T) {
	handler := NewHandler()
	request := func(path string, target any) {
		t.Helper()
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, path, nil))
		if response.Code != http.StatusOK {
			t.Fatalf("%s: status %d", path, response.Code)
		}
		if err := json.Unmarshal(response.Body.Bytes(), target); err != nil {
			t.Fatal(err)
		}
	}
	var jumps []Jump
	request("/v1/jumps", &jumps)
	if len(jumps) != 1 || !jumps[0].Demo || jumps[0].VideoURL != nil {
		t.Fatal("demo must be explicit and have no fake footage")
	}
	var telemetry Telemetry
	request("/v1/jumps/"+jumps[0].ID+"/telemetry", &telemetry)
	if telemetry.JumpID != jumps[0].ID || telemetry.AltitudeReference != "above_drop_zone" {
		t.Fatal("telemetry identity/datum mismatch")
	}
	for i, sample := range telemetry.Samples {
		if i > 0 && sample.Time <= telemetry.Samples[i-1].Time {
			t.Fatal("samples not increasing")
		}
		if sample.Altitude < 0 || math.IsNaN(sample.Speed3D) {
			t.Fatal("invalid sample")
		}
	}
	if telemetry.Samples[75].Altitude != 1000 || telemetry.Samples[225].Altitude != 0 {
		t.Fatal("event altitude mismatch")
	}
	var detail Jump
	request("/v1/jumps/demo-jump", &detail)
	if detail.ID != jumps[0].ID {
		t.Fatal("detail identity mismatch")
	}
}

func TestUnknownJumpAndUnsupportedMethod(t *testing.T) {
	for _, tc := range []struct {
		method, path string
		status       int
	}{
		{"GET", "/v1/jumps/missing", 404},
		{"GET", "/v1/jumps/missing/telemetry", 404},
		{"POST", "/v1/jumps", 405},
	} {
		response := httptest.NewRecorder()
		NewHandler().ServeHTTP(response, httptest.NewRequest(tc.method, tc.path, nil))
		if response.Code != tc.status {
			t.Errorf("%s %s: got %d", tc.method, tc.path, response.Code)
		}
	}
}
