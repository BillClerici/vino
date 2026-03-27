# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vino is a Django 5.x web application with OAuth2 social authentication (Google, Microsoft), RBAC, PostgreSQL, Redis, Celery, and a REST API. Frontend uses Materialize CSS. Generated via the GSD Framework.

## Commands

```bash
make up              # Start all services (docker-compose up -d)
make down            # Stop all services
make build           # Rebuild Docker images
make migrate         # Run Django migrations
make seed            # Run all seed commands (lookups, superusers, rbac)
make shell           # Django shell_plus
make test            # pytest -v
make lint            # ruff check + mypy
make logs            # Tail ECS CloudWatch logs
make deploy ENV=dev  # Deploy to AWS ECS Fargate (prompts for confirmation if ENV=prod)
make sso-login       # AWS SSO login
```

Run a single test file:
```bash
docker-compose exec web pytest tests/unit/test_models.py -v
```

Run tests matching a keyword:
```bash
docker-compose exec web pytest -k "test_health" -v
```

### Flutter APK Build

The build number is tracked in two places that must stay in sync:
- `mobile/pubspec.yaml` — `version: 1.0.0+N` (the `+N` is Flutter's internal versionCode)
- The `--dart-define=BUILD_NUMBER=N` flag (displayed as `v1.0.N` in the app drawer)

**To build a new APK:**
1. Read the current build number `N` from `mobile/pubspec.yaml` (the number after the `+`)
2. Increment to `N+1` in both places: `version: 1.0.<N+1>+<N+1>` (e.g., `version: 1.0.28+28`)
3. Run: `cd mobile && flutter build apk --release --dart-define=BUILD_NUMBER=<N+1>`
4. Output: `mobile/build/app/outputs/flutter-apk/app-release.apk`

**Always increment the build number when building a new APK.** Never skip this step.

## Architecture

### Django Apps (under `apps/`)

- **core** — `BaseModel` abstract base (UUID PK, timestamps, soft delete via `is_active`), `ActiveManager`, landing page view, `seed_superusers` command
- **users** — Custom `User` model (email as USERNAME_FIELD, no password storage), `SocialAccount` model with encrypted OAuth tokens, social auth pipeline (`save_social_account`, `issue_jwt`)
- **lookup** — `LookupValue` universal reference data table with parent-child self-FK hierarchy. Single table for all reference data types
- **rbac** — `ControlPointGroup` → `ControlPoint` → `Role` → User. All admin CRUD views live here (superuser-only). Handles Users, Roles, Control Points, Groups, and Lookup Items
- **api** — `health_check` endpoint, `auth_callback` for JWT issuance, `agents/` (LangGraph state machine), `ai_utils.py` (multi-LLM init)
- **wineries** — `Place` (name, place_type, location, geo coords, metadata) and `MenuItem` (varietal, vintage, price, Pinecone vector ID)
- **visits** — `VisitLog` (user→place with multi-factor ratings: staff/ambience/food/overall) and `VisitWine` (items tasted per visit with notes)
- **trips** — `Trip` (M2M users via `TripMember`, itinerary JSON, status workflow), `TripStop` (ordered stops)
- **palate** — `PalateProfile` (one-to-one with User, structured preferences JSON, Pinecone vector ID)

### Settings

Environment-based settings in `config/settings/`: `base.py` (shared), `local.py` (dev), `dev.py` (AWS dev), `uat.py`, `prod.py`. All secrets from `.env` via `django-environ`.

### Templates

All templates extend `templates/base.html` (fixed navbar, pinnable sidenav, admin menu for superusers). Admin CRUD uses three generic templates: `admin/list.html`, `admin/form.html`, `admin/delete.html`.

### Frontend Libraries (loaded in base.html)

- **Materialize CSS 1.0.0** — CSS framework + Material Icons (CDN)
- **htmx 2.0.4** — Server-driven interactivity. Prefer htmx attributes (`hx-post`, `hx-get`, `hx-swap`, `hx-target`) over custom `fetch()` JS for any interaction that needs server data. CSRF token auto-attached via `htmx:configRequest` listener.
- **SortableJS 1.15.6** — Drag-and-drop reorder for lists (CDN)
- **Google Maps JavaScript API** — Maps with AdvancedMarkerElement + Places API (New)

### Docker Stack

`web` (Django :8000), `db` (PostgreSQL 16), `redis` (Redis 7), `worker` (Celery). Entrypoint waits for DB, runs migrations, collects static files.

## Model Conventions (Mandatory)

- **All models** inherit from `apps.core.models.BaseModel`
- **Primary keys**: UUID (never auto-increment)
- **Soft delete only**: Set `is_active=False`, never hard delete
- **Default manager** (`objects`) returns only active records; use `all_objects` for everything
- **Timestamps**: `created_at` and `updated_at` are auto-managed

## Data Grid Requirements (Mandatory)

Every list/table view must include: client-side search filtering, clickable sortable column headers with direction icons, pagination with size selector (10/25/50/100), and scrollable table body with sticky header.

## API Response Envelope

```json
{"success": true, "data": {}, "meta": {"page": 1, "total": 42}, "errors": []}
```

## Authentication

OAuth2 only (Google + Microsoft) — normal users have `set_unusable_password()`. Only seeded superusers have passwords for Django admin access. Social auth tokens are encrypted at rest via `django-encrypted-model-fields`.

## Testing

- Fixtures in `tests/conftest.py`: `api_client`, `user_factory`, `authenticated_client`, `lookup_factory`
- Factories in `tests/factories/factories.py`: `UserFactory`, `LookupValueFactory`
- Test directories: `unit/`, `feature/`, `integration/`

## AI / LangGraph Architecture

- **Multi-LLM**: `apps/api/ai_utils.py` — `get_claude()` (Claude Sonnet for reasoning), `get_claude_fast()` (Claude Haiku for trip planning tool-calling), and `get_gemini()` (Gemini 1.5 Pro for vision)
- **LangGraph**: `apps/api/agents/graph.py` — `VinoState` TypedDict tracks palate profile, trip context, messages, and working data. Two graphs: `palate` (analyze → search) and `trip` (aggregate → search → itinerary)
- **State persistence**: `langgraph-checkpoint-postgres` writes `VinoState` as JSONB after each node. Thread ID = user UUID or trip UUID. Django models are durable business records; graph state is agent working memory
- **Env vars**: `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY` (Gemini), `PINECONE_API_KEY`, `PINECONE_INDEX_NAME`

## Critical Rules

- **NEVER** modify, blank out, or replace values in `.env`, `.env.docker`, or `.env.example` — these contain pre-configured working credentials
- **ALWAYS** use `LookupValue` (parent-child hierarchy in `apps.lookup`) for dropdown/select lists instead of hardcoded `TextChoices` on models. This allows admins to manage list values through the Lookup Items admin UI without code changes. Use FK to `LookupValue` on the model, and filter by `parent__code` in forms. Status/workflow fields that drive code logic (e.g., `pending`/`approved`) are the exception — those stay as `TextChoices`.
- **ALL dates displayed in the UI** must use **MM/DD/YYYY** format. This applies everywhere: Trip Preview cards, list views, detail pages, chat messages, and both Flutter (mobile) and HTML (web) templates. In Flutter use `DateFormat('MM/dd/yyyy')` from `intl`; in Django templates use `{{ date|date:"m/d/Y" }}`; in JavaScript use `toLocaleDateString('en-US')` or equivalent.
- CI runs on every push: ruff check → mypy → pytest (see `.github/workflows/ci.yml`)
