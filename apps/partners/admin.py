from django.contrib import admin

from apps.partners.models import Partner, PlaceClaim, Promotion, PromotionImpression


@admin.register(Partner)
class PartnerAdmin(admin.ModelAdmin):
    list_display = ("business_name", "user", "tier", "status", "created_at")
    list_filter = ("tier", "status")
    search_fields = ("business_name", "user__email")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(PlaceClaim)
class PlaceClaimAdmin(admin.ModelAdmin):
    list_display = ("partner", "place", "status", "claimed_at")
    list_filter = ("status",)
    search_fields = ("partner__business_name", "place__name")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(Promotion)
class PromotionAdmin(admin.ModelAdmin):
    list_display = ("name", "partner", "place", "promotion_type", "status", "start_date", "end_date")
    list_filter = ("promotion_type", "status")
    search_fields = ("name", "partner__business_name", "place__name")
    readonly_fields = ("id", "created_at", "updated_at")


@admin.register(PromotionImpression)
class PromotionImpressionAdmin(admin.ModelAdmin):
    list_display = ("promotion", "user", "impression_type", "context", "created_at")
    list_filter = ("impression_type",)
    readonly_fields = ("id", "created_at", "updated_at")
