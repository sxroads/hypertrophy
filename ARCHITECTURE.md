# Architecture Documentation

## Overview

Hypertrophy is an offline-first workout tracking application built with an event-driven architecture. The system uses **Event Sourcing** with **CQRS** (Command Query Responsibility Segregation) to ensure reliable data synchronization and offline resilience.

## System Architecture

### High-Level Architecture

```
┌─────────────────┐         ┌─────────────────┐
│  Flutter App    │◄───────►│  FastAPI Backend │
│  (Mobile)       │  HTTP   │  (Python)        │
└────────┬────────┘         └────────┬─────────┘
         │                            │
         │                            │
    ┌────▼────┐                  ┌────▼────┐
    │ SQLite  │                  │PostgreSQL│
    │ (Local) │                  │  (Cloud)│
    └─────────┘                  └─────────┘
```

### Core Principles

1. **Event Sourcing**: All state changes are stored as immutable events
2. **Offline-First**: App works without internet, syncs when online
3. **Idempotency**: Events can be safely retried without duplication
4. **CQRS**: Separate read (projections) and write (events) models

## Backend Architecture

### Event-Driven Design

The backend uses an event log as the single source of truth:

- **`events` table**: Immutable event log with JSONB payloads
- **Projections**: Read-optimized views (`workouts_projection`, `sets_projection`)
- **Event Types**: `WorkoutStarted`, `WorkoutEnded`, `SetCompleted`, etc.

### Data Flow

```
Client Event → POST /api/v1/sync → Event Validation → Event Storage
                                                      ↓
                                              Projection Rebuild
                                                      ↓
                                              Read from Projections
```

### Key Components

#### 1. Sync Service (`app/services/sync_service.py`)
- Handles idempotent event ingestion
- Validates sequence numbers (monotonic per device)
- Ensures transactional consistency
- Returns acknowledgment cursors

#### 2. Projection Service (`app/services/projection_service.py`)
- Rebuilds read-optimized projections from events
- Ensures deterministic state reconstruction
- Handles projection updates after event sync

#### 3. API Layer (`app/api/v1/`)
- RESTful endpoints for sync, projections, auth, workouts, etc.
- Rate limiting via `slowapi`
- JWT authentication for authenticated users
- Optional authentication for anonymous users

### Database Schema

#### Events Table
```sql
events (
    event_id UUID PRIMARY KEY,        -- Client-generated, ensures idempotency
    event_type VARCHAR,                -- Event type (WorkoutStarted, etc.)
    payload JSONB,                     -- Event-specific data
    user_id UUID,                      -- User identifier
    device_id UUID,                    -- Device identifier
    sequence_number INTEGER,           -- Monotonic per device
    correlation_id UUID,               -- For grouping related events
    created_at TIMESTAMP
)
```

#### Projections
- `workouts_projection`: Derived workout state
- `sets_projection`: Derived set data
- Rebuilt by replaying events in `(device_id, sequence_number)` order

## Frontend Architecture

### Flutter App Structure

```
lib/
├── main.dart                 # App entry point, auth wrapper
├── pages/                    # UI screens
├── services/                 # Business logic
│   ├── sync_service.dart     # Event sync coordination
│   ├── event_queue_service.dart  # Local event queue
│   ├── auth_service.dart     # Authentication
│   └── api_service.dart      # HTTP client
└── widgets/                  # Reusable UI components
```

### Offline-First Flow

1. **Event Creation**: User actions create events stored in local SQLite
2. **Event Queue**: Events marked as `pending` until synced
3. **Sync Process**: 
   - Attempts sync on app foreground
   - Retries failed events
   - Marks events as `synced` after successful sync
4. **State Management**: Local state derived from events + projections

### Local Database Schema

```sql
event_queue (
    event_id TEXT PRIMARY KEY,
    event_type TEXT,
    payload TEXT,              -- JSON string
    device_id TEXT,
    user_id TEXT,
    sequence_number INTEGER,
    status TEXT,               -- 'pending', 'syncing', 'synced', 'failed'
    created_at INTEGER,
    synced_at INTEGER
)
```

## Authentication & User Management

### Anonymous Users
- Created automatically on first app launch
- Identified by `device_id` only
- Can upgrade to authenticated account later

### Authenticated Users
- Email/password authentication
- JWT tokens for API access
- Can merge anonymous data when registering

### User Merge Service
- Merges events from anonymous user to authenticated user
- Preserves event ordering and sequence numbers
- Updates all related projections

## Sync Protocol

### Idempotency Guarantees

1. **Event ID Uniqueness**: Client-generated UUIDs prevent duplicates
2. **Sequence Number Validation**: Monotonic sequence per device ensures ordering
3. **Acknowledgment Cursors**: Server returns last accepted sequence number

### Sync Request Format

```json
{
  "device_id": "uuid",
  "user_id": "uuid",
  "events": [
    {
      "event_id": "uuid",
      "event_type": "WorkoutStarted",
      "payload": {...},
      "sequence_number": 1
    }
  ]
}
```

### Sync Response Format

```json
{
  "ack_cursor": {
    "device_id": "uuid",
    "last_acked_sequence": 5
  },
  "accepted_count": 5,
  "rejected_count": 0,
  "rejected_event_ids": []
}
```

## Projection Rebuild

Projections are rebuilt by:
1. Querying all events ordered by `(device_id, sequence_number)`
2. Replaying events to reconstruct state
3. Updating projection tables atomically

This ensures:
- Deterministic state reconstruction
- Consistency after failures
- Ability to rebuild from scratch

## Error Handling

### Sync Failures
- Events marked as `failed` in local queue
- Retried on next sync attempt
- Partial batch success handled gracefully

### Network Failures
- Events remain in local queue
- Sync retries automatically on app foreground
- No data loss

### Validation Errors
- Invalid events rejected with specific error messages
- Valid events in batch still accepted
- Client can retry rejected events after fixing

## Performance Considerations

### Backend
- Batch event insertion for efficiency
- Projection rebuilds can be async (background job)
- Indexes on `event_id`, `(device_id, sequence_number)`

### Frontend
- Local SQLite for fast offline access
- Incremental sync (only pending events)
- Background sync on app foreground

## Security

- JWT tokens for authenticated endpoints
- Rate limiting on sensitive endpoints (AI chat, sync)
- Input validation via Pydantic models
- SQL injection prevention via SQLAlchemy ORM

