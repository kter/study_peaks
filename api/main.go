package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"cloud.google.com/go/firestore/apiv1/firestorepb"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"
	"google.golang.org/api/idtoken"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type ctxKey int

const userIdKey ctxKey = iota

const (
	anonymousPrefix = "anon_"
	sessionTTL      = 24 * time.Hour
)

var (
	firestoreClient *firestore.Client
	authClient      *auth.Client
	initMu          sync.RWMutex
	isInitialized   bool
)

func main() {
	// Setup router first so health check works immediately
	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(corsMiddleware)

	// Health check - must work before Firebase init
	r.Get("/health", healthHandler)

	// API routes
	r.Route("/v1", func(r chi.Router) {
		r.Use(requireInit)
		r.Get("/rooms", getRoomsHandler)
		r.Get("/rooms/{roomId}/seats", getSeatsHandler)

		// Seat operations with optional auth (support anonymous users)
		r.Group(func(r chi.Router) {
			r.Use(optionalAuthMiddleware)
			r.Post("/rooms/{roomId}/sit", sitHandler)
			r.Post("/rooms/{roomId}/sync", syncHandler)
			r.Post("/rooms/{roomId}/leave", leaveHandler)
			r.Get("/rooms/{roomId}/sessions/{sessionId}", getSessionHandler)
		})
	})

	r.With(cleanupAuthMiddleware, requireInit).Post("/internal/cleanup-sessions", cleanupHandler)

	// Initialize Firebase in background
	go initFirebase()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting server on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, r))
}

func initFirebase() {
	ctx := context.Background()

	app, err := firebase.NewApp(ctx, nil)
	if err != nil {
		log.Printf("Warning: Failed to initialize Firebase: %v", err)
		return
	}

	fc, err := app.Firestore(ctx)
	if err != nil {
		log.Printf("Warning: Failed to initialize Firestore: %v", err)
		return
	}

	ac, err := app.Auth(ctx)
	if err != nil {
		log.Printf("Warning: Failed to initialize Auth: %v", err)
		fc.Close()
		return
	}

	initializeRooms(ctx, fc)

	initMu.Lock()
	firestoreClient = fc
	authClient = ac
	isInitialized = true
	initMu.Unlock()

	log.Println("Firebase initialized successfully")
}

func requireInit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		initMu.RLock()
		ready := isInitialized
		initMu.RUnlock()

		if !ready {
			writeError(w, http.StatusServiceUnavailable, "INITIALIZING", "Service is starting up")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func initializeRooms(ctx context.Context, client *firestore.Client) {
	rooms := []map[string]interface{}{
		{"roomId": "everest", "name": "Mt. Everest", "capacity": 100},
		{"roomId": "fuji", "name": "Mt. Fuji", "capacity": 50},
		{"roomId": "kilimanjaro", "name": "Mt. Kilimanjaro", "capacity": 75},
		{"roomId": "denali", "name": "Denali", "capacity": 40},
	}

	for _, room := range rooms {
		roomId := getString(room, "roomId")
		_, err := client.Collection("rooms").Doc(roomId).Set(ctx, room, firestore.MergeAll)
		if err != nil {
			log.Printf("Failed to initialize room %s: %v", roomId, err)
		}
	}
}

func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func bearerToken(header string) string {
	parts := strings.Fields(header)
	if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
		return parts[1]
	}
	return ""
}

