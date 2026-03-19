# VinoVoyage

A social wine trip planning and tasting journal built with Django. Plan wine trips with friends, check in at wineries in real time, rate your experience, log every wine you taste, and build a personal wine history over time.

## What It Does

**Plan Trips** — Create wine trips, build an ordered itinerary of winery stops, invite friends by email, and manage RSVPs. Drag-and-drop to reorder your itinerary.

**Live Trip Mode** — On the day of your trip, launch the step-by-step live experience. Check in at each winery, rate the staff, ambience, and food, then log every wine you taste with the varietal, vintage, serving type (tasting, glass, flight, bottle), star rating, and tasting notes. Mark favorites and track purchases for future reference.

**Explore Wineries** — Search and discover wineries on an interactive Google Maps interface. Favorite wineries, view community ratings, and start trips directly from the map.

**Tasting Journal** — Every check-in and wine tasting is saved as a permanent visit log. Track your history, see your top-rated wineries, and build a personal palate profile.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Backend** | Django 5.x, Python 3.12+ |
| **Database** | PostgreSQL 16 |
| **Cache / Broker** | Redis 7 |
| **Task Queue** | Celery 5 |
| **Frontend** | Materialize CSS 1.0, htmx 2.0, SortableJS |
| **Maps** | Google Maps JavaScript API (Places, AdvancedMarkerElement) |
| **Auth** | OAuth2 (Google, Microsoft) via python-social-auth |
| **API** | Django REST Framework, JWT (SimpleJWT) |
| **AI** | LangGraph, Claude (Anthropic), Gemini (Google), Pinecone vector DB |
| **Encryption** | django-encrypted-model-fields (OAuth tokens at rest) |
| **Infrastructure** | Docker Compose (local), AWS ECS Fargate (production) |
| **CI/CD** | GitHub Actions (lint, type check, test on every push) |
| **Monitoring** | Sentry (error tracking), structured JSON logging |

## Django Apps

| App | Purpose |
|-----|---------|
| `core` | BaseModel (UUID PK, timestamps, soft delete), landing page |
| `users` | Custom User model (email login, no passwords), OAuth social accounts |
| `wineries` | Winery and Wine models, Google Places integration, favorites |
| `visits` | VisitLog (multi-factor ratings), VisitWine (tastings with serving type, purchases) |
| `trips` | Trip planning (members, invitations, itinerary), Live Trip mode |
| `palate` | PalateProfile (structured preferences, Pinecone vector) |
| `lookup` | Universal reference data table with parent-child hierarchy |
| `rbac` | Role-based access control (groups, control points, roles) |
| `api` | Health check, JWT auth callback, LangGraph AI agents |

## Quick Start

```bash
# Clone and configure
git clone https://github.com/BillClerici/vino.git
cd vino
cp .env.docker.example .env.docker
cp .env.example .env
# Edit .env and .env.docker with your API keys

# Start everything
make up

# Set up the database
make migrate
make seed

# Open in browser
open http://localhost:8000
```

## Commands

```bash
make up              # Start all services (Docker Compose)
make down            # Stop all services
make build           # Rebuild Docker images
make migrate         # Run Django migrations
make seed            # Seed lookups, superusers, and RBAC
make shell           # Django shell_plus
make test            # Run pytest
make lint            # Run ruff + mypy
make logs            # Tail ECS CloudWatch logs
make deploy ENV=dev  # Deploy to AWS ECS Fargate
```

## Running Tests

```bash
# All tests
make test

# Single file
docker-compose exec web pytest tests/unit/test_models.py -v

# By keyword
docker-compose exec web pytest -k "test_health" -v
```

## Architecture Highlights

- **UUID primary keys** on all models — no auto-increment IDs
- **Soft delete** — `is_active=False`, never hard delete. Default manager filters automatically
- **OAuth2 only** — users authenticate via Google or Microsoft. No passwords stored
- **Environment-based settings** — `base.py` (shared), `local.py` (dev), `dev.py` / `uat.py` / `prod.py` (AWS)
- **AI agents** — LangGraph state machines for palate analysis and trip planning, backed by Claude and Gemini
- **Docker stack** — web (Django :8000), db (PostgreSQL), redis, worker (Celery)

## Environment Variables

Copy `.env.example` and fill in your keys:

- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` — Google OAuth
- `MICROSOFT_CLIENT_ID` / `MICROSOFT_CLIENT_SECRET` — Microsoft OAuth
- `GOOGLE_MAPS_API_KEY` — Maps and Places API
- `ANTHROPIC_API_KEY` — Claude AI
- `GOOGLE_API_KEY` — Gemini AI
- `PINECONE_API_KEY` — Vector search
- `STRIPE_*` — Payment processing
- `SENTRY_DSN` — Error monitoring (optional)

## License

Private repository.
