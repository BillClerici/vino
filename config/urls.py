from django.contrib import admin
from django.urls import include, path
from rest_framework_simplejwt.views import TokenRefreshView

from apps.api.views import auth_callback, health_check
from apps.core.views import AppSettingsView, LandingPageView
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
from apps.users.views import LoginView, LogoutView, RegisterView

urlpatterns = [
    path('admin/', admin.site.urls),
    path('health/', health_check, name='health_check'),
    path('api/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('auth/jwt-callback/', auth_callback, name='auth_jwt_callback'),
    path('', LandingPageView.as_view(), name='landing'),
    path('settings/', AppSettingsView.as_view(), name='app_settings'),
    path('login/', LoginView.as_view(), name='login'),
    path('register/', RegisterView.as_view(), name='register'),
    path('logout/', LogoutView.as_view(), name='logout'),
    # User-facing features
    path('places/', include('apps.wineries.urls')),
    path('visits/', include('apps.visits.urls')),
    path('trips/', include('apps.trips.urls')),
    path('palate/', include('apps.palate.urls')),
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
    path('auth/', include('social_django.urls', namespace='social')),
]
