from django.contrib import admin

from .models import MenuItem, Place


@admin.register(Place)
class PlaceAdmin(admin.ModelAdmin):
    list_display = ("name", "city", "state", "country", "is_active")
    list_filter = ("state", "country", "is_active")
    search_fields = ("name", "city")


@admin.register(MenuItem)
class MenuItemAdmin(admin.ModelAdmin):
    list_display = ("name", "varietal", "vintage", "place", "is_active")
    list_filter = ("varietal", "vintage", "is_active")
    search_fields = ("name", "varietal")
