from urllib.parse import urlencode
from django.http import HttpResponseRedirect
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response


@api_view(['GET'])
@permission_classes([AllowAny])
def health_check(request):
    from django.db import connection
    checks = {'status': 'ok', 'db': 'ok'}
    try:
        connection.ensure_connection()
    except Exception:
        checks['db'] = 'error'
        checks['status'] = 'degraded'
    return Response(checks, status=200 if checks['status'] == 'ok' else 503)


def auth_callback(request):
    """
    After social auth completes, redirect to the frontend with JWT tokens.
    The pipeline stores tokens in the session. This view picks them up
    and passes them to the SPA via URL query params.
    """
    access = request.session.pop('jwt_access', '')
    refresh = request.session.pop('jwt_refresh', '')
    if access:
        params = urlencode({'access_token': access, 'refresh_token': refresh})
        return HttpResponseRedirect(f'/login/callback?{params}')
    # Fallback: no tokens (pipeline didn't run or session lost)
    return HttpResponseRedirect('/')
