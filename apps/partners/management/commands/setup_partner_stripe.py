"""
Create Partner subscription Products and Prices in Stripe.
Run once to set up, then copy the output Price IDs into .env.
Safe to re-run — will find existing products by metadata tag.
"""

import stripe
from django.conf import settings
from django.core.management.base import BaseCommand

PARTNER_PRODUCTS = [
    {
        "tier": "silver",
        "name": "Vino Partner — Silver",
        "description": "1 place, 2 promotions/month, views + clicks analytics",
        "monthly_price": 4900,  # cents
        "yearly_price": 46800,  # $39/mo * 12 = $468
    },
    {
        "tier": "gold",
        "name": "Vino Partner — Gold",
        "description": "3 places, 10 promotions/month, full analytics, featured badge",
        "monthly_price": 9900,
        "yearly_price": 94800,  # $79/mo * 12 = $948
    },
    {
        "tier": "platinum",
        "name": "Vino Partner — Platinum",
        "description": "Unlimited places & promotions, full analytics + export, trip recommendations",
        "monthly_price": 19900,
        "yearly_price": 190800,  # $159/mo * 12 = $1908
    },
]


class Command(BaseCommand):
    help = "Create Partner subscription Products and Prices in Stripe"

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Show what would be created without making Stripe API calls",
        )

    def handle(self, *args, **options):
        api_key = settings.STRIPE_SECRET_KEY
        if not api_key:
            self.stderr.write(self.style.ERROR("STRIPE_SECRET_KEY not configured"))
            return

        stripe.api_key = api_key
        dry_run = options["dry_run"]

        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS("=== Vino Partner Stripe Setup ==="))
        self.stdout.write("")

        env_lines = []

        for product_def in PARTNER_PRODUCTS:
            tier = product_def["tier"]
            name = product_def["name"]

            self.stdout.write(f"  Product: {name}")

            if dry_run:
                self.stdout.write(f"    [DRY RUN] Would create product + 2 prices")
                env_lines.append(f"STRIPE_PARTNER_{tier.upper()}_MONTHLY_PRICE_ID=price_xxx")
                env_lines.append(f"STRIPE_PARTNER_{tier.upper()}_YEARLY_PRICE_ID=price_xxx")
                continue

            # Check if product already exists (by metadata)
            existing = stripe.Product.list(limit=100)
            product = None
            for p in existing.data:
                if p.metadata.get("vino_partner_tier") == tier:
                    product = p
                    self.stdout.write(f"    [exists] Product: {p.id}")
                    break

            if not product:
                product = stripe.Product.create(
                    name=name,
                    description=product_def["description"],
                    metadata={"vino_partner_tier": tier, "type": "partner"},
                )
                self.stdout.write(self.style.SUCCESS(f"    [created] Product: {product.id}"))

            # Check/create monthly price
            monthly_price = self._find_or_create_price(
                product.id, tier, "monthly",
                product_def["monthly_price"], "month",
            )
            env_lines.append(
                f"STRIPE_PARTNER_{tier.upper()}_MONTHLY_PRICE_ID={monthly_price.id}"
            )

            # Check/create yearly price
            yearly_price = self._find_or_create_price(
                product.id, tier, "yearly",
                product_def["yearly_price"], "year",
            )
            env_lines.append(
                f"STRIPE_PARTNER_{tier.upper()}_YEARLY_PRICE_ID={yearly_price.id}"
            )

        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS("=== Add these to your .env file ==="))
        self.stdout.write("")
        for line in env_lines:
            self.stdout.write(f"  {line}")
        self.stdout.write("")

    def _find_or_create_price(self, product_id, tier, period, amount, interval):
        """Find existing price by metadata or create a new one."""
        existing_prices = stripe.Price.list(product=product_id, active=True, limit=20)
        for price in existing_prices.data:
            if (
                price.recurring
                and price.recurring.interval == interval
                and price.unit_amount == amount
            ):
                self.stdout.write(f"    [exists] {period} price: {price.id} (${amount / 100:.2f}/{interval})")
                return price

        price = stripe.Price.create(
            product=product_id,
            unit_amount=amount,
            currency="usd",
            recurring={"interval": interval},
            metadata={"vino_partner_tier": tier, "period": period},
        )
        self.stdout.write(
            self.style.SUCCESS(f"    [created] {period} price: {price.id} (${amount / 100:.2f}/{interval})")
        )
        return price
