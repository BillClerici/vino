from django.core.management.base import BaseCommand

from apps.lookup.models import LookupValue
from apps.rbac.models import ControlPoint, ControlPointGroup, Role


LOOKUP_TYPES = [
    {
        "code": "PARTNER_TIER",
        "label": "Partner Tier",
        "description": "Partnership subscription tiers",
        "children": [
            {"code": "FREE", "label": "Free", "sort_order": 1, "metadata": {"max_claims": 1, "max_promotions": 0}},
            {"code": "SILVER", "label": "Silver", "sort_order": 2, "metadata": {"max_claims": 1, "max_promotions": 2}},
            {"code": "GOLD", "label": "Gold", "sort_order": 3, "metadata": {"max_claims": 3, "max_promotions": 10}},
            {"code": "PLATINUM", "label": "Platinum", "sort_order": 4, "metadata": {"max_claims": -1, "max_promotions": -1}},
        ],
    },
    {
        "code": "PROMOTION_TYPE",
        "label": "Promotion Type",
        "description": "Types of partner promotions",
        "children": [
            {"code": "FEATURED_LISTING", "label": "Featured Listing", "sort_order": 1},
            {"code": "DISCOVER_SPOTLIGHT", "label": "Discover Spotlight", "sort_order": 2},
            {"code": "TRIP_SUGGESTION", "label": "Trip Suggestion", "sort_order": 3},
            {"code": "SPECIAL_OFFER", "label": "Special Offer", "sort_order": 4},
            {"code": "EVENT", "label": "Event", "sort_order": 5},
        ],
    },
]


CONTROL_POINTS = [
    {"code": "partner.view", "label": "Can View Partners"},
    {"code": "partner.approve", "label": "Can Approve Partners"},
    {"code": "partner.edit", "label": "Can Edit Partners"},
    {"code": "claim.view", "label": "Can View Claims"},
    {"code": "claim.approve", "label": "Can Approve Claims"},
    {"code": "promotion.view", "label": "Can View Promotions"},
    {"code": "promotion.approve", "label": "Can Approve Promotions"},
]


class Command(BaseCommand):
    help = "Seed Partner RBAC: control point group, control points, and roles (idempotent)"

    def handle(self, *args, **options):
        # Create the Partnerships group
        group, created = ControlPointGroup.all_objects.get_or_create(
            name="Partnerships",
            defaults={
                "description": "Partner management control points",
                "sort_order": 30,
            },
        )
        status = "created" if created else "exists"
        self.stdout.write(f"  [{status}] Group: Partnerships")

        # Create control points
        cps = []
        for cp_data in CONTROL_POINTS:
            cp, cp_created = ControlPoint.all_objects.get_or_create(
                code=cp_data["code"],
                defaults={
                    "group": group,
                    "label": cp_data["label"],
                    "description": cp_data["label"],
                },
            )
            cps.append(cp)
            if cp_created:
                self.stdout.write(self.style.SUCCESS(f"    [+] {cp.code}: {cp.label}"))
            else:
                self.stdout.write(f"    [exists] {cp.code}")

        # Create Partner Manager role with all partnership CPs
        manager_role, created = Role.all_objects.get_or_create(
            name="Partner Manager",
            defaults={"description": "Can manage partners, claims, and promotions"},
        )
        status = "created" if created else "exists"
        self.stdout.write(f"  [{status}] Role: Partner Manager")

        existing = set(manager_role.control_points.values_list("pk", flat=True))
        new_cps = [cp for cp in cps if cp.pk not in existing]
        if new_cps:
            manager_role.control_points.add(*new_cps)
            self.stdout.write(self.style.SUCCESS(
                f"    [+] Assigned {len(new_cps)} control points to Partner Manager"
            ))

        # Create Partner role (portal access, no admin CPs)
        partner_role, created = Role.all_objects.get_or_create(
            name="Partner",
            defaults={"description": "Partner portal access role"},
        )
        status = "created" if created else "exists"
        self.stdout.write(f"  [{status}] Role: Partner")

        # Seed lookup values
        self.stdout.write("")
        for ltype in LOOKUP_TYPES:
            parent, created = LookupValue.all_objects.get_or_create(
                parent=None,
                code=ltype["code"],
                defaults={
                    "label": ltype["label"],
                    "description": ltype.get("description", ""),
                },
            )
            status = "created" if created else "exists"
            self.stdout.write(f"  [{status}] Lookup Type: {ltype['label']}")
            for child in ltype["children"]:
                lv, lv_created = LookupValue.all_objects.get_or_create(
                    parent=parent,
                    code=child["code"],
                    defaults={
                        "label": child["label"],
                        "sort_order": child.get("sort_order", 0),
                        "metadata": child.get("metadata", {}),
                    },
                )
                if lv_created:
                    self.stdout.write(self.style.SUCCESS(f"    [+] {child['code']}: {child['label']}"))
                else:
                    self.stdout.write(f"    [exists] {child['code']}")

        self.stdout.write(self.style.SUCCESS("Partner RBAC seed complete."))
