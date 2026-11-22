# Global Study Peaks - Firestore Data Model

Firestore Native Mode schema design for the virtual study room application.

---

## Collections Overview

```
├── users/                          # User profiles
│   └── {userId}
├── rooms/                          # Study rooms
│   └── {roomId}
│       └── seats/                  # Subcollection
│           └── {seatId}
```

---

## Collection: `users`

User profile and settings.

| Field | Type | Description |
|-------|------|-------------|
| `userId` | string | Document ID (from Identity Platform) |
| `displayName` | string | User-selected display name (max 30 chars) |
| `countryCode` | string | ISO 3166-1 alpha-2 code (e.g., "JP", "US") |
| `statusMessage` | string | One-line message (max 50 chars) |
| `createdAt` | timestamp | Account creation time (server timestamp) |
| `lastActiveAt` | timestamp | Last activity timestamp |
| `totalStudyTime` | number | Cumulative study time in seconds |

**Example Document**
```json
{
  "displayName": "Taro",
  "countryCode": "JP",
  "statusMessage": "頑張る！",
  "createdAt": "2026-01-01T00:00:00Z",
  "lastActiveAt": "2026-01-12T02:00:00Z",
  "totalStudyTime": 36000
}
```

---

## Collection: `rooms`

Study room definitions.

| Field | Type | Description |
|-------|------|-------------|
| `roomId` | string | Document ID (e.g., "everest", "fuji") |
| `name` | string | Display name (e.g., "Mt. Everest") |
| `capacity` | number | Maximum seats (50-100) |
| `currentOccupancy` | number | Current occupied seat count |

**Example Document**
```json
{
  "name": "Mt. Everest",
  "capacity": 100,
  "currentOccupancy": 42
}
```

**Predefined Rooms**
| roomId | name | capacity |
|--------|------|----------|
| `everest` | Mt. Everest | 100 |
| `fuji` | Mt. Fuji | 50 |
| `matterhorn` | Matterhorn | 75 |
| `kilimanjaro` | Mt. Kilimanjaro | 80 |
| `denali` | Denali | 60 |

---

## Subcollection: `rooms/{roomId}/seats`

Individual seat state within a room.

When a user with a verified Firebase UID takes a seat, including a user signed in anonymously, the API looks up all seat documents for that `userId` across rooms, deletes them, and writes the new seat in one transaction. Taking the same seat replaces its session ID. If someone else occupies the requested seat, the transaction leaves the user's existing seats in place.

| Field | Type | Description |
|-------|------|-------------|
| `seatId` | string | Document ID (e.g., "seat-001") |
| `seatNumber` | number | Visual seat number (1-100) |
| `isOccupied` | boolean | Occupation status |
| `userId` | string \| null | Occupying user's Firebase UID or an `anon_<uuid>` ID for guests without a token |
| `ownerAnonymous` | boolean (optional) | True if the seat was created using a Firebase anonymous token |
| `sessionId` | string \| null | Current session identifier |
| `sessionStartedAt` | timestamp \| null | When user sat down (server timestamp) |
| `lastSyncAt` | timestamp \| null | Last 5-min sync (server timestamp) |
| `currentSessionDuration` | number | Duration in seconds at last sync |

**Example Document (Occupied)**
```json
{
  "seatNumber": 42,
  "isOccupied": true,
  "userId": "user123",
  "sessionId": "sess_abc123",
  "sessionStartedAt": "2026-01-12T02:00:00Z",
  "lastSyncAt": "2026-01-12T02:25:00Z",
  "currentSessionDuration": 1500
}
```

**Example Document (Empty)**
```json
{
  "seatNumber": 43,
  "isOccupied": false,
  "userId": null,
  "sessionId": null,
  "sessionStartedAt": null,
  "lastSyncAt": null,
  "currentSessionDuration": 0
}
```

---

## Indexes

### Single-Field Index for Seat Moves

Terraform adds an ascending `COLLECTION_GROUP` index for `seats.userId` so the sit transaction can find seats by UID across rooms. The default collection-scope indexes are preserved.

Apply this index with Terraform and wait until it is `READY` before deploying an API version that moves seats. Without it, every signed-in sit fails with `FAILED_PRECONDITION`.

### Required Composite Indexes

1. **Inactive Session Cleanup**
   - Collection: `seats`
   - Fields: `isOccupied` (ASC), `lastSyncAt` (ASC)
   - Purpose: Query sessions for auto-logout after 30 minutes of inactivity

2. **Room Seats Query**
   - Collection: `seats` (collection group)
   - Fields: `roomId` (ASC), `seatNumber` (ASC)
   - Purpose: Fetch all seats in a room

---

## Auto-Logout Logic

The Cloud Scheduler job runs every 10 minutes and queries:

```
WHERE isOccupied == true
AND lastSyncAt < (now - 30 minutes)
```

Matching seats are force-vacated:
1. Set `isOccupied = false`
2. Clear user-related fields
3. Decrement room's `currentOccupancy`
4. Update user's `totalStudyTime`
