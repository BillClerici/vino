from django.contrib import admin

from .models import Trip, TripMember, TripStop


class TripMemberInline(admin.TabularInline):
    model = TripMember
    extra = 0


class TripStopInline(admin.TabularInline):
    model = TripStop
    extra = 0


@admin.register(Trip)
class TripAdmin(admin.ModelAdmin):
    list_display = ("name", "created_by", "status", "scheduled_date", "is_active")
    list_filter = ("status", "is_active")
    search_fields = ("name",)
    inlines = [TripMemberInline, TripStopInline]
