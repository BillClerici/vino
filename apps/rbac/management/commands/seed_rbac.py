from django.core.management.base import BaseCommand
from apps.rbac.models import ControlPointGroup, ControlPoint, Role


# Control Point Groups and their CRUD control points
SEED_DATA = {
    "User Management": {
        "prefix": "USER",
        "control_points": ["ADD", "UPDATE", "DELETE", "VIEW"],
    },
    "Role Management": {
        "prefix": "ROLE",
        "control_points": ["ADD", "UPDATE", "DELETE", "VIEW"],
    },
    "Control Point Management": {
        "prefix": "CONTROL_POINT",
        "control_points": ["ADD", "UPDATE", "DELETE", "VIEW"],
    },
    "Control Point Group Management": {
        "prefix": "CP_GROUP",
        "control_points": ["ADD", "UPDATE", "DELETE", "VIEW"],
    },
    "Lookup Item Management": {
        "prefix": "LOOKUP",
        "control_points": ["ADD", "UPDATE", "DELETE", "VIEW"],
    },
}

# Roles and which control points they get (by code prefix pattern)
ROLES = {
    "Admin": "*",           # All control points
    "Power User": None,     # No default CPs — assign manually
    "Guest": None,          # No default CPs — assign manually
}


class Command(BaseCommand):
    help = "Seed RBAC: control point groups, control points, and roles (idempotent)"

    def handle(self, *args, **options):
        all_cps = []

        # Create groups and control points
        for group_name, config in SEED_DATA.items():
            group, created = ControlPointGroup.all_objects.get_or_create(
                name=group_name,
                defaults={"description": f"Manage {group_name.lower()}"},
            )
            status = "created" if created else "exists"
            self.stdout.write(f"  [{status}] Group: {group_name}")

            prefix = config["prefix"]
            for i, action in enumerate(config["control_points"]):
                code = f"{prefix}_{action}"
                label = f"Can {action.replace('_', ' ').title()} {group_name.replace(' Management', '')}"
                cp, cp_created = ControlPoint.all_objects.get_or_create(
                    code=code,
                    defaults={
                        "group": group,
                        "label": label,
                        "description": f"{label} in the system",
                    },
                )
                all_cps.append(cp)
                if cp_created:
                    self.stdout.write(self.style.SUCCESS(f"    [+] {code}: {label}"))

        # Create roles
        for role_name, cp_assignment in ROLES.items():
            role, created = Role.all_objects.get_or_create(
                name=role_name,
                defaults={"description": f"{role_name} role"},
            )
            status = "created" if created else "exists"
            self.stdout.write(f"  [{status}] Role: {role_name}")

            # Assign control points
            if cp_assignment == "*" and created:
                role.control_points.set(all_cps)
                self.stdout.write(self.style.SUCCESS(
                    f"    [+] Assigned all {len(all_cps)} control points to {role_name}"
                ))
            elif cp_assignment == "*" and not created:
                # Ensure Admin always has all CPs even on re-run
                existing = set(role.control_points.values_list("pk", flat=True))
                new_cps = [cp for cp in all_cps if cp.pk not in existing]
                if new_cps:
                    role.control_points.add(*new_cps)
                    self.stdout.write(self.style.SUCCESS(
                        f"    [+] Added {len(new_cps)} new control points to {role_name}"
                    ))

        # Assign Admin role to all superusers
        admin_role = Role.all_objects.filter(name="Admin").first()
        if admin_role:
            from django.contrib.auth import get_user_model
            User = get_user_model()
            superusers = User.objects.filter(is_superuser=True)
            for su in superusers:
                if not su.roles.filter(pk=admin_role.pk).exists():
                    su.roles.add(admin_role)
                    self.stdout.write(self.style.SUCCESS(
                        f"    [+] Assigned Admin role to superuser: {su.email}"
                    ))

        self.stdout.write(self.style.SUCCESS("RBAC seed complete."))
