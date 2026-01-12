# Hypertrophy

[![Backend Coverage](https://img.shields.io/badge/backend%20coverage-70%25-brightgreen)](./backend/htmlcov/index.html)
[![Frontend Coverage](https://img.shields.io/badge/frontend%20coverage-pending-yellow)](./coverage/index.html)

## Project Overview

Hypertrophy is a workout tracking application designed for users who train in environments with unreliable connectivity. The app uses an event-driven architecture with offline-first capabilities, allowing users to log workouts, track body measurements, and analyze progress even when disconnected from the internet. Events are queued locally and synced when connectivity is restored, with idempotency guarantees to handle network failures gracefully. The system supports both anonymous and authenticated users, enabling immediate use without account creation. This project targets fitness enthusiasts who need reliable workout tracking regardless of network conditions.

## Key Features

- **Progress-centric design**: The app is built from the ground up to help you track and visualize your progress over time—every workout, set, and measurement contributes to your personal fitness timeline.
- **Offline-first experience**: Log workouts and capture important training details anytime, anywhere—even without an internet connection. All activity is securely queued and synced whenever you're back online.
- **Anonymous usage**: Start tracking immediately, no account required. Choose to create an account and merge your data later.
- **Body measurement tracking**: Record your body stats with optional auto-calculated body fat using the for a richer view of your journey.
- **AI-driven coaching & quick questions**: Receive personalized insights, ask workout or measurement questions, and get instant, AI-powered answers right in the app.
- **Weekly reports & measurement analytics**: AI based progress and measurement reports—generated weekly—give you actionable feedback, trends, and milestones.
- **Event-driven and idempotent sync**: Every action is stored as an event with strict ordering, ensuring a reliable and seamless sync across all your devices.


## Architecture & Design Decisions

The system follows an **event sourcing** pattern with **CQRS** (Command Query Responsibility Segregation). The `events` table is the single source of truth, storing all workout actions as immutable events with JSONB payloads. Read-optimized projections (`workouts_projection`, `sets_projection`) are rebuilt by replaying events in `(device_id, sequence_number)` order, ensuring deterministic state reconstruction.

**Why this architecture:**
- **Offline resilience**: Events can be queued locally and synced later without data loss
- **Idempotency**: Client-generated `event_id` prevents duplicate processing

For detailed architecture documentation, see [ARCHITECTURE.md](./ARCHITECTURE.md).


## Tech Stack

**Backend:**
- **FastAPI** (Python 3.11): Async web framework with automatic OpenAPI docs
- **SQLAlchemy 2.0**: ORM with declarative models
- **PostgreSQL 15**: Primary database with JSONB support for event payloads
- **Alembic**: Database migrations
- **Pydantic**: Request/response validation and event payload schemas


**Frontend:**
- **Flutter 3.10+**: Cross-platform mobile framework (iOS, Android)
- **sqflite**: Local SQLite database for event queue and templates
- **shared_preferences**: User authentication state persistence

**Infrastructure:**
- **Docker Compose**: Local development environment
- **pytest**: Backend testing framework


## Database & Data Model

**Core Entities:**

- **`users`**: User accounts (anonymous or authenticated). Anonymous users have `is_anonymous=true` and no email/password.
- **`events`**: Immutable event log. Each event has `event_id` (client-generated UUID), `event_type`, `payload` (JSONB), `user_id`, `device_id`, `sequence_number` (monotonic per device), and `correlation_id`.
- **`workouts_projection`**: Derived from events. Contains `workout_id`, `user_id`, `started_at`, `ended_at`, `status`.
- **`sets_projection`**: Derived from events. Contains `set_id`, `workout_id`, `exercise_id`, `reps`, `weight`, `completed_at`.
- **`exercises`**: Exercise catalog with `name` and `muscle_category`.
- **`body_measurements`**: User body measurements with calculated metrics (body fat %, fat mass, lean mass).
- **`weekly_metrics`**: Aggregated weekly statistics per user.
- **`weekly_reports`**: AI-generated weekly progress reports.

**Relationships:**
- Events reference `user_id` and `device_id` (no foreign keys for flexibility)
- Projections reference `user_id` and `workout_id` with foreign keys
- Sets reference workouts via `workout_id` foreign key

**Data Access:**
- SQLAlchemy ORM with declarative models
- Direct SQL queries for projection rebuilds (performance)
- Alembic migrations for schema changes

**Migration Strategy:**
- All schema changes go through Alembic migrations
- Migrations are versioned and reversible

## Testing Strategy

**Test Types:**

- **Unit tests** (`backend/tests/unit/`): Service layer logic, business rules, calculations (body fat calculator, metrics aggregation). Mock database sessions.
- **Integration tests** (`backend/tests/integration/`): Full API endpoints with test database, event sync idempotency, projection rebuilds, partial failure handling.

**Coverage:**
- ✅ Event sync idempotency and ordering validation
- ✅ Projection rebuild correctness
- ✅ Body fat calculation (Navy method for male/female)
- ✅ API authentication and authorization
- ✅ Partial batch failure handling in sync

For detailed testing documentation, see [TESTING.md](./TESTING.md).


## Setup & Running Locally

**Prerequisites:**
- Python 3.11+
- Flutter 3.10+
- Docker and Docker Compose
- PostgreSQL 15 (or use Docker Compose)
- OpenAI API key (optional, for AI features)

**Backend Setup:**

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set up environment variables
export DATABASE_URL="postgresql://hypertrophy:hypertrophy_dev@localhost:5432/hypertrophy"
export OPENAI_API_KEY="sk-..."  # Optional
export AI_MEMORY_DB_PATH="./data/agent_memory.db"

# Run database migrations
alembic upgrade head

# Start backend server
uvicorn app.main:app --reload
```

**Using Docker Compose (Recommended):**

```bash
# Start PostgreSQL and API
docker-compose up -d

# Run migrations (in API container or locally)
docker-compose exec api alembic upgrade head
```

Backend API available at `http://localhost:8000`
- Swagger UI: `http://localhost:8000/docs`
- Health check: `http://localhost:8000/health`

**Frontend Setup:**

```bash
# Install Flutter dependencies
flutter pub get

# Run on iOS simulator
flutter run -d ios

# Run on Android emulator
flutter run -d android
```

**Environment Variables (Backend):**
- `DATABASE_URL`: PostgreSQL connection string (default: `postgresql://hypertrophy:hypertrophy_dev@localhost:5432/hypertrophy`)
- `OPENAI_API_KEY`: OpenAI API key for AI features (optional)
- `AI_MEMORY_DB_PATH`: Path to SQLite file for AI agent memory (default: `./data/agent_memory.db`)
- `ENV`: Environment name (`development`, `production`)
