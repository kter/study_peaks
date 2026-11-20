package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strconv"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

func TestRequireStudyHistoryOwner(t *testing.T) {
	router := chi.NewRouter()
	router.With(requireStudyHistoryOwner).Get("/users/{userId}/study-history",
		func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusNoContent)
		})
	for _, test := range []struct {
		uid  string
		want int
	}{
		{"", http.StatusUnauthorized},
		{"other", http.StatusForbidden},
		{"owner", http.StatusNoContent},
	} {
		request := httptest.NewRequest(http.MethodGet, "/users/owner/study-history", nil)
		request = request.WithContext(context.WithValue(request.Context(), userIdKey, test.uid))
		response := httptest.NewRecorder()
		router.ServeHTTP(response, request)
		if response.Code != test.want {
			t.Errorf("UID %q received %d, want %d", test.uid, response.Code, test.want)
		}
	}
}

func TestStudyHistoryFirestore(t *testing.T) {
	if os.Getenv("FIRESTORE_EMULATOR_HOST") == "" {
		t.Skip("requires the Firestore emulator")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	client, err := firestore.NewClient(ctx, "demo-study-peaks")
	if err != nil {
		t.Fatal(err)
	}
	previous := firestoreClient
	firestoreClient = client
	t.Cleanup(func() {
		firestoreClient = previous
		client.Close()
	})

	router := chi.NewRouter()
	router.With(requireStudyHistoryOwner).Get("/users/{userId}/study-history", getStudyHistoryHandler)
	router.With(requireStudyHistoryOwner).Post("/users/{userId}/study-history", saveStudyHistoryHandler)
	owner := uuid.NewString()
	other := uuid.NewString()
	request := func(method, caller, uid, cursor string, body []byte) *httptest.ResponseRecorder {
		t.Helper()
		path := fmt.Sprintf("/users/%s/study-history?cursor=%s", uid, url.QueryEscape(cursor))
		r := httptest.NewRequest(method, path, bytes.NewReader(body))
		r = r.WithContext(context.WithValue(ctx, userIdKey, caller))
		w := httptest.NewRecorder()
		router.ServeHTTP(w, r)
		return w
	}
	post := func(records []studyRecord) *httptest.ResponseRecorder {
		t.Helper()
		body, err := json.Marshal(map[string][]studyRecord{"records": records})
		if err != nil {
			t.Fatal(err)
		}
		return request(http.MethodPost, owner, owner, "", body)
	}
	upload := func(records []studyRecord) {
		t.Helper()
		w := post(records)
		if w.Code != http.StatusOK || w.Body.String() != "{\"rejectedSessionIds\":[]}\n" {
			t.Fatalf("upload: %d %s", w.Code, w.Body.String())
		}
	}
	get := func(uid, cursor string) studyHistoryPage {
		t.Helper()
		w := request(http.MethodGet, uid, uid, cursor, nil)
		if w.Code != http.StatusOK {
			t.Fatalf("get: %d %s", w.Code, w.Body.String())
		}
		var page studyHistoryPage
		if err := json.Unmarshal(w.Body.Bytes(), &page); err != nil {
			t.Fatal(err)
		}
		return page
	}

	start := time.Date(2026, 11, 20, 14, 59, 30, 123456000, time.UTC)
	initial := studyRecord{
		SessionID: "initial", RoomID: "fuji", StartTime: start.Format(time.RFC3339Nano),
		DurationSeconds: 60,
		FocusIntervals:  []focusInterval{{start, start.Add(time.Minute), 540}},
	}
	upload([]studyRecord{initial})
	replay := initial
	replay.DurationSeconds = 77
	replay.FocusIntervals = nil
	upload([]studyRecord{replay})

	// Two devices upload batches concurrently. Each includes the same
	// previously synced session, which must keep its original sequence.
	batches := make([][]studyRecord, 3)
	for i := 0; i <= studyPageSize; i++ {
		batch := i / (studyUploadLimit - 1)
		batches[batch] = append(batches[batch], studyRecord{
			SessionID: "record_" + strconv.Itoa(i),
			RoomID:    "fuji", StartTime: "2026-11-20T23:59:30.000", DurationSeconds: 30,
		})
	}
	responses := make(chan *httptest.ResponseRecorder, len(batches))
	for _, batch := range batches {
		go func(batch []studyRecord) { responses <- post(append(batch, replay)) }(batch)
	}
	for range batches {
		w := <-responses
		if w.Code != http.StatusOK {
			t.Errorf("concurrent upload: %d %s", w.Code, w.Body.String())
		}
	}
	if t.Failed() {
		t.FailNow()
	}

	first := get(owner, "")
	second := get(owner, first.NextCursor)
	if len(first.Records) != studyPageSize || !first.HasMore ||
		len(second.Records) != 2 || second.HasMore ||
		second.Records[0].FocusIntervals != nil {
		t.Fatalf("unexpected pages: %d, %+v", len(first.Records), second)
	}
	seen := make(map[string]bool)
	for _, record := range append(first.Records, second.Records...) {
		if seen[record.SessionID] {
			t.Fatalf("duplicate session: %s", record.SessionID)
		}
		seen[record.SessionID] = true
	}
	saved := first.Records[0]
	if saved.SessionID != initial.SessionID || saved.DurationSeconds != initial.DurationSeconds ||
		len(saved.FocusIntervals) != 1 || saved.FocusIntervals[0].Offset != 540 ||
		!saved.FocusIntervals[0].Start.Equal(start) {
		t.Fatalf("initial record changed after retry: %+v", saved)
	}

	later := initial
	later.SessionID = "later"
	upload([]studyRecord{later})
	incremental := get(owner, second.NextCursor)
	if len(incremental.Records) != 1 || incremental.Records[0].SessionID != later.SessionID {
		t.Fatalf("unexpected incremental page: %+v", incremental)
	}
	if page := get(other, ""); len(page.Records) != 0 {
		t.Fatalf("other account received records: %+v", page)
	}

	fixture, err := os.ReadFile("testdata/study_history_upload.json")
	if err != nil {
		t.Fatal(err)
	}
	w := request(http.MethodPost, other, other, "", fixture)
	if w.Code != http.StatusOK || w.Body.String() != "{\"rejectedSessionIds\":[]}\n" {
		t.Fatalf("shared fixture rejected: %d %s", w.Code, w.Body.String())
	}
	bad := json.RawMessage(`{"sessionId":"bad","roomId":"fuji","startTime":"2026-11-20T14:59:58.000Z","durationSeconds":1,"focusIntervals":[{"start":"invalid","end":"2026-11-20T15:00:00.000Z","offset":540}]}`)
	laterJSON, err := json.Marshal(later)
	if err != nil {
		t.Fatal(err)
	}
	mixed, err := json.Marshal(map[string][]json.RawMessage{"records": {bad, laterJSON}})
	if err != nil {
		t.Fatal(err)
	}
	w = request(http.MethodPost, other, other, "", mixed)
	if w.Code != http.StatusOK || w.Body.String() != "{\"rejectedSessionIds\":[\"bad\"]}\n" {
		t.Fatalf("mixed upload: %d %s", w.Code, w.Body.String())
	}
	otherPage := get(other, "")
	if len(otherPage.Records) != 2 || otherPage.Records[1].SessionID != "later" {
		t.Fatalf("valid records missing after mixed upload: %+v", otherPage)
	}
}
