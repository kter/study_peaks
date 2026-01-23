# Global Study Peaks - API Specification

REST API endpoints for the virtual study room application.

**Base URL**: `https://api.studypeaks.example.com/v1`

---

## Authentication

All API requests require a valid Identity Platform JWT token in the `Authorization` header:

```
Authorization: Bearer <id_token>
```

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

**Request Body**
```json
{
  "seatNumber": 42
}
```

**Response (200)**
```json
{
  "sessionId": "sess_abc123",
  "seatNumber": 42,
  "sessionStartedAt": "2026-01-12T02:00:00Z"
}
```

**Errors**
| Code | Description |
|------|-------------|
| 400  | Seat number invalid |
| 409  | Seat already occupied |
| 409  | User already seated in another room |

---

### Sync Session (5-minute update)

**`POST /rooms/{roomId}/sync`**

Updates the session's `lastSyncAt` timestamp and duration. Called every 5 minutes from the client.

**Request Body**
```json
{
  "sessionId": "sess_abc123",
  "currentDuration": 1800
}
```

**Response (200)**
```json
{
  "syncedAt": "2026-01-12T02:30:00Z"
}
```

---

### Leave Seat

**`POST /rooms/{roomId}/leave`**

Ends the current study session and frees the seat.

**Request Body**
```json
{
  "sessionId": "sess_abc123",
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

---

### Get Session (Validate Session)

**`GET /rooms/{roomId}/sessions/{sessionId}`**

Validates if a session is still active. Used to restore session state after app restart.

**Response (200)**
```json
{
  "sessionId": "sess_abc123",
  "roomId": "denali",
  "roomName": "Denali",
  "seatNumber": 42,
  "sessionStartedAt": "2026-01-12T02:00:00Z",
  "lastSyncAt": "2026-01-12T02:30:00Z",
  "currentDuration": 1800
}
```

**Errors**
| Code | Description |
|------|-------------|
| 404  | Session not found or expired |

> [!NOTE]
> Sessions without sync for 3 hours are considered expired.

---

### Internal: Cleanup Sessions

**`POST /internal/cleanup-sessions`**

Called by Cloud Scheduler every hour to force logout sessions inactive for 24+ hours.

> [!NOTE]
> This endpoint requires Cloud Scheduler OIDC authentication.

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
