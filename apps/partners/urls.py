from django.urls import path

from apps.partners.subscription_views import (
    AdminPartnerCheckoutView,
    AdminPartnerStripePortalView,
    AdminPartnerSubscriptionView,
    PartnerCheckoutSuccessView,
    PartnerCheckoutView,
    PartnerPortalView,
    PartnerPricingView,
)
from apps.partners.views import (
    AdminClaimEditView,
    AdminClaimListView,
    AdminPartnerAddOwnerView,
    AdminPartnerCreateView,
    AdminPartnerDecisionView,
    AdminPartnerEditView,
    AdminPartnerListView,
    AdminPartnerRemoveOwnerView,
    AdminPartnerUpdateOwnerView,
    AdminPromotionEditView,
    AdminPromotionListView,
    AdminUserSearchView,
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
    path("subscription/", PartnerPricingView.as_view(), name="partner_pricing"),
    path("subscription/checkout/", PartnerCheckoutView.as_view(), name="partner_checkout"),
    path("subscription/success/", PartnerCheckoutSuccessView.as_view(), name="partner_checkout_success"),
    path("subscription/portal/", PartnerPortalView.as_view(), name="partner_portal"),
]

# Admin URL patterns (included under /manage/)
admin_patterns = [
    path("partners/", AdminPartnerListView.as_view(), name="admin_partners_list"),
    path("partners/create/", AdminPartnerCreateView.as_view(), name="admin_partners_create"),
    path("partners/<uuid:pk>/edit/", AdminPartnerEditView.as_view(), name="admin_partners_edit"),
    path("partners/<uuid:pk>/decision/", AdminPartnerDecisionView.as_view(), name="admin_partner_decision"),
    path("partners/<uuid:pk>/owners/add/", AdminPartnerAddOwnerView.as_view(), name="admin_partner_add_owner"),
    path("partners/<uuid:pk>/owners/<uuid:owner_pk>/update/", AdminPartnerUpdateOwnerView.as_view(), name="admin_partner_update_owner"),
    path("partners/<uuid:pk>/owners/<uuid:owner_pk>/remove/", AdminPartnerRemoveOwnerView.as_view(), name="admin_partner_remove_owner"),
    path("partners/<uuid:pk>/subscription/", AdminPartnerSubscriptionView.as_view(), name="admin_partner_subscription"),
    path("partners/<uuid:pk>/subscription/checkout/", AdminPartnerCheckoutView.as_view(), name="admin_partner_checkout"),
    path("partners/<uuid:pk>/subscription/portal/", AdminPartnerStripePortalView.as_view(), name="admin_partner_stripe_portal"),
    path("users/search/", AdminUserSearchView.as_view(), name="admin_user_search"),
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
