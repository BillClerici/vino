from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView
from rest_framework_simplejwt.views import TokenRefreshView

from apps.api.views import auth_callback, health_check
from apps.core.feature_views import (
    BadgesView,
    CellarView,
    JourneyMapView,
    SippyChatView,
    SippyHistoryView,
    SippyPlannerView,
    HelpView,
    TripRecapView,
    UpdateOnboardingView,
    WishlistView,
)
from apps.core.views import AppSettingsView, LandingPageView, SetTimezoneView
from apps.partners.urls import admin_patterns as partner_admin_patterns
from apps.partners.urls import partner_portal_patterns
from apps.rbac.views import (
    ControlPointCreateView,
    ControlPointDeleteView,
    ControlPointEditView,
    ControlPointGroupCreateView,
    ControlPointGroupDeleteView,
    ControlPointGroupEditView,
    ControlPointGroupListView,
    ControlPointListView,
    LookupCreateView,
    LookupDeleteView,
    LookupEditView,
    LookupListView,
    RoleCreateView,
    RoleDeleteView,
    RoleEditView,
    RoleListView,
    UserCreateView,
    UserDeleteView,
    UserEditView,
    UserListView,
)
from apps.users.subscription_views import (
    CheckoutSuccessView,
    CreateCheckoutSessionView,
    CustomerPortalView,
    PricingView,
    StripeWebhookView,
)
from apps.users.views import LoginView, LogoutView, ProfileView, RegisterView
from apps.wineries.views import (
    PlaceAdminCreateView,
    PlaceAdminDeleteView,
    PlaceAdminEditView,
    PlaceAdminListView,
)

urlpatterns = [
    path('admin/', admin.site.urls),
    path('health/', health_check, name='health_check'),
    # REST API v1
    path('api/v1/', include('apps.api.v1.urls')),
    path('api/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('auth/jwt-callback/', auth_callback, name='auth_jwt_callback'),
    path('', LandingPageView.as_view(), name='landing'),
    path('settings/', AppSettingsView.as_view(), name='app_settings'),
    path('api/set-timezone/', SetTimezoneView.as_view(), name='set_timezone'),
    path('login/', LoginView.as_view(), name='login'),
    path('register/', RegisterView.as_view(), name='register'),
    path('logout/', LogoutView.as_view(), name='logout'),
    path('profile/', ProfileView.as_view(), name='profile'),
    # Subscription
    path('subscription/pricing/', PricingView.as_view(), name='pricing'),
    path('subscription/create-checkout/', CreateCheckoutSessionView.as_view(), name='create_checkout'),
    path('subscription/success/', CheckoutSuccessView.as_view(), name='checkout_success'),
    path('subscription/portal/', CustomerPortalView.as_view(), name='customer_portal'),
    path('subscription/webhook/', StripeWebhookView.as_view(), name='stripe_webhook'),
    # New feature pages (synced from mobile)
    path('wishlist/', WishlistView.as_view(), name='wishlist_list'),
    path('cellar/', CellarView.as_view(), name='cellar_view'),
    path('badges/', BadgesView.as_view(), name='badges_view'),
    path('journey/', JourneyMapView.as_view(), name='journey_map'),
    path('trips/<uuid:pk>/recap/', TripRecapView.as_view(), name='trip_recap'),
    path('sippy/', SippyPlannerView.as_view(), name='sippy_planner'),
    path('sippy/chat/', SippyChatView.as_view(), name='sippy_chat'),
    path('sippy/chat/<uuid:trip_pk>/', SippyChatView.as_view(), name='sippy_trip_chat'),
    path('sippy/history/', SippyHistoryView.as_view(), name='sippy_history'),
    path('help/', HelpView.as_view(), name='help_guide'),
    path('onboarding/update/', UpdateOnboardingView.as_view(), name='update_onboarding'),
    # User-facing features
    path('places/', include('apps.wineries.urls')),
    path('visits/', include('apps.visits.urls')),
    path('trips/', include('apps.trips.urls')),
    path('palate/', include('apps.palate.urls')),
    path('partners/', include(partner_portal_patterns)),
    # Admin CRUD (HTML views)
    path('manage/users/', UserListView.as_view(), name='admin_users_list'),
    path('manage/users/create/', UserCreateView.as_view(), name='admin_users_create'),
    path('manage/users/<uuid:pk>/edit/', UserEditView.as_view(), name='admin_users_edit'),
    path('manage/users/<uuid:pk>/delete/', UserDeleteView.as_view(), name='admin_users_delete'),
    path('manage/roles/', RoleListView.as_view(), name='admin_roles_list'),
    path('manage/roles/create/', RoleCreateView.as_view(), name='admin_roles_create'),
    path('manage/roles/<uuid:pk>/edit/', RoleEditView.as_view(), name='admin_roles_edit'),
    path('manage/roles/<uuid:pk>/delete/', RoleDeleteView.as_view(), name='admin_roles_delete'),
    path('manage/controlpoints/', ControlPointListView.as_view(), name='admin_controlpoints_list'),
    path('manage/controlpoints/create/', ControlPointCreateView.as_view(), name='admin_controlpoints_create'),
    path('manage/controlpoints/<uuid:pk>/edit/', ControlPointEditView.as_view(), name='admin_controlpoints_edit'),
    path('manage/controlpoints/<uuid:pk>/delete/', ControlPointDeleteView.as_view(), name='admin_controlpoints_delete'),
    path('manage/cpgroups/', ControlPointGroupListView.as_view(), name='admin_cpgroups_list'),
    path('manage/cpgroups/create/', ControlPointGroupCreateView.as_view(), name='admin_cpgroups_create'),
    path('manage/cpgroups/<uuid:pk>/edit/', ControlPointGroupEditView.as_view(), name='admin_cpgroups_edit'),
    path('manage/cpgroups/<uuid:pk>/delete/', ControlPointGroupDeleteView.as_view(), name='admin_cpgroups_delete'),
    path('manage/lookups/', LookupListView.as_view(), name='admin_lookups_list'),
    path('manage/lookups/create/', LookupCreateView.as_view(), name='admin_lookups_create'),
    path('manage/lookups/<uuid:pk>/edit/', LookupEditView.as_view(), name='admin_lookups_edit'),
    path('manage/lookups/<uuid:pk>/delete/', LookupDeleteView.as_view(), name='admin_lookups_delete'),
    # App Admin (superuser)
    path('manage/places/', PlaceAdminListView.as_view(), name='admin_places_list'),
    path('manage/places/create/', PlaceAdminCreateView.as_view(), name='admin_places_create'),
    path('manage/places/<uuid:pk>/edit/', PlaceAdminEditView.as_view(), name='admin_places_edit'),
    path('manage/places/<uuid:pk>/delete/', PlaceAdminDeleteView.as_view(), name='admin_places_delete'),
    # Partner admin
    path('manage/', include(partner_admin_patterns)),
    path('auth/', include('social_django.urls', namespace='social')),
    # OpenAPI documentation
    path('api/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
