package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/go-chi/chi/v5"
)

const (
	studyUploadLimit = 20
	studyPageSize    = 40
)

var studySessionID = regexp.MustCompile(`^[A-Za-z0-9_-]{1,128}$`)

type focusInterval struct {
	Start  time.Time `json:"start" firestore:"start"`
	End    time.Time `json:"end" firestore:"end"`
	Offset int       `json:"offset" firestore:"offset"`
}

type studyRecord struct {
	SessionID       string          `json:"sessionId" firestore:"sessionId"`
	RoomID          string          `json:"roomId" firestore:"roomId"`
	StartTime       string          `json:"startTime" firestore:"startTime"`
	DurationSeconds int64           `json:"durationSeconds" firestore:"durationSeconds"`
	FocusIntervals  []focusInterval `json:"focusIntervals" firestore:"focusIntervals"`
}

type storedStudyRecord struct {
	Record   studyRecord `firestore:"record"`
	Sequence int64       `firestore:"sequence"`
}

type studyHistoryPage struct {
	Records    []studyRecord `json:"records"`
	NextCursor string        `json:"nextCursor"`
	HasMore    bool          `json:"hasMore"`
}

func requireStudyHistoryOwner(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		uid := authenticatedUserId(ctx)
		if uid == "" {
			writeError(w, http.StatusUnauthorized, "SIGN_IN_REQUIRED", "Sign in to sync study history")
			return
		}
		if isAnonymousAuth(ctx) || uid != chi.URLParam(r, "userId") {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "Study history access denied")
			return
		}
		w.Header().Set("Cache-Control", "private, no-store")
		next.ServeHTTP(w, r)
	})
}

func studyHistoryAccount(uid string) *firestore.DocumentRef {
	owner := "u_" + base64.RawURLEncoding.EncodeToString([]byte(uid))
	return firestoreClient.Collection("studyHistoryAccounts").Doc(owner)
}

func (record studyRecord) valid() bool {
	if !studySessionID.MatchString(record.SessionID) ||
		len(record.RoomID) == 0 || len(record.RoomID) > 128 ||
		record.DurationSeconds < 0 || len(record.FocusIntervals) > 2000 {
		return false
	}
	// Older records can have a civil start time without a timezone.
	if _, err := time.Parse(time.RFC3339Nano, record.StartTime); err != nil {
		if _, err := time.Parse("2006-01-02T15:04:05", record.StartTime); err != nil {
			return false
		}
	}
	if record.FocusIntervals == nil {
		return true
	}

	var previousEnd time.Time
	var milliseconds int64
	for _, interval := range record.FocusIntervals {
		if interval.Start.IsZero() || interval.End.IsZero() ||
			interval.Start.Before(previousEnd) || interval.End.Before(interval.Start) ||
			interval.Offset < -24*60 || interval.Offset > 24*60 {
			return false
		}
		milliseconds += (interval.End.UnixMicro() - interval.Start.UnixMicro()) / 1000
		previousEnd = interval.End
	}
	return milliseconds/1000 == record.DurationSeconds
}

func saveStudyHistoryHandler(w http.ResponseWriter, r *http.Request) {
	var upload struct {
		Records []json.RawMessage `json:"records"`
	}
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 5<<20))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&upload); err != nil ||
		!errors.Is(decoder.Decode(new(json.RawMessage)), io.EOF) ||
		len(upload.Records) == 0 || len(upload.Records) > studyUploadLimit {
		writeError(w, http.StatusBadRequest, "INVALID_STUDY_RECORDS", "Invalid study records")
		return
	}
	seen := make(map[string]bool, len(upload.Records))
	accepted := make([]studyRecord, 0, len(upload.Records))
	rejected := make([]string, 0)
	for _, raw := range upload.Records {
		var identity struct {
			SessionID string `json:"sessionId"`
		}
		if err := json.Unmarshal(raw, &identity); err != nil || seen[identity.SessionID] {
			writeError(w, http.StatusBadRequest, "INVALID_STUDY_RECORDS", "Invalid study records")
			return
		}
		seen[identity.SessionID] = true
		var record studyRecord
		if err := json.Unmarshal(raw, &record); err != nil || !record.valid() {
			rejected = append(rejected, identity.SessionID)
			continue
		}
		accepted = append(accepted, record)
	}

	result := map[string][]string{"rejectedSessionIds": rejected}
	if len(accepted) == 0 {
		writeJSON(w, http.StatusOK, result)
		return
	}
	ctx := r.Context()
	account := studyHistoryAccount(authenticatedUserId(ctx))
	records := account.Collection("studyRecords")
	refs := []*firestore.DocumentRef{account}
	for _, record := range accepted {
		refs = append(refs, records.Doc("s_"+record.SessionID))
	}
	// Allocate sequences in the same transaction as the records. Concurrent
	// uploads cannot insert records behind a device's saved cursor.
	err := firestoreClient.RunTransaction(ctx, func(_ context.Context, tx *firestore.Transaction) error {
		docs, err := tx.GetAll(refs)
		if err != nil {
			return err
		}
		var sequence int64
		if docs[0].Exists() {
			var ok bool
			sequence, ok = docs[0].Data()["lastSequence"].(int64)
			if !ok {
				return errors.New("study history account is missing its sequence")
			}
		}
		previous := sequence
		for i, doc := range docs[1:] {
			if doc.Exists() {
				continue
			}
			sequence++
			if err := tx.Create(doc.Ref, storedStudyRecord{
				Record:   accepted[i],
				Sequence: sequence,
			}); err != nil {
				return err
			}
		}
		if sequence != previous {
			return tx.Set(account, map[string]int64{"lastSequence": sequence})
		}
		return nil
	})
	if err != nil {
		writeAPIError(w, "STUDY_HISTORY_SAVE_FAILED", err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func getStudyHistoryHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	account := studyHistoryAccount(authenticatedUserId(ctx))
	query := account.Collection("studyRecords").OrderBy("sequence", firestore.Asc)
	if cursor := r.URL.Query().Get("cursor"); cursor != "" {
		sequence, err := strconv.ParseInt(cursor, 10, 64)
		if err != nil || sequence < 1 {
			writeError(w, http.StatusBadRequest, "INVALID_HISTORY_CURSOR", "Invalid history cursor")
			return
		}
		query = query.StartAfter(sequence)
	}

	docs, err := query.Limit(studyPageSize + 1).Documents(ctx).GetAll()
	if err != nil {
		writeAPIError(w, "STUDY_HISTORY_LOAD_FAILED", err)
		return
	}
	page := studyHistoryPage{
		Records: make([]studyRecord, 0, min(len(docs), studyPageSize)),
		HasMore: len(docs) > studyPageSize,
	}
	for _, doc := range docs[:min(len(docs), studyPageSize)] {
		var stored storedStudyRecord
		if err := doc.DataTo(&stored); err != nil {
			writeAPIError(w, "STUDY_HISTORY_LOAD_FAILED", err)
			return
		}
		page.Records = append(page.Records, stored.Record)
		page.NextCursor = strconv.FormatInt(stored.Sequence, 10)
	}
	writeJSON(w, http.StatusOK, page)
}
