package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
)

func TestRoomIdPattern(t *testing.T) {
	cases := []struct {
		id   string
		want bool
	}{
		{"everest", true},
		{"fuji", true},
		{"kilimanjaro", true},
		{"denali", true},
		{"unknown-room-2", true},
		{"a", true},
		{strings.Repeat("a", 64), true},
		{"", false},
		{"__x__", false},
		{"Fuji", false},
		{"富士", false},
		{"fuji/seats", false},
		{strings.Repeat("a", 65), false},
	}
	for _, c := range cases {
		if got := roomIdPattern.MatchString(c.id); got != c.want {
			t.Errorf("roomIdPattern.MatchString(%q) = %t, want %t", c.id, got, c.want)
		}
	}
}

func TestSessionIdPattern(t *testing.T) {
	cases := []struct {
		id   string
		want bool
	}{
		{"sess_123e4567-e89b-12d3-a456-426614174000", true},
		{"sess_A", true},
		{"sess_" + strings.Repeat("A0-", 21) + "B", true},
		{"", false},
		{"sess_", false},
		{"SESS_123", false},
		{"123", false},
		{"sess_a_b", false},
		{"sess_a\n", false},
		{"sess_" + strings.Repeat("a", 65), false},
	}
	for _, c := range cases {
		if got := sessionIdPattern.MatchString(c.id); got != c.want {
			t.Errorf("sessionIdPattern.MatchString(%q) = %t, want %t", c.id, got, c.want)
		}
	}
}

func TestNormalizeDisplayName(t *testing.T) {
	cases := []struct {
		name, input, fallback, want string
	}{
		{"anonymous", "Anonymous", "User", "Anonymous"},
		{"Japanese", "高橋", "", "高橋"},
		{"control and format characters", "\u3000 A\x00\t\u0085\u200b\u200f\u202a\u202e\u2066\u2069\ufeff B \u3000", "", "A B"},
		{"sit fallback", " \x00\u202e ", "User", "User"},
		{"sync empty", " \x00\u202e ", "", ""},
		{"rune limit", strings.Repeat("高🙂", 15) + "橋", "", strings.Repeat("高🙂", 15)},
		{"remove and trim before truncating", " \u202e" + strings.Repeat("橋", 30) + "高 ", "", strings.Repeat("橋", 30)},
		{"joiner only", "\u200d\u200c", "User", "User"},
		{"keep emoji joiners", "👨\u200d👩\u200d👧", "", "👨\u200d👩\u200d👧"},
		{"trim after truncating", strings.Repeat("a", 29) + "  bbb", "", strings.Repeat("a", 29)},
		{"legacy long name", strings.Repeat("a", 5000), "User", strings.Repeat("a", 30)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := normalizeDisplayName(c.input, c.fallback); got != c.want {
				t.Errorf("normalizeDisplayName() = %q, want %q", got, c.want)
			}
		})
	}
}

func TestNormalizeCountryCode(t *testing.T) {
	cases := []struct {
		input, fallback, want string
	}{
		{"JP", "JP", "JP"},
		{"uS", "", "US"},
		{"<script>ZZZ", "JP", "JP"},
		{"<script>ZZZ", "", ""},
		{"", "JP", "JP"},
		{"A1", "", ""},
		{" JP ", "", ""},
		{"日本", "", ""},
	}
	for _, c := range cases {
		if got := normalizeCountryCode(c.input, c.fallback); got != c.want {
			t.Errorf("normalizeCountryCode(%q, %q) = %q, want %q", c.input, c.fallback, got, c.want)
		}
	}
}

func TestNormalizePhotoUrl(t *testing.T) {
	const baseUrl = "https://googleusercontent.com/"
	maxUrl := baseUrl + strings.Repeat("x", 2048-len(baseUrl))
	cases := []struct {
		name, input string
		wantValid   bool
	}{
		{"empty clears photo", "", true},
		{"Google profile photo", "https://lh3.googleusercontent.com/a/xyz=s96-c", true},
		{"root domain", baseUrl, true},
		{"case-insensitive domain", "https://LH3.GOOGLEUSERCONTENT.COM/a", true},
		{"maximum length", maxUrl, true},
		{"over maximum length", maxUrl + "x", false},
		{"invalid URL", baseUrl + "%zz", false},
		{"HTTP", "http://googleusercontent.com/a", false},
		{"no scheme", "//googleusercontent.com/a", false},
		{"no host", "https:googleusercontent.com/a", false},
		{"arbitrary host", "https://attacker.example/a", false},
		{"suffix without dot", "https://fakegoogleusercontent.com/a", false},
		{"domain in subdomain", "https://googleusercontent.com.attacker.example/a", false},
		{"domain in user info", "https://googleusercontent.com@attacker.example/a", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			want := ""
			if c.wantValid {
				want = c.input
			}
			if got := normalizePhotoUrl(c.input); got != want {
				t.Errorf("normalizePhotoUrl() = %q, want %q", got, want)
			}
		})
	}
}

