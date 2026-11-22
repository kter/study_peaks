package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"unicode"

	"github.com/go-chi/chi/v5"
)

const maxSeatRequestBytes = 64 << 10

var (
	roomIdPattern      = regexp.MustCompile(`^[a-z0-9-]{1,64}$`)
	sessionIdPattern   = regexp.MustCompile(`^sess_[A-Za-z0-9-]{1,64}$`)
	countryCodePattern = regexp.MustCompile(`^[A-Z]{2}$`)
)

func requestRoomId(w http.ResponseWriter, r *http.Request) (string, bool) {
	roomId := chi.URLParam(r, "roomId")
	if !roomIdPattern.MatchString(roomId) {
		writeError(w, http.StatusNotFound, "ROOM_NOT_FOUND", "Room not found")
		return "", false
	}
	return roomId, true
}

func validateSessionId(w http.ResponseWriter, sessionId string) bool {
	if !sessionIdPattern.MatchString(sessionId) {
		writeError(w, http.StatusNotFound, "SESSION_NOT_FOUND", "Session not found")
		return false
	}
	return true
}

func readSeatRequest(w http.ResponseWriter, r *http.Request, req any) bool {
	// Read the entire body so trailing bytes also count toward the limit.
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxSeatRequestBytes))
	trimmed := bytes.TrimSpace(body)
	if err != nil || len(trimmed) == 0 || trimmed[0] != '{' || json.Unmarshal(body, req) != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return false
	}
	return true
}

func normalizeDisplayName(name, fallback string) string {
	name = strings.Map(func(r rune) rune {
		// Keep ZWNJ/ZWJ: scripts and emoji sequences need them.
		if r == '\u200c' || r == '\u200d' {
			return r
		}
		if unicode.IsControl(r) || unicode.Is(unicode.Cf, r) {
			return -1
		}
		return r
	}, name)
	name = strings.TrimSpace(name)
	count := 0
	for i := range name {
		if count == 30 {
			name = strings.TrimSpace(name[:i])
			break
		}
		count++
	}
	// A name made only of joiners is still invisible.
	if strings.Trim(name, "\u200c\u200d") == "" {
		return fallback
	}
	return name
}

func normalizeCountryCode(code, fallback string) string {
	code = strings.ToUpper(code)
	if !countryCodePattern.MatchString(code) {
		return fallback
	}
	return code
}

func normalizePhotoUrl(photoUrl string) string {
	if photoUrl == "" || len(photoUrl) > 2048 {
		return ""
	}
	parsed, err := url.Parse(photoUrl)
	if err != nil || parsed.Scheme != "https" {
		return ""
	}
	host := strings.ToLower(parsed.Hostname())
	if host == "googleusercontent.com" || strings.HasSuffix(host, ".googleusercontent.com") {
		return photoUrl
	}
	return ""
}

func normalizeIconSeed(seed string) string {
	seed = strings.TrimSpace(seed)
	if len(seed) > 128 {
		return ""
	}
	return seed
}

func normalizeDuration(duration int) int {
	return max(0, duration)
}
