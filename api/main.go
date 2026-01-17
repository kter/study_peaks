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
		})
	})

	r.Post("/internal/cleanup-sessions", cleanupHandler)
	r.Post("/internal/cleanup-old-seeds", cleanupOldSeedsHandler)

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

	docs, err := firestoreClient.Collection("rooms").Doc(roomId).Collection("seats").Documents(ctx).GetAll()
	if err != nil {
		writeError(w, http.StatusInternalServerError, "FIRESTORE_ERROR", err.Error())
		return
	}

	type UserInfo struct {
		DisplayName            string `json:"displayName"`
		CountryCode            string `json:"countryCode"`
		StatusMessage          string `json:"statusMessage"`
		CurrentSessionDuration int    `json:"currentSessionDuration"`
	}

	type SeatResponse struct {
		SeatNumber int       `json:"seatNumber"`
		IsOccupied bool      `json:"isOccupied"`
		User       *UserInfo `json:"user"`
	}

	seats := []SeatResponse{}
	for _, doc := range docs {
		data := doc.Data()
		seat := SeatResponse{
			SeatNumber: int(data["seatNumber"].(int64)),
			IsOccupied: data["isOccupied"].(bool),
		}

		if seat.IsOccupied {
			seat.User = &UserInfo{
				DisplayName:            getString(data, "displayName"),
				CountryCode:            getString(data, "countryCode"),
				StatusMessage:          getString(data, "statusMessage"),
				CurrentSessionDuration: getInt(data, "currentSessionDuration"),
			}
		}

		seats = append(seats, seat)
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

		return tx.Set(seatRef, map[string]interface{}{
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
		})
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
	_, err = docs[0].Ref.Update(ctx, []firestore.Update{
		{Path: "lastSyncAt", Value: now},
		{Path: "currentSessionDuration", Value: req.CurrentDuration},
	})

	if err != nil {
		writeError(w, http.StatusInternalServerError, "UPDATE_ERROR", err.Error())
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"syncedAt": now})
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

// cleanupOldSeedsHandler removes old seed documents that use the wrong ID format
func cleanupOldSeedsHandler(w http.ResponseWriter, r *http.Request) {
	initMu.RLock()
	ready := isInitialized
	initMu.RUnlock()

	if !ready {
		writeError(w, http.StatusServiceUnavailable, "INITIALIZING", "Service is starting up")
		return
	}

	ctx := r.Context()
	cleaned := 0

	// List of room IDs
	roomIds := []string{"everest", "fuji", "kilimanjaro", "denali"}

	for _, roomId := range roomIds {
		docs, err := firestoreClient.Collection("rooms").Doc(roomId).Collection("seats").Documents(ctx).GetAll()
		if err != nil {
			log.Printf("Error listing seats for room %s: %v", roomId, err)
			continue
		}

		for _, doc := range docs {
			// Old format: "denali-seat-001", new format: "seat-01"
			// Delete documents that contain roomId in their ID
			if len(doc.Ref.ID) > 10 && doc.Ref.ID[:len(roomId)] == roomId {
				if _, err := doc.Ref.Delete(ctx); err == nil {
					cleaned++
					log.Printf("Deleted old seed document: %s/%s", roomId, doc.Ref.ID)
				}
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"cleanedDocuments": cleaned,
		"processedAt":      time.Now().UTC(),
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
