from django.contrib import admin

from .models import Wine, Winery


@admin.register(Winery)
class WineryAdmin(admin.ModelAdmin):
    list_display = ("name", "city", "state", "country", "is_active")
    list_filter = ("state", "country", "is_active")
    search_fields = ("name", "city")


@admin.register(Wine)
class WineAdmin(admin.ModelAdmin):
    list_display = ("name", "varietal", "vintage", "winery", "is_active")
    list_filter = ("varietal", "vintage", "is_active")
    search_fields = ("name", "varietal")
