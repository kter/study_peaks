package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"
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

	r.Post("/internal/cleanup-sessions", cleanupHandler)

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

	initMu.Lock()
	firestoreClient = fc
	authClient = ac
	isInitialized = true
	initMu.Unlock()

	// Initialize rooms
	initializeRooms(ctx)
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

func initializeRooms(ctx context.Context) {
	rooms := []map[string]interface{}{
		{"roomId": "everest", "name": "Mt. Everest", "capacity": 100},
		{"roomId": "fuji", "name": "Mt. Fuji", "capacity": 50},
		{"roomId": "kilimanjaro", "name": "Mt. Kilimanjaro", "capacity": 75},
		{"roomId": "denali", "name": "Denali", "capacity": 40},
	}

	for _, room := range rooms {
		roomId := room["roomId"].(string)
		_, err := firestoreClient.Collection("rooms").Doc(roomId).Set(ctx, room, firestore.MergeAll)
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

// optionalAuthMiddleware attempts to verify Firebase token if present,
// but allows the request to proceed without authentication for anonymous users
func optionalAuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		authHeader := r.Header.Get("Authorization")

		if len(authHeader) >= 7 && authHeader[:7] == "Bearer " {
			token := authHeader[7:]
			decoded, err := authClient.VerifyIDToken(ctx, token)
			if err == nil {
				ctx = context.WithValue(ctx, "userId", decoded.UID)
				ctx = context.WithValue(ctx, "isAuthenticated", true)
			}
		}

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if len(authHeader) < 8 || authHeader[:7] != "Bearer " {
			writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "Missing or invalid authorization header")
			return
		}

		token := authHeader[7:]
		decoded, err := authClient.VerifyIDToken(r.Context(), token)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "INVALID_TOKEN", "Invalid or expired token")
			return
		}

		ctx := context.WithValue(r.Context(), "userId", decoded.UID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

func getRoomsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	docs, err := firestoreClient.Collection("rooms").Documents(ctx).GetAll()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "FIRESTORE_ERROR", err.Error())
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
		seatsQuery := firestoreClient.Collection("rooms").Doc(doc.Ref.ID).Collection("seats").Where("isOccupied", "==", true)
		seatDocs, _ := seatsQuery.Documents(ctx).GetAll()

		rooms = append(rooms, RoomResponse{
			RoomId:           doc.Ref.ID,
			Name:             data["name"].(string),
			Capacity:         int(data["capacity"].(int64)),
			CurrentOccupancy: len(seatDocs),
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"rooms": rooms})
}

func getSeatsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	roomId := chi.URLParam(r, "roomId")

	// Get room capacity
	roomDoc, err := firestoreClient.Collection("rooms").Doc(roomId).Get(ctx)
	if err != nil {
		writeError(w, http.StatusNotFound, "ROOM_NOT_FOUND", "Room not found")
		return
	}
	roomData := roomDoc.Data()
	capacity := int(roomData["capacity"].(int64))

	// Get occupied seats from Firestore
	docs, err := firestoreClient.Collection("rooms").Doc(roomId).Collection("seats").Documents(ctx).GetAll()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "FIRESTORE_ERROR", err.Error())
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
		seatNum := int(data["seatNumber"].(int64))
		seat := SeatResponse{
			SeatId:     doc.Ref.ID,
			SeatNumber: seatNum,
			IsOccupied: data["isOccupied"].(bool),
		}

		if val, ok := data["sessionStartedAt"]; ok {
			seat.SessionStartedAt = val.(time.Time)
		}

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
	seats := make([]SeatResponse, 0, capacity)
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

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"seats": seats})
}

func sitHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	roomId := chi.URLParam(r, "roomId")

	var req struct {
		SeatNumber  int    `json:"seatNumber"`
		DisplayName string `json:"displayName"`
		CountryCode string `json:"countryCode"`
		UserId      string `json:"userId"`
		IconSeed    string `json:"iconSeed"`
		PhotoUrl    string `json:"photoUrl"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "INVALID_REQUEST", "Invalid request body")
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

	// Get userId from auth context or request, generate if not present
	userId := ""
	if ctxUserId := ctx.Value("userId"); ctxUserId != nil {
		userId = ctxUserId.(string)
	} else if req.UserId != "" {
		userId = req.UserId
	} else {
		userId = "anon_" + uuid.New().String()[:8]
	}

	seatRef := firestoreClient.Collection("rooms").Doc(roomId).Collection("seats").Doc(seatId(req.SeatNumber))

	err := firestoreClient.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(seatRef)
		if err == nil && doc.Exists() {
			data := doc.Data()
			if data["isOccupied"].(bool) {
				return &AppError{Code: "SEAT_OCCUPIED", Message: "Seat is already occupied", Status: http.StatusConflict}
			}
		}

		sessionId := "sess_" + uuid.New().String()[:8]
		now := time.Now().UTC()

		updateMap := map[string]interface{}{
			"seatNumber":             req.SeatNumber,
			"isOccupied":             true,
			"userId":                 userId,
			"sessionId":              sessionId,
			"sessionStartedAt":       now,
			"lastSyncAt":             now,
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
		if appErr, ok := err.(*AppError); ok {
			writeError(w, appErr.Status, appErr.Code, appErr.Message)
			return
		}
		writeError(w, http.StatusInternalServerError, "TRANSACTION_ERROR", err.Error())
		return
	}

	doc, _ := seatRef.Get(ctx)
	data := doc.Data()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"sessionId":        data["sessionId"],
		"seatNumber":       req.SeatNumber,
		"sessionStartedAt": data["sessionStartedAt"],
		"userId":           userId,
	})
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

	query := firestoreClient.Collection("rooms").Doc(roomId).Collection("seats").Where("sessionId", "==", req.SessionId).Limit(1)
	docs, err := query.Documents(ctx).GetAll()
	if err != nil || len(docs) == 0 {
		writeError(w, http.StatusNotFound, "SESSION_NOT_FOUND", "Session not found")
		return
	}

	now := time.Now().UTC()
	updates := []firestore.Update{
		{Path: "lastSyncAt", Value: now},
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

	_, err = docs[0].Ref.Update(ctx, updates)

	if err != nil {
		writeError(w, http.StatusInternalServerError, "UPDATE_ERROR", err.Error())
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"syncedAt": now})
}

func getSessionHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	roomId := chi.URLParam(r, "roomId")
	sessionId := chi.URLParam(r, "sessionId")

	// Get room info for room name
	roomDoc, err := firestoreClient.Collection("rooms").Doc(roomId).Get(ctx)
	if err != nil {
		writeError(w, http.StatusNotFound, "ROOM_NOT_FOUND", "Room not found")
		return
	}
	roomData := roomDoc.Data()
	roomName := getString(roomData, "name")

	// Find the session by sessionId
	query := firestoreClient.Collection("rooms").Doc(roomId).Collection("seats").Where("sessionId", "==", sessionId).Limit(1)
	docs, err := query.Documents(ctx).GetAll()
	if err != nil || len(docs) == 0 {
		writeError(w, http.StatusNotFound, "SESSION_NOT_FOUND", "Session not found or expired")
		return
	}

	data := docs[0].Data()

	// Check if the session is still valid (not stale)
	// Sessions without sync for 3 hours are considered expired
	if lastSyncAt, ok := data["lastSyncAt"].(time.Time); ok {
		if time.Since(lastSyncAt) > 3*time.Hour {
			writeError(w, http.StatusNotFound, "SESSION_EXPIRED", "Session has expired due to inactivity")
			return
		}
	}

	var sessionStartedAt time.Time
	if val, ok := data["sessionStartedAt"]; ok {
		sessionStartedAt = val.(time.Time)
	}
	var lastSyncAt time.Time
	if val, ok := data["lastSyncAt"]; ok {
		lastSyncAt = val.(time.Time)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
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

	query := firestoreClient.Collection("rooms").Doc(roomId).Collection("seats").Where("sessionId", "==", req.SessionId).Limit(1)
	docs, err := query.Documents(ctx).GetAll()
	if err != nil || len(docs) == 0 {
		writeError(w, http.StatusNotFound, "SESSION_NOT_FOUND", "Session not found")
		return
	}

	now := time.Now().UTC()
	_, err = docs[0].Ref.Delete(ctx)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "DELETE_ERROR", err.Error())
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"totalSessionDuration": req.FinalDuration,
		"endedAt":              now,
	})
}

func cleanupHandler(w http.ResponseWriter, r *http.Request) {
	initMu.RLock()
	ready := isInitialized
	initMu.RUnlock()

	if !ready {
		writeError(w, http.StatusServiceUnavailable, "INITIALIZING", "Service is starting up")
		return
	}

	ctx := r.Context()
	cutoff := time.Now().UTC().Add(-24 * time.Hour)
	cleaned := 0

	rooms, _ := firestoreClient.Collection("rooms").Documents(ctx).GetAll()
	for _, room := range rooms {
		query := room.Ref.Collection("seats").Where("lastSyncAt", "<", cutoff)
		docs, _ := query.Documents(ctx).GetAll()
		for _, doc := range docs {
			doc.Ref.Delete(ctx)
			cleaned++
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"cleanedSessions": cleaned,
		"processedAt":     time.Now().UTC(),
	})
}

func seatId(num int) string {
	return "seat-" + string(rune('0'+num/10)) + string(rune('0'+num%10))
}

func getString(data map[string]interface{}, key string) string {
	if v, ok := data[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

func getInt(data map[string]interface{}, key string) int {
	if v, ok := data[key]; ok {
		if i, ok := v.(int64); ok {
			return int(i)
		}
	}
	return 0
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"error": map[string]string{
			"code":    code,
			"message": message,
		},
	})
}

type AppError struct {
	Code    string
	Message string
	Status  int
}

func (e *AppError) Error() string {
	return e.Message
}
