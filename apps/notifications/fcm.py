"""Firebase Cloud Messaging helper — FCM HTTP v1 API.

Sends push notifications via the modern FCM v1 API using Google OAuth2
credentials. Supports Application Default Credentials (gcloud auth for
local dev) and service account JSON (GOOGLE_APPLICATION_CREDENTIALS for
production).

If credentials are unavailable, notifications are still stored in the
database and visible in-app — push delivery is just skipped.
"""

import json
import logging

import httpx
from google.auth.transport.requests import Request
from google.oauth2 import service_account

logger = logging.getLogger(__name__)

FCM_SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]

# Module-level cached credentials — refreshed automatically when expired.
_credentials = None


def _get_credentials():
    """Return cached OAuth2 credentials, creating/refreshing as needed."""
    global _credentials

    from django.conf import settings

    if _credentials is not None and _credentials.valid:
        return _credentials

    if _credentials is not None and _credentials.expired:
        _credentials.refresh(Request())
        return _credentials

    # Option 1: Service account JSON from env var (base64 or file path)
    sa_json = getattr(settings, "FCM_SERVICE_ACCOUNT_JSON", "")
    if sa_json:
        try:
            info = json.loads(sa_json)
            _credentials = service_account.Credentials.from_service_account_info(
                info, scopes=FCM_SCOPES
            )
            _credentials.refresh(Request())
            return _credentials
        except Exception:
            logger.exception("Failed to load FCM service account from JSON")
            return None

    # Option 2: Application Default Credentials (gcloud auth / GOOGLE_APPLICATION_CREDENTIALS)
    try:
        import google.auth

        _credentials, _ = google.auth.default(scopes=FCM_SCOPES)
        _credentials.refresh(Request())
        return _credentials
    except Exception:
        logger.debug(
            "No Google credentials available — push delivery disabled (in-app only)"
        )
        return None


def send_fcm_message(
    token: str, title: str, body: str, data: dict | None = None
) -> bool:
    """Send a push notification to a single device token via FCM v1 API.

    Returns True if sent successfully, False if the token is invalid/expired.
    Returns True (no-op) if credentials are not available — the notification
    is still stored in the database by the caller.
    """
    from django.conf import settings

    firebase_project_id = getattr(settings, "FIREBASE_PROJECT_ID", "")
    if not firebase_project_id:
        logger.debug("FIREBASE_PROJECT_ID not set — push delivery skipped")
        return True

    creds = _get_credentials()
    if creds is None:
        return True  # Graceful degradation — in-app only

    url = (
        f"https://fcm.googleapis.com/v1/projects/{firebase_project_id}"
        f"/messages:send"
    )

    payload = {
        "message": {
            "token": token,
            "notification": {
                "title": title,
                "body": body,
            },
            "android": {
                "priority": "HIGH",
                "notification": {
                    "channel_id": "vino_default",
                    "sound": "default",
                },
            },
            "data": {k: str(v) for k, v in (data or {}).items()},
        }
    }

    try:
        with httpx.Client(timeout=10) as client:
            resp = client.post(
                url,
                headers={
                    "Authorization": f"Bearer {creds.token}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )

        if resp.status_code == 200:
            return True

        error = resp.json().get("error", {})
        error_code = error.get("status", "")
        details = error.get("details", [])

        # Extract FCM-specific error code from details
        fcm_error = ""
        for detail in details:
            if detail.get("errorCode"):
                fcm_error = detail["errorCode"]
                break

        # Token is invalid or unregistered — caller should deactivate it
        if fcm_error in ("UNREGISTERED", "INVALID_ARGUMENT") or error_code in (
            "NOT_FOUND",
            "INVALID_ARGUMENT",
        ):
            logger.info(
                "FCM token invalid (%s / %s): %s...",
                error_code,
                fcm_error,
                token[:20],
            )
            return False

        # Sender ID mismatch
        if fcm_error == "SENDER_ID_MISMATCH":
            logger.warning("FCM sender ID mismatch for token: %s...", token[:20])
            return False

        logger.warning(
            "FCM v1 API error (HTTP %d): %s", resp.status_code, error
        )
        return False

    except Exception:
        logger.exception("FCM send failed for token: %s...", token[:20])
        return False