// optionalAuthMiddleware verifies Firebase tokens and allows guests without a header.
func optionalAuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		headers := r.Header.Values("Authorization")
		if len(headers) == 0 {
			next.ServeHTTP(w, r)
			return
		}
		token := bearerToken(headers[0])
		if len(headers) != 1 || token == "" {
			writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired token")
			return
		}

		decoded, err := authClient.VerifyIDToken(r.Context(), token)
		if err != nil {
			log.Printf("Firebase ID token verification failed: %v", err)
			writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired token")
			return
		}

		ctx := context.WithValue(r.Context(), userIdKey, decoded.UID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func cleanupAuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		audience := os.Getenv("CLEANUP_AUDIENCE")
		invokerEmail := os.Getenv("CLEANUP_INVOKER_EMAIL")
		if audience == "" || invokerEmail == "" {
			log.Print("Cleanup authentication is not configured")
			writeError(w, http.StatusForbidden, "FORBIDDEN", "Cleanup access denied")
			return
		}

		token := bearerToken(r.Header.Get("Authorization"))
		if token == "" {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "Cleanup access denied")
			return
		}
		payload, err := idtoken.Validate(r.Context(), token, audience)
		if err != nil {
			log.Printf("Cleanup ID token verification failed: %v", err)
			writeError(w, http.StatusForbidden, "FORBIDDEN", "Cleanup access denied")
			return
		}
		if !isCleanupInvoker(payload, invokerEmail) {
			writeError(w, http.StatusForbidden, "FORBIDDEN", "Cleanup access denied")
			return
		}

		next.ServeHTTP(w, r)
	})
}

func isCleanupInvoker(payload *idtoken.Payload, invokerEmail string) bool {
	return (payload.Issuer == "https://accounts.google.com" || payload.Issuer == "accounts.google.com") &&
		getString(payload.Claims, "email") == invokerEmail &&
		getBool(payload.Claims, "email_verified")
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func seatsRef(roomId string) *firestore.CollectionRef {
	return firestoreClient.Collection("rooms").Doc(roomId).Collection("seats")
}

func getRoom(ctx context.Context, roomId string) (*firestore.DocumentSnapshot, error) {
	doc, err := firestoreClient.Collection("rooms").Doc(roomId).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, &AppError{Code: "ROOM_NOT_FOUND", Message: "Room not found", Status: http.StatusNotFound}
	}
	return doc, err
}

func findSeatBySession(ctx context.Context, roomId, sessionId string) (*firestore.DocumentSnapshot, error) {
	iter := seatsRef(roomId).Where("sessionId", "==", sessionId).Limit(1).Documents(ctx)
	defer iter.Stop()
	doc, err := iter.Next()
	if err == iterator.Done {
		return nil, &AppError{Code: "SESSION_NOT_FOUND", Message: "Session not found", Status: http.StatusNotFound}
	}
	return doc, err
}

func getRoomsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	docs, err := firestoreClient.Collection("rooms").Documents(ctx).GetAll()
	if err != nil {
		writeAPIError(w, "FIRESTORE_ERROR", err)
		return
	}

	type RoomResponse struct {
		RoomId           string `json:"roomId"`
		Name             string `json:"name"`
		Capacity         int    `json:"capacity"`
		CurrentOccupancy int    `json:"currentOccupancy"`
	}

	rooms := []RoomResponse{}
	for _, doc := range docs {
		data := doc.Data()
		seatsQuery := seatsRef(doc.Ref.ID).Where("isOccupied", "==", true)
		result, err := seatsQuery.NewAggregationQuery().WithCount("occupied").Get(ctx)
		occupancy := 0
		if err != nil {
			log.Printf("Failed to count occupied seats in room %s: %v", doc.Ref.ID, err)
		} else if count, ok := result["occupied"].(*firestorepb.Value); ok {
			occupancy = int(count.GetIntegerValue())
		} else {
			log.Printf("Missing occupancy count for room %s", doc.Ref.ID)
		}

		rooms = append(rooms, RoomResponse{
			RoomId:           doc.Ref.ID,
			Name:             getString(data, "name"),
			Capacity:         getInt(data, "capacity"),
			CurrentOccupancy: occupancy,
		})
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"rooms": rooms})
}

func getSeatsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	roomId := chi.URLParam(r, "roomId")

	// Get room capacity
	roomDoc, err := getRoom(ctx, roomId)
	if err != nil {
		writeAPIError(w, "FIRESTORE_ERROR", err)
		return
	}
	capacity := getInt(roomDoc.Data(), "capacity")

	// Get occupied seats from Firestore
	docs, err := seatsRef(roomId).Documents(ctx).GetAll()
	if err != nil {
		writeAPIError(w, "FIRESTORE_ERROR", err)
		return
	}

	type UserInfo struct {
		UserId                 string `json:"userId"`
		DisplayName            string `json:"displayName"`
		CountryCode            string `json:"countryCode"`
		StatusMessage          string `json:"statusMessage"`
		IconSeed               string `json:"iconSeed,omitempty"`
		PhotoUrl               string `json:"photoUrl,omitempty"`
		CurrentSessionDuration int    `json:"currentSessionDuration"`
	}

	type SeatResponse struct {
		SeatId           string    `json:"seatId"`
		SeatNumber       int       `json:"seatNumber"`
		IsOccupied       bool      `json:"isOccupied"`
		User             *UserInfo `json:"user"`
		SessionStartedAt time.Time `json:"sessionStartedAt"`
	}

	// Build map of occupied seats
	occupiedSeats := make(map[int]SeatResponse)
	for _, doc := range docs {
		data := doc.Data()
		seatNum := getInt(data, "seatNumber")
		seat := SeatResponse{
			SeatId:     doc.Ref.ID,
			SeatNumber: seatNum,
			IsOccupied: getBool(data, "isOccupied"),
		}

		seat.SessionStartedAt = getTime(data, "sessionStartedAt")

		if seat.IsOccupied {
			seat.User = &UserInfo{
				UserId:                 getString(data, "userId"),
				DisplayName:            getString(data, "displayName"),
				CountryCode:            getString(data, "countryCode"),
				StatusMessage:          getString(data, "statusMessage"),
				IconSeed:               getString(data, "iconSeed"),
				PhotoUrl:               getString(data, "photoUrl"),
				CurrentSessionDuration: getInt(data, "currentSessionDuration"),
			}
		}

		occupiedSeats[seatNum] = seat
	}

	// Generate all seats (1 to capacity)
	seats := make([]SeatResponse, 0, max(0, capacity))
	for i := 1; i <= capacity; i++ {
		if occupied, exists := occupiedSeats[i]; exists {
			seats = append(seats, occupied)
		} else {
			// Empty seat
			seats = append(seats, SeatResponse{
				SeatId:     seatId(i),
				SeatNumber: i,
				IsOccupied: false,
				User:       nil,
			})
		}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"seats": seats})
}

func sitHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	roomId := chi.URLParam(r, "roomId")

	var req struct {
		SeatNumber  int    `json:"seatNumber"`
		DisplayName string `json:"displayName"`
		CountryCode string `json:"countryCode"`
		UserId      string `json:"userId"` // Accepted for client compatibility.
		IconSeed    string `json:"iconSeed"`
		PhotoUrl    string `json:"photoUrl"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	roomDoc, err := getRoom(ctx, roomId)
	if err != nil {
		writeAPIError(w, "FIRESTORE_ERROR", err)
		return
	}
	if !validSeatNumber(req.SeatNumber, getInt(roomDoc.Data(), "capacity")) {
		writeError(w, http.StatusBadRequest, "INVALID_SEAT", "Seat number is outside the room capacity")
		return
	}

	// Validate displayName is required for anonymous users
	if req.DisplayName == "" {
		req.DisplayName = "User"
	}

	// Set default country code
	if req.CountryCode == "" {
		req.CountryCode = "JP"
	}

	userId := authenticatedUserId(ctx)
	if userId == "" {
		userId = anonymousPrefix + uuid.New().String()
	}

	seatRef := seatsRef(roomId).Doc(seatId(req.SeatNumber))
	var sessionId string
	var startedAt time.Time

	err = firestoreClient.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(seatRef)
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		if err == nil && getBool(doc.Data(), "isOccupied") {
			return &AppError{Code: "SEAT_OCCUPIED", Message: "Seat is already occupied", Status: http.StatusConflict}
		}

		sessionId = "sess_" + uuid.New().String()
		startedAt = time.Now().UTC().Truncate(time.Microsecond)

		updateMap := map[string]interface{}{
			"seatNumber":             req.SeatNumber,
			"isOccupied":             true,
			"userId":                 userId,
			"sessionId":              sessionId,
			"sessionStartedAt":       startedAt,
			"lastSyncAt":             startedAt,
			"currentSessionDuration": 0,
			"displayName":            req.DisplayName,
			"countryCode":            req.CountryCode,
			"statusMessage":          "",
		}

		// Only save if provided
		if req.IconSeed != "" {
			updateMap["iconSeed"] = req.IconSeed
		}
		if req.PhotoUrl != "" {
			updateMap["photoUrl"] = req.PhotoUrl
		}

		return tx.Set(seatRef, updateMap)
	})

	if err != nil {
		writeAPIError(w, "TRANSACTION_ERROR", err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"sessionId":        sessionId,
		"seatNumber":       req.SeatNumber,
		"sessionStartedAt": startedAt,
		"userId":           userId,
	})
}

func validSeatNumber(seatNumber, capacity int) bool {
	return seatNumber >= 1 && seatNumber <= capacity
}

func authenticatedUserId(ctx context.Context) string {
	userId, _ := ctx.Value(userIdKey).(string)
	return userId
}

func canModifySession(ownerId, callerId string) bool {
	return strings.HasPrefix(ownerId, anonymousPrefix) || (callerId != "" && callerId == ownerId)
}

func mutateSession(ctx context.Context, roomId, sessionId string, mutate func(*firestore.DocumentRef, firestore.Precondition) error) error {
	const maxAttempts = 3
	userId := authenticatedUserId(ctx)
	var err error
	for attempt := 0; attempt < maxAttempts; attempt++ {
		doc, lookupErr := findSeatBySession(ctx, roomId, sessionId)
		if lookupErr != nil {
			return lookupErr
		}
		if !canModifySession(getString(doc.Data(), "userId"), userId) {
			return &AppError{Code: "FORBIDDEN", Message: "Session belongs to another user", Status: http.StatusForbidden}
		}

		err = mutate(doc.Ref, firestore.LastUpdateTime(doc.UpdateTime))
		code := status.Code(err)
		if code != codes.FailedPrecondition && code != codes.NotFound {
			return err
		}
		// Recheck the session and its owner if a write raced with this request.
	}
	return err
}

func syncHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	roomId := chi.URLParam(r, "roomId")

	var req struct {
		SessionId       string `json:"sessionId"`
		CurrentDuration int    `json:"currentDuration"`
		DisplayName     string `json:"displayName"`
		CountryCode     string `json:"countryCode"`
		IconSeed        string `json:"iconSeed"`
		PhotoUrl        string `json:"photoUrl"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	var syncedAt time.Time
	updates := []firestore.Update{
		{Path: "currentSessionDuration", Value: req.CurrentDuration},
	}

	// Update profile fields if provided
	if req.DisplayName != "" {
		updates = append(updates, firestore.Update{Path: "displayName", Value: req.DisplayName})
	}
	if req.CountryCode != "" {
		updates = append(updates, firestore.Update{Path: "countryCode", Value: req.CountryCode})
	}
	if req.IconSeed != "" {
		updates = append(updates, firestore.Update{Path: "iconSeed", Value: req.IconSeed})
	}
	// PhotoUrl can be empty string (user switched from Google to Jdenticon)
	// So we always update it if it's present in the request
	updates = append(updates, firestore.Update{Path: "photoUrl", Value: req.PhotoUrl})

	err := mutateSession(ctx, roomId, req.SessionId, func(ref *firestore.DocumentRef, precondition firestore.Precondition) error {
		syncedAt = time.Now().UTC()
		_, err := ref.Update(ctx, append(updates, firestore.Update{Path: "lastSyncAt", Value: syncedAt}), precondition)
		return err
	})
	if err != nil {
		writeAPIError(w, "UPDATE_ERROR", err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"syncedAt": syncedAt})
}

func getSessionHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	roomId := chi.URLParam(r, "roomId")
	sessionId := chi.URLParam(r, "sessionId")

	// Get room info for room name
	roomDoc, err := getRoom(ctx, roomId)
	if err != nil {
		writeAPIError(w, "FIRESTORE_ERROR", err)
		return
	}
	roomData := roomDoc.Data()
	roomName := getString(roomData, "name")

	doc, err := findSeatBySession(ctx, roomId, sessionId)
	if err != nil {
		writeAPIError(w, "FIRESTORE_ERROR", err)
		return
	}

	data := doc.Data()
	sessionStartedAt := getTime(data, "sessionStartedAt")
	lastSyncAt := getTime(data, "lastSyncAt")
	if !lastSyncAt.IsZero() && time.Since(lastSyncAt) > sessionTTL {
		writeError(w, http.StatusNotFound, "SESSION_EXPIRED", "Session has expired due to inactivity")
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"sessionId":        sessionId,
		"roomId":           roomId,
		"roomName":         roomName,
		"seatNumber":       getInt(data, "seatNumber"),
		"sessionStartedAt": sessionStartedAt,
		"lastSyncAt":       lastSyncAt,
		"currentDuration":  getInt(data, "currentSessionDuration"),
	})
}

func leaveHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	roomId := chi.URLParam(r, "roomId")

	var req struct {
		SessionId     string `json:"sessionId"`
		FinalDuration int    `json:"finalDuration"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
		return
	}

	err := mutateSession(ctx, roomId, req.SessionId, func(ref *firestore.DocumentRef, precondition firestore.Precondition) error {
		_, err := ref.Delete(ctx, precondition)
		return err
	})
	if err != nil {
		writeAPIError(w, "DELETE_ERROR", err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"totalSessionDuration": req.FinalDuration,
		"endedAt":              time.Now().UTC(),
	})
}

func cleanupHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	cutoff := time.Now().UTC().Add(-sessionTTL)
	cleaned := 0

	rooms, err := firestoreClient.Collection("rooms").Documents(ctx).GetAll()
	if err != nil {
		writeAPIError(w, "FIRESTORE_ERROR", err)
		return
	}
	for _, room := range rooms {
		query := seatsRef(room.Ref.ID).Where("lastSyncAt", "<", cutoff)
		docs, err := query.Documents(ctx).GetAll()
		if err != nil {
			writeAPIError(w, "FIRESTORE_ERROR", err)
			return
		}
		for _, doc := range docs {
			_, err := doc.Ref.Delete(ctx, firestore.LastUpdateTime(doc.UpdateTime))
			switch status.Code(err) {
			case codes.OK:
				cleaned++
			case codes.FailedPrecondition, codes.NotFound:
				// The seat changed or was removed after the query.
			default:
				writeAPIError(w, "DELETE_ERROR", err)
				return
			}
		}
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"cleanedSessions": cleaned,
		"processedAt":     time.Now().UTC(),
	})
}

func seatId(num int) string {
	return fmt.Sprintf("seat-%02d", num)
}

func getString(data map[string]interface{}, key string) string {
	if v, ok := data[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

// getTime returns the time value for key, or the zero time when the field is
// missing, null, or not a timestamp (e.g. seeded empty seats).
func getTime(data map[string]interface{}, key string) time.Time {
	if v, ok := data[key]; ok {
		if t, ok := v.(time.Time); ok {
			return t
		}
	}
	return time.Time{}
}

func getInt(data map[string]interface{}, key string) int {
	if v, ok := data[key]; ok {
		if i, ok := v.(int64); ok {
			return int(i)
		}
	}
	return 0
}

func getBool(data map[string]interface{}, key string) bool {
	value, _ := data[key].(bool)
	return value
}

func writeJSON(w http.ResponseWriter, status int, value interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("Failed to write JSON response: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]interface{}{
		"error": map[string]string{
			"code":    code,
			"message": message,
		},
	})
}

func writeAPIError(w http.ResponseWriter, code string, err error) {
	var appErr *AppError
	if errors.As(err, &appErr) {
		writeError(w, appErr.Status, appErr.Code, appErr.Message)
		return
	}
	log.Printf("%s: %v", code, err)
	writeError(w, http.StatusInternalServerError, code, "Database operation failed")
}

type AppError struct {
	Code    string
	Message string
	Status  int
}

func (e *AppError) Error() string {
	return e.Message
}
