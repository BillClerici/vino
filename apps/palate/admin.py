from django.contrib import admin

from .models import PalateProfile


@admin.register(PalateProfile)
class PalateProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "last_analyzed_at", "analysis_version", "is_active")
    search_fields = ("user__email",)
