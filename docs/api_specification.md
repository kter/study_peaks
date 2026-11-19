# Global Study Peaks - API Specification

REST API endpoints for the virtual study room application.

**Base URL**: `https://api.studypeaks.example.com/v1`

---

## Authentication

Room and seat listings are public. For sit, sync, leave, and session lookup, signed-in clients send a Firebase ID token in the `Authorization` header.

```
Authorization: Bearer <id_token>
```

Guest clients omit the header. An invalid or expired token returns HTTP 401 with code `INVALID_TOKEN` on these endpoints.

---

## Endpoints

### Get Rooms List

**`GET /rooms`**

Returns all available study rooms with occupancy information.

**Response (200)**
```json
{
  "rooms": [
    {
      "roomId": "everest",
      "name": "Mt. Everest",
      "capacity": 100,
      "currentOccupancy": 42
    },
    {
      "roomId": "fuji",
      "name": "Mt. Fuji",
      "capacity": 50,
      "currentOccupancy": 23
    }
  ]
}
```

---

### Get Room Seats

**`GET /rooms/{roomId}/seats`**

Returns all seats in a room with current occupant information.

An unknown room returns HTTP 404 with code `ROOM_NOT_FOUND`.

**Response (200)**
```json
{
  "seats": [
    {
      "seatNumber": 1,
      "isOccupied": true,
      "user": {
        "displayName": "Taro",
        "countryCode": "JP",
        "statusMessage": "頑張る！",
        "currentSessionDuration": 1800
      }
    },
    {
      "seatNumber": 2,
      "isOccupied": false,
      "user": null
    }
  ]
}
```

---

### Sit Down (Take a Seat)

**`POST /rooms/{roomId}/sit`**

Occupies a seat in the specified room.

The server uses the verified Firebase UID for signed-in users and generates an `anon_` ID with a full UUID for guests. The request may include `userId`, which the server ignores.

For a signed-in user, taking a seat releases all previous seats held by that user across rooms in the same Firestore transaction. Taking the same seat starts a new session. If someone else occupies the requested seat, the server returns `409 SEAT_OCCUPIED` and keeps the user's existing seats. The lookup uses the `seats.userId` collection-group index.

**Request Body**
```json
{
  "seatNumber": 42
}
```

**Response (200)**
```json
{
  "sessionId": "sess_550e8400-e29b-41d4-a716-446655440000",
  "seatNumber": 42,
  "sessionStartedAt": "2026-01-12T02:00:00Z",
  "userId": "anon_9ad7e76b-15b0-4a0c-ae80-e72b93c76d1b"
}
```

New session IDs use a `sess_` prefix followed by a full UUID. Clients treat the entire ID as an opaque string.

**Errors**
| HTTP | Code | Description |
|------|------|-------------|
| 400 | `INVALID_SEAT` | Seat number is outside the range from 1 through the room capacity |
| 401 | `INVALID_TOKEN` | Firebase ID token is invalid or expired |
| 404 | `ROOM_NOT_FOUND` | Room does not exist |
| 409 | `SEAT_OCCUPIED` | The requested seat is occupied and cannot be taken by the caller |

---

### Sync Session (5-minute update)

**`POST /rooms/{roomId}/sync`**

Updates the session's `lastSyncAt` timestamp and duration. Called every 5 minutes from the client.

Signed-in sessions require a verified Firebase UID that matches the session owner. For guest sessions, the session ID is sufficient.

Sync returns `404 SESSION_NOT_FOUND` after a seat move replaces the session or the 24-hour inactivity cleanup deletes it. The client finalizes the local study record and clears the active session.

**Request Body**
```json
{
  "sessionId": "sess_550e8400-e29b-41d4-a716-446655440000",
  "currentDuration": 1800
}
```

**Response (200)**
```json
{
  "syncedAt": "2026-01-12T02:30:00Z"
}
```

**Errors**
| HTTP | Code | Description |
|------|------|-------------|
| 401 | `INVALID_TOKEN` | Firebase ID token is invalid or expired |
| 403 | `FORBIDDEN` | Signed-in session requires its owner's Firebase UID |
| 404 | `SESSION_NOT_FOUND` | Session does not exist |

---

### Leave Seat

**`POST /rooms/{roomId}/leave`**

Ends the current study session and frees the seat.

Leave uses the same ownership rules as sync.

**Request Body**
```json
{
  "sessionId": "sess_550e8400-e29b-41d4-a716-446655440000",
  "finalDuration": 3600
}
```

**Response (200)**
```json
{
  "totalSessionDuration": 3600,
  "endedAt": "2026-01-12T03:00:00Z"
}
```

**Errors**
| HTTP | Code | Description |
|------|------|-------------|
| 401 | `INVALID_TOKEN` | Firebase ID token is invalid or expired |
| 403 | `FORBIDDEN` | Signed-in session requires its owner's Firebase UID |
| 404 | `SESSION_NOT_FOUND` | Session does not exist |

---

### Get Session (Validate Session)

**`GET /rooms/{roomId}/sessions/{sessionId}`**

Validates if a session is still active. Used to restore session state after app restart.

**Response (200)**
```json
{
  "sessionId": "sess_550e8400-e29b-41d4-a716-446655440000",
  "roomId": "everest",
  "roomName": "Mt. Everest",
  "seatNumber": 42,
  "sessionStartedAt": "2026-01-12T02:00:00Z",
  "lastSyncAt": "2026-01-12T02:30:00Z",
  "currentDuration": 1800
}
```

**Errors**
| HTTP | Code | Description |
|------|------|-------------|
| 401 | `INVALID_TOKEN` | Firebase ID token is invalid or expired |
| 404 | `ROOM_NOT_FOUND` | Room does not exist |
| 404 | `SESSION_NOT_FOUND` | Session does not exist |
| 404 | `SESSION_EXPIRED` | More than 24 hours have passed since the last sync |

> [!NOTE]
> Session lookup and cleanup use the same 24-hour inactivity TTL.

---

### Internal: Cleanup Sessions

**`POST /internal/cleanup-sessions`**

Called by Cloud Scheduler every hour to remove sessions that have been inactive for more than 24 hours. This endpoint is relative to the service URL, outside `/v1`.

Cloud Scheduler sends a Google OIDC ID token as a Bearer token in the `Authorization` header. The API verifies the token against two environment variables.

| Variable | Value |
|----------|-------|
| `CLEANUP_AUDIENCE` | Cloud Run service URL used as the Scheduler token audience |
| `CLEANUP_INVOKER_EMAIL` | Email address of the Scheduler service account |

If either variable is unset or empty, or the token is missing, invalid, or from another caller, the endpoint returns HTTP 403 with code `FORBIDDEN`.

**Response (200)**
```json
{
  "cleanedSessions": 5,
  "processedAt": "2026-01-12T00:00:00Z"
}
```

---

## Error Response Format

All errors follow this structure:

```json
{
  "error": {
    "code": "SEAT_OCCUPIED",
    "message": "The requested seat is already occupied"
  }
}
```
