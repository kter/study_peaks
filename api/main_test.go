package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/idtoken"
)

func TestSeatId(t *testing.T) {
	cases := []struct {
		number int
		want   string
	}{
		{1, "seat-01"},
		{9, "seat-09"},
		{10, "seat-10"},
		{99, "seat-99"},
		{100, "seat-100"},
	}

	for _, c := range cases {
		if got := seatId(c.number); got != c.want {
			t.Errorf("seatId(%d) = %q, want %q", c.number, got, c.want)
		}
	}
}

func TestValidSeatNumber(t *testing.T) {
	cases := []struct {
		number   int
		capacity int
		want     bool
	}{
		{-1, 100, false},
		{0, 100, false},
		{1, 100, true},
		{100, 100, true},
		{101, 100, false},
		{1, 0, false},
	}

	for _, c := range cases {
		if got := validSeatNumber(c.number, c.capacity); got != c.want {
			t.Errorf("validSeatNumber(%d, %d) = %t, want %t", c.number, c.capacity, got, c.want)
		}
	}
}

func TestCanMoveSeat(t *testing.T) {
	cases := []struct {
		userId string
		want   bool
	}{
		{"uid-1", true},
		{"anon_guest", false},
		{"", false},
	}

	for _, c := range cases {
		if got := canMoveSeat(c.userId); got != c.want {
			t.Errorf("canMoveSeat(%q) = %t, want %t", c.userId, got, c.want)
		}
	}
}

func TestCanTakeSeat(t *testing.T) {
	cases := []struct {
		name     string
		occupied bool
		ownerId  string
		callerId string
		want     bool
	}{
		{"guest takes empty seat", false, "", "anon_guest", true},
		{"signed-in user takes empty seat", false, "", "uid-1", true},
		{"signed-in user retakes own seat", true, "uid-1", "uid-1", true},
		{"signed-in user cannot take another user's seat", true, "uid-2", "uid-1", false},
		{"signed-in user cannot take a guest's seat", true, "anon_guest", "uid-1", false},
		{"guest cannot retake an occupied seat", true, "anon_guest", "anon_guest", false},
		{"missing user IDs do not grant access", true, "", "", false},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := canTakeSeat(c.occupied, c.ownerId, c.callerId); got != c.want {
				t.Errorf("canTakeSeat(%t, %q, %q) = %t, want %t", c.occupied, c.ownerId, c.callerId, got, c.want)
			}
		})
	}
}

func TestCanModifySession(t *testing.T) {
	cases := []struct {
		name     string
		ownerId  string
		callerId string
		want     bool
	}{
		{"guest session, guest caller", "anon_guest", "", true},
		{"guest session, signed-in caller", "anon_guest", "uid-1", true},
		{"matching authenticated user", "uid-1", "uid-1", true},
		{"different authenticated user", "uid-1", "uid-2", false},
		{"missing authentication", "uid-1", "", false},
		{"missing owner and authentication", "", "", false},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := canModifySession(c.ownerId, c.callerId); got != c.want {
				t.Errorf("canModifySession(%q, %q) = %t, want %t", c.ownerId, c.callerId, got, c.want)
			}
		})
	}
}

func TestOptionalAuthMiddleware(t *testing.T) {
	// The SDK parses malformed tokens locally. This setting avoids ADC discovery.
	t.Setenv("FIREBASE_AUTH_EMULATOR_HOST", "127.0.0.1:9099")
	ctx := context.Background()
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: "demo-study-peaks"})
	if err != nil {
		t.Fatal(err)
	}
	client, err := app.Auth(ctx)
	if err != nil {
		t.Fatal(err)
	}
	previousAuthClient := authClient
	authClient = client
	t.Cleanup(func() { authClient = previousAuthClient })

	handler := optionalAuthMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))

	guest := httptest.NewRecorder()
	handler.ServeHTTP(guest, httptest.NewRequest(http.MethodPost, "/", nil))
	if guest.Code != http.StatusNoContent {
		t.Errorf("guest status = %d, want %d", guest.Code, http.StatusNoContent)
	}

	for _, header := range []string{"", "Bearer", "Bearer invalid-token"} {
		req := httptest.NewRequest(http.MethodPost, "/", nil)
		req.Header.Set("Authorization", header)
		res := httptest.NewRecorder()
		handler.ServeHTTP(res, req)
		if res.Code != http.StatusUnauthorized || !strings.Contains(res.Body.String(), `"code":"INVALID_TOKEN"`) {
			t.Errorf("Authorization %q: got %d %s, want 401 INVALID_TOKEN", header, res.Code, res.Body)
		}
	}
}

func TestCleanupAuthMiddleware(t *testing.T) {
	const audience = "https://study-peaks-api.example.com"
	const email = "scheduler@example.iam.gserviceaccount.com"

	cases := []struct {
		name     string
		audience string
		email    string
		header   string
	}{
		{"missing audience", "", email, "Bearer invalid-token"},
		{"missing invoker email", audience, "", "Bearer invalid-token"},
		{"missing authorization", audience, email, ""},
		{"invalid token", audience, email, "Bearer invalid-token"},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			t.Setenv("CLEANUP_AUDIENCE", c.audience)
			t.Setenv("CLEANUP_INVOKER_EMAIL", c.email)
			handler := cleanupAuthMiddleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				t.Error("unauthorized request reached the cleanup handler")
			}))
			req := httptest.NewRequest(http.MethodPost, "/internal/cleanup-sessions", nil)
			req.Header.Set("Authorization", c.header)
			res := httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if res.Code != http.StatusForbidden || !strings.Contains(res.Body.String(), `"code":"FORBIDDEN"`) {
				t.Errorf("got %d %s, want 403 FORBIDDEN", res.Code, res.Body)
			}
		})
	}
}

func TestIsCleanupInvoker(t *testing.T) {
	const email = "scheduler@example.iam.gserviceaccount.com"

	cases := []struct {
		name     string
		issuer   string
		email    string
		verified bool
		want     bool
	}{
		{"HTTPS Google issuer", "https://accounts.google.com", email, true, true},
		{"bare Google issuer", "accounts.google.com", email, true, true},
		{"unexpected issuer", "https://example.com", email, true, false},
		{"unexpected email", "https://accounts.google.com", "other@example.com", true, false},
		{"unverified email", "https://accounts.google.com", email, false, false},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			payload := &idtoken.Payload{
				Issuer: c.issuer,
				Claims: map[string]interface{}{
					"email":          c.email,
					"email_verified": c.verified,
				},
			}
			if got := isCleanupInvoker(payload, email); got != c.want {
				t.Errorf("isCleanupInvoker = %t, want %t", got, c.want)
			}
		})
	}
}

func TestGetTime(t *testing.T) {
	ts := time.Date(2026, 11, 16, 12, 0, 0, 0, time.UTC)

	cases := []struct {
		name string
		data map[string]interface{}
		want time.Time
	}{
		{"timestamp", map[string]interface{}{"k": ts}, ts},
		{"missing", map[string]interface{}{}, time.Time{}},
		{"null (seeded empty seat)", map[string]interface{}{"k": nil}, time.Time{}},
		{"wrong type", map[string]interface{}{"k": "2026-11-16"}, time.Time{}},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := getTime(c.data, "k"); !got.Equal(c.want) {
				t.Errorf("getTime() = %v, want %v", got, c.want)
			}
		})
	}
}
