from django.contrib import admin

from .models import DeviceToken, Notification, NotificationPreference

admin.site.register(DeviceToken)
admin.site.register(Notification)
admin.site.register(NotificationPreference)
