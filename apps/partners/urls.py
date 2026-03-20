from django.urls import path

from apps.partners.views import (
    AdminClaimEditView,
    AdminClaimListView,
    AdminPartnerCreateView,
    AdminPartnerEditView,
    AdminPartnerListView,
    AdminPromotionEditView,
    AdminPromotionListView,
    PartnerApplyView,
    PartnerClaimCreateView,
    PartnerClaimListView,
    PartnerDashboardView,
    PartnerProfileView,
    PartnerPromotionCreateView,
    PartnerPromotionEditView,
    PartnerPromotionListView,
)

# Partner portal URL patterns (included under /partners/)
partner_portal_patterns = [
    path("dashboard/", PartnerDashboardView.as_view(), name="partner_dashboard"),
    path("profile/", PartnerProfileView.as_view(), name="partner_profile"),
    path("claims/", PartnerClaimListView.as_view(), name="partner_claims"),
    path("claims/new/", PartnerClaimCreateView.as_view(), name="partner_claim_create"),
    path("promotions/", PartnerPromotionListView.as_view(), name="partner_promotions"),
    path("promotions/new/", PartnerPromotionCreateView.as_view(), name="partner_promotion_create"),
    path(
        "promotions/<uuid:pk>/edit/",
        PartnerPromotionEditView.as_view(),
        name="partner_promotion_edit",
    ),
    path("apply/", PartnerApplyView.as_view(), name="partner_apply"),
]

# Admin URL patterns (included under /manage/)
admin_patterns = [
    path("partners/", AdminPartnerListView.as_view(), name="admin_partners_list"),
    path("partners/create/", AdminPartnerCreateView.as_view(), name="admin_partners_create"),
    path(
        "partners/<uuid:pk>/edit/",
        AdminPartnerEditView.as_view(),
        name="admin_partners_edit",
    ),
    path("claims/", AdminClaimListView.as_view(), name="admin_claims_list"),
    path(
        "claims/<uuid:pk>/edit/",
        AdminClaimEditView.as_view(),
        name="admin_claims_edit",
    ),
    path("promotions/", AdminPromotionListView.as_view(), name="admin_promotions_list"),
    path(
        "promotions/<uuid:pk>/edit/",
        AdminPromotionEditView.as_view(),
        name="admin_promotions_edit",
    ),
]