func TestNormalizeIconSeed(t *testing.T) {
	const seed = "123e4567-e89b-12d3-a456-426614174000"
	maxSeed := strings.Repeat("é", 64)
	cases := []struct {
		input, want string
	}{
		{seed, seed},
		{" \t" + seed + "\u3000", seed},
		{" \t", ""},
		{" " + maxSeed + " ", maxSeed},
		{maxSeed + "x", ""},
	}
	for _, c := range cases {
		if got := normalizeIconSeed(c.input); got != c.want {
			t.Errorf("normalizeIconSeed(%q) = %q, want %q", c.input, got, c.want)
		}
	}
}

func TestNormalizeDuration(t *testing.T) {
	cases := []struct {
		input, want int
	}{
		{-1, 0},
		{0, 0},
		{120, 120},
	}
	for _, c := range cases {
		if got := normalizeDuration(c.input); got != c.want {
			t.Errorf("normalizeDuration(%d) = %d, want %d", c.input, got, c.want)
		}
	}
}

func TestSeatHandlersRejectInvalidRequests(t *testing.T) {
	const (
		roomNotFound    = `{"error":{"code":"ROOM_NOT_FOUND","message":"Room not found"}}`
		sessionNotFound = `{"error":{"code":"SESSION_NOT_FOUND","message":"Session not found"}}`
		invalidRequest  = `{"error":{"code":"INVALID_REQUEST","message":"Invalid request body"}}`
		validBody       = `{"seatNumber":1,"sessionId":"sess_A-1"}`
		bodyLimit       = 64 << 10
	)
	r := chi.NewRouter()
	r.Get("/v1/rooms/{roomId}/seats", getSeatsHandler)
	r.Post("/v1/rooms/{roomId}/sit", sitHandler)
	r.Post("/v1/rooms/{roomId}/sync", syncHandler)
	r.Post("/v1/rooms/{roomId}/leave", leaveHandler)
	r.Get("/v1/rooms/{roomId}/sessions/{sessionId}", getSessionHandler)

	// Omit requireInit and recovery so an unexpected Firestore call fails the test.
	check := func(t *testing.T, method, path, body string, status int, response string) {
		t.Helper()
		res := httptest.NewRecorder()
		r.ServeHTTP(res, httptest.NewRequest(method, path, strings.NewReader(body)))
		if res.Code != status || res.Body.String() != response+"\n" {
			t.Errorf("got %d %s, want %d %s", res.Code, res.Body, status, response)
		}
	}

	for _, route := range []struct{ method, suffix string }{
		{http.MethodGet, "/seats"},
		{http.MethodPost, "/sit"},
		{http.MethodPost, "/sync"},
		{http.MethodPost, "/leave"},
		{http.MethodGet, "/sessions/sess_A-1"},
	} {
		t.Run("invalid room"+route.suffix, func(t *testing.T) {
			for _, roomId := range []string{"__x__", strings.Repeat("a", 2000)} {
				check(t, route.method, "/v1/rooms/"+roomId+route.suffix, validBody, http.StatusNotFound, roomNotFound)
			}
		})
	}

	longSession := "sess_" + strings.Repeat("a", 3000)
	t.Run("invalid session path", func(t *testing.T) {
		check(t, http.MethodGet, "/v1/rooms/fuji/sessions/"+longSession, "", http.StatusNotFound, sessionNotFound)
	})
	for _, endpoint := range []string{"sync", "leave"} {
		t.Run("invalid session/"+endpoint, func(t *testing.T) {
			path := "/v1/rooms/fuji/" + endpoint
			for _, id := range []string{"", "invalid", longSession} {
				check(t, http.MethodPost, path, `{"sessionId":"`+id+`"}`, http.StatusNotFound, sessionNotFound)
			}
			body := `{}` + strings.Repeat(" ", bodyLimit-len(`{}`))
			check(t, http.MethodPost, path, body, http.StatusNotFound, sessionNotFound)
		})
	}

	for _, endpoint := range []string{"sit", "sync", "leave"} {
		for _, c := range []struct{ name, body string }{
			{"oversized JSON", `{"displayName":"` + strings.Repeat("a", bodyLimit) + `"}`},
			{"oversized trailing whitespace", validBody + strings.Repeat(" ", bodyLimit-len(validBody)+1)},
			{"malformed JSON", `{"sessionId":`},
			{"trailing JSON", validBody + `{}`},
			{"null body", `null`},
		} {
			t.Run(endpoint+"/"+c.name, func(t *testing.T) {
				check(t, http.MethodPost, "/v1/rooms/fuji/"+endpoint, c.body, http.StatusBadRequest, invalidRequest)
			})
		}
	}
}
