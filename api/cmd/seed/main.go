package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"google.golang.org/api/option"
)

// Room configuration
var roomSeats = map[string]int{
	"everest":     100,
	"fuji":        50,
	"kilimanjaro": 75,
	"denali":      40,
}

func main() {
	ctx := context.Background()

	projectPtr := flag.String("project", "", "GCP project ID (studypeaks-dev or studypeaks-prd)")
	flag.Parse()

	projectID := *projectPtr
	if projectID == "" {
		projectID = os.Getenv("GOOGLE_CLOUD_PROJECT")
	}
	if projectID == "" {
		log.Fatal("Please specify project ID with -project flag or GOOGLE_CLOUD_PROJECT env var")
	}

	log.Printf("Seeding Firestore for project: %s", projectID)

	var app *firebase.App
	var err error

	// Check for service account credentials
	credFile := os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")
	if credFile != "" {
		app, err = firebase.NewApp(ctx, nil, option.WithCredentialsFile(credFile))
	} else {
		// Use default credentials (for Cloud Shell or local gcloud auth)
		app, err = firebase.NewApp(ctx, &firebase.Config{
			ProjectID: projectID,
		})
	}

	if err != nil {
		log.Fatalf("Failed to initialize Firebase: %v", err)
	}

	client, err := app.Firestore(ctx)
	if err != nil {
		log.Fatalf("Failed to initialize Firestore: %v", err)
	}
	defer client.Close()

	// Seed rooms and seats
	for roomId, capacity := range roomSeats {
		if err := seedRoom(ctx, client, roomId, capacity); err != nil {
			log.Printf("Failed to seed room %s: %v", roomId, err)
		} else {
			log.Printf("✓ Seeded room %s with %d seats", roomId, capacity)
		}
	}

	log.Println("Seeding complete!")
}

func seedRoom(ctx context.Context, client *firestore.Client, roomId string, capacity int) error {
	roomRef := client.Collection("rooms").Doc(roomId)

	// Use batched writes for efficiency (max 500 operations per batch)
	batch := client.Batch()
	batchCount := 0

	for i := 1; i <= capacity; i++ {
		seatId := fmt.Sprintf("%s-seat-%03d", roomId, i)
		seatRef := roomRef.Collection("seats").Doc(seatId)

		seat := map[string]interface{}{
			"seatId":                 seatId,
			"roomId":                 roomId,
			"seatNumber":             i,
			"isOccupied":             false,
			"user":                   nil,
			"sessionStartedAt":       nil,
			"currentSessionDuration": 0,
			"lastSyncAt":             nil,
		}

		batch.Set(seatRef, seat)
		batchCount++

		// Commit batch if we reach 500 operations
		if batchCount >= 500 {
			if _, err := batch.Commit(ctx); err != nil {
				return fmt.Errorf("batch commit failed: %w", err)
			}
			batch = client.Batch()
			batchCount = 0
		}
	}

	// Commit remaining operations
	if batchCount > 0 {
		if _, err := batch.Commit(ctx); err != nil {
			return fmt.Errorf("final batch commit failed: %w", err)
		}
	}

	return nil
}
