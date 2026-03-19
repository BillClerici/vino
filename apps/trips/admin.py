from django.contrib import admin

from .models import Trip, TripMember, TripWinery


class TripMemberInline(admin.TabularInline):
    model = TripMember
    extra = 0


class TripWineryInline(admin.TabularInline):
    model = TripWinery
    extra = 0


@admin.register(Trip)
class TripAdmin(admin.ModelAdmin):
    list_display = ("name", "created_by", "status", "scheduled_date", "is_active")
    list_filter = ("status", "is_active")
    search_fields = ("name",)
    inlines = [TripMemberInline, TripWineryInline]
