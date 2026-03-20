from django.core.management import call_command
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = "Load golden seed data (users, RBAC, lookups) from fixtures/seed_data.json"

    def handle(self, *args, **options):
        self.stdout.write("Loading seed data from fixtures/seed_data.json...")
        call_command("loaddata", "fixtures/seed_data.json", verbosity=1)
        self.stdout.write(self.style.SUCCESS("Seed data loaded successfully."))
        self.stdout.write("")
        self.stdout.write("  Included: Users, Roles, Control Points, CP Groups, Lookups")
        self.stdout.write("  Run 'make seed' to ensure all seed commands are up to date.")
