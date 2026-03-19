from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model

User = get_user_model()

SUPERUSERS = [
    {"email": "wildbill.clerici@gmail.com", "password": "admin123", "first_name": "Bill", "last_name": "Clerici"},
    {"email": "micah.minarik@gmail.com", "password": "admin123", "first_name": "Micah", "last_name": "Minarik"},
    {"email": "bill@1200investing.com", "password": "admin123", "first_name": "Bill", "last_name": "Clerici"},
    {"email": "micah@1200investing.com", "password": "admin123", "first_name": "Micah", "last_name": "Minarik"},
]


class Command(BaseCommand):
    help = "Create default superuser accounts (idempotent - skips existing)"

    def handle(self, *args, **options):
        for user_data in SUPERUSERS:
            email = user_data["email"]
            if User.objects.filter(email=email).exists():
                self.stdout.write(f"  [=] {email} already exists - skipped")
                continue
            user = User.objects.create_superuser(
                email=email,
                first_name=user_data.get("first_name", ""),
                last_name=user_data.get("last_name", ""),
            )
            # Set password for admin access (superusers are the only exception to no-password rule)
            user.set_password(user_data["password"])
            user.save(update_fields=["password"])
            self.stdout.write(self.style.SUCCESS(f"  [+] Created superuser: {email}"))
