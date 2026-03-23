from django.contrib import admin

from apps.lookup.models import LookupValue


@admin.register(LookupValue)
class LookupValueAdmin(admin.ModelAdmin):
    list_display = ('label', 'code', 'parent', 'sort_order', 'is_active')
    list_filter = ('parent', 'is_active')
    search_fields = ('code', 'label')
    ordering = ('parent', 'sort_order', 'label')
