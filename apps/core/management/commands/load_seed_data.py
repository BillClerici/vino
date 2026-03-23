"""
Load seed data from seed_data.json into the database.

Usage:
    python manage.py load_seed_data
    python manage.py load_seed_data --clear  # Clear existing data first
"""

from django.core.management import call_command
from django.core.management.base import BaseCommand


class Command(BaseCommand):
    help = "Load seed data from seed_data.json"

    def add_arguments(self, parser):
        parser.add_argument(
            "--clear",
            action="store_true",
            help="Flush the database before loading seed data",
        )
        parser.add_argument(
            "--file",
            default="seed_data.json",
            help="Path to seed data JSON file (default: seed_data.json)",
        )

    def handle(self, *args, **options):
        if options["clear"]:
            self.stdout.write("Flushing database...")
            call_command("flush", "--no-input")
            self.stdout.write(self.style.SUCCESS("Database flushed."))

        seed_file = options["file"]
        self.stdout.write(f"Loading seed data from {seed_file}...")
        call_command("loaddata", seed_file)
        self.stdout.write(self.style.SUCCESS("Seed data loaded successfully."))
