from django.core.management.base import BaseCommand
from apps.lookup.models import LookupValue


LOOKUP_SEED = {
    'CUSTOMER_TYPE': ['Enterprise', 'SMB', 'Startup', 'Individual'],
    'EMPLOYEE_TYPE': ['Full-time', 'Part-time', 'Contractor', 'Intern'],
    'BUSINESS_CATEGORY': ['Financial Services', 'Healthcare', 'Technology', 'Retail'],
    'STATUS': ['Active', 'Inactive', 'Pending', 'Suspended'],
    # Wine drink types
    'WINE_TYPE': [
        'Red', 'White', 'Rosé', 'Sparkling', 'Dessert',
        'Fortified', 'Orange', 'Natural', 'Blend', 'Other',
    ],
    # Wine serving sizes
    'WINE_SERVING': [
        'Tasting', 'Glass', 'Flight', 'Half Bottle', 'Bottle', 'Split', 'Magnum',
    ],
    # Beer drink types
    'BEER_TYPE': [
        'IPA', 'Pale Ale', 'Lager', 'Pilsner', 'Stout', 'Porter',
        'Wheat', 'Sour', 'Amber', 'Brown Ale', 'Belgian',
        'Saison', 'Kolsch', 'Hazy IPA', 'Double IPA',
        'Cider', 'Mead', 'Seltzer', 'Other',
    ],
    # Beer serving sizes
    'BEER_SERVING': [
        'Tasting', 'Half Pint', 'Pint', 'Flight', 'Can', 'Bottle',
        'Crowler', 'Growler', 'Pitcher',
    ],
    # Promotion types (existing)
    'PROMOTION_TYPE': ['Discount', 'Event', 'Happy Hour', 'New Release', 'Seasonal'],
}


class Command(BaseCommand):
    help = "Seed the LookupValue table with default types and values (idempotent)"

    def handle(self, *args, **options):
        for type_code, values in LOOKUP_SEED.items():
            parent, created = LookupValue.all_objects.get_or_create(
                parent=None,
                code=type_code,
                defaults={'label': type_code.replace('_', ' ').title()},
            )
            status = "created" if created else "exists"
            self.stdout.write(f"  [{status}] Type: {type_code}")

            for i, val_label in enumerate(values):
                val_code = val_label.upper().replace(' ', '_').replace('-', '_')
                _, val_created = LookupValue.all_objects.get_or_create(
                    parent=parent,
                    code=val_code,
                    defaults={'label': val_label, 'sort_order': i},
                )
                if val_created:
                    self.stdout.write(self.style.SUCCESS(f"    [+] {val_label}"))

        self.stdout.write(self.style.SUCCESS("Lookup seed complete."))
