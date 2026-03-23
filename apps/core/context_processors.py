def app_version_context(request):
    """Add app version to template context."""
    from django.conf import settings
    return {"app_version": getattr(settings, "APP_VERSION_FULL", "v0.0.0")}


def partner_context(request):
    """Add is_approved_partner flag to template context."""
    if not request.user.is_authenticated:
        return {"is_approved_partner": False}

    from apps.partners.models import Partner, PartnerOwner

    is_partner = PartnerOwner.objects.filter(
        user=request.user,
        is_active=True,
        partner__status=Partner.Status.APPROVED,
        partner__is_active=True,
    ).exists()
    return {"is_approved_partner": is_partner}
