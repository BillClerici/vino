# GSD Framework -- Setup Prompts

These prompts are designed to be run sequentially in Claude Code (Cursor or CLI) after generating a project with `gsd-init.py`. The skeleton is already fully scaffolded -- config/, apps/, templates/, requirements/, docker/, migrations, Makefile, and docker-compose.yml are all in place.
---

## CRITICAL: .env Protection Rules

**These rules apply to every prompt and every phase below.**

> The .env, .env.docker, and .env.example files are pre-populated with real
> API keys for Google OAuth, Microsoft OAuth, Stripe, and LLM providers.
>
> **NEVER:**
> - Remove, blank out, or replace any existing key values in .env files
> - Replace real keys with placeholder text like "your-key-here" or "changeme"
> - Strip, redact, or "sanitize" key values for any reason
> - Modify any line in .env/.env.docker/.env.example that you did not explicitly add
>
> **ALWAYS:**
> - Preserve every existing key and value exactly as-is
> - If you need to add a new variable, append it -- never rewrite the file
> - If a setting references an env var, trust that the .env file already has it

---

## Phase 1 -- Verify the skeleton

### PROMPT 1: Install dependencies and verify
```
@PROJECT_SPEC.md

You are working on a Django application that has already been fully
scaffolded by the GSD framework generator. All files are in place:
config/, apps/, templates/, requirements/, docker/, migrations, etc.

CRITICAL: The .env file contains real API keys. NEVER remove, blank out,
or replace any existing values in .env, .env.docker, or .env.example.

Let's verify everything is wired up:

1. Create a Python virtual environment and activate it
2. pip install -r requirements/dev.txt
3. python manage.py migrate
4. python manage.py seed_lookups
5. python manage.py seed_superusers
6. python manage.py runserver

Confirm:
- Landing page loads at http://localhost:8000/
- Health check at http://localhost:8000/health/ returns {"status": "ok", "db": "ok"}
- Admin at http://localhost:8000/admin/ loads and you can log in with
  wildbill.clerici@gmail.com / admin123

Report any errors and fix them before moving on.
Do NOT modify any .env files.
```

---

## Phase 2 -- Add Login and Registration pages

### PROMPT 2: Create auth templates and views
```
@PROJECT_SPEC.md

CRITICAL: Do NOT modify .env, .env.docker, or .env.example files.
Preserve all existing key values exactly as-is.

Create a login page and a registration page using social auth (Google
and Microsoft OAuth2). No password fields -- all authentication is
via social providers only.

1. Create templates/auth/login.html:
   - Extends base.html
   - "Sign in with Google" button that links to /auth/login/google-oauth2/
   - "Sign in with Microsoft" button that links to /auth/login/microsoft-oauth2/
   - Clean card-based layout using Materialize CSS (consistent with base.html)
   - Link to registration page for new users

2. Create templates/auth/register.html:
   - Extends base.html
   - Same Google and Microsoft sign-in buttons (social auth creates the
     account automatically on first login)
   - Explanatory text: "Create your account by signing in with Google or Microsoft"
   - Link back to login page

3. Create apps/users/views.py with:
   - LoginView (TemplateView rendering auth/login.html)
   - RegisterView (TemplateView rendering auth/register.html)
   - LogoutView that clears the session and redirects to landing page

4. Update config/urls.py to add:
   - path('login/', LoginView.as_view(), name='login')
   - path('register/', RegisterView.as_view(), name='register')
   - path('logout/', LogoutView.as_view(), name='logout')

5. Update templates/base.html navbar to include:
   - Login link (when user is not authenticated)
   - Register link (when user is not authenticated)
   - Logout link (when user is authenticated)
   - Display user email when authenticated

6. Update the landing page to include a "Get Started" button that links
   to /register/ and a "Sign In" link that goes to /login/

7. Update config/settings/base.py:
   - Set LOGIN_URL = '/login/'
   - Set LOGIN_REDIRECT_URL = '/'
   - Set LOGOUT_REDIRECT_URL = '/'
   - Set SOCIAL_AUTH_LOGIN_REDIRECT_URL = '/'
   - Set SOCIAL_AUTH_NEW_USER_REDIRECT_URL = '/'

Make sure the social auth URLs from social_django are already wired up
in urls.py (path('auth/', include('social_django.urls', namespace='social'))).

Test that all pages render correctly at:
- http://localhost:8000/login/
- http://localhost:8000/register/
- http://localhost:8000/
```

---

## Phase 3 -- Docker verification

### PROMPT 3: Build and run Docker containers
```
CRITICAL: Do NOT modify .env, .env.docker, or .env.example files.

Build and start the Docker containers:

1. docker-compose build
2. docker-compose up -d
3. Verify all containers are running: docker-compose ps
4. Check logs for errors: docker-compose logs --tail=50
5. Confirm the app is accessible at http://localhost:8000/
6. Confirm health check returns OK
7. Run: docker-compose exec web python manage.py seed_lookups
8. Run: docker-compose exec web python manage.py seed_superusers

Report any errors. Do NOT modify .env files to fix issues -- if there
is an encoding or config problem, fix the code that reads the config,
not the config values themselves.
```

---

## Phase 4 -- Social login end-to-end test

### PROMPT 4: Test social login flow
```
CRITICAL: Do NOT modify .env, .env.docker, or .env.example files.

The Google and Microsoft OAuth credentials are already configured in
the .env file. Let's verify the social login flow works:

1. Navigate to http://localhost:8000/login/
2. Confirm both "Sign in with Google" and "Sign in with Microsoft"
   buttons are visible and link to the correct social auth URLs:
   - Google: /auth/login/google-oauth2/
   - Microsoft: /auth/login/microsoft-oauth2/
3. Verify the social_django URLs are properly included in config/urls.py
4. Check that SOCIAL_AUTH settings in config/settings/base.py reference
   the correct env vars (GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, etc.)
5. Verify the auth pipeline in settings includes our custom steps:
   - apps.users.pipeline.save_social_account
   - apps.users.pipeline.issue_jwt

If there are any issues with the OAuth flow, fix the Django code --
never modify the .env key values.
```

---

## Phase 5 -- Run tests

### PROMPT 5: Execute the test suite
```
Run the test suite and fix any failures:

1. pytest -v
2. Fix any failing tests
3. Run pytest --cov to check coverage

The test structure is:
  tests/unit/       -- model and service logic tests
  tests/feature/    -- endpoint and view tests
  tests/integration/ -- external service tests
  tests/factories/  -- factory-boy factories
```
