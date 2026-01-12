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

| Field | Type | Description |
|-------|------|-------------|
| `seatId` | string | Document ID (e.g., "seat-001") |
| `seatNumber` | number | Visual seat number (1-100) |
| `isOccupied` | boolean | Occupation status |
| `userId` | string \| null | Occupying user's ID |
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

### Required Composite Indexes

1. **Inactive Session Cleanup**
   - Collection: `seats`
   - Fields: `isOccupied` (ASC), `lastSyncAt` (ASC)
   - Purpose: Query sessions for 24h auto-logout

2. **Room Seats Query**
   - Collection: `seats` (collection group)
   - Fields: `roomId` (ASC), `seatNumber` (ASC)
   - Purpose: Fetch all seats in a room

---

## Auto-Logout Logic

The Cloud Scheduler job runs every hour and queries:

```
WHERE isOccupied == true
AND lastSyncAt < (now - 24 hours)
```

Matching seats are force-vacated:
1. Set `isOccupied = false`
2. Clear user-related fields
3. Decrement room's `currentOccupancy`
4. Update user's `totalStudyTime`
