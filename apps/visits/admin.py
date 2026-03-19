from django.contrib import admin

from .models import VisitLog, VisitWine


class VisitWineInline(admin.TabularInline):
    model = VisitWine
    extra = 0


@admin.register(VisitLog)
class VisitLogAdmin(admin.ModelAdmin):
    list_display = ("user", "place", "visited_at", "rating_overall", "is_active")
    list_filter = ("rating_overall", "is_active")
    search_fields = ("user__email", "place__name")
    inlines = [VisitWineInline]
