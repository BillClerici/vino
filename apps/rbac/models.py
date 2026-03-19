from django.db import models
from apps.core.models import BaseModel


class ControlPointGroup(BaseModel):
    """
    Groups control points by entity/feature area.
    E.g. "Products", "Orders", "Reports"
    """
    name = models.CharField(max_length=100, unique=True)
    description = models.TextField(blank=True)
    sort_order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ['sort_order', 'name']
        db_table = 'rbac_control_point_group'

    def __str__(self):
        return self.name


class ControlPoint(BaseModel):
    """
    Fine-grained entitlement. E.g. "Can Add Product", "Can View Report".
    Organized into groups by like entities.
    """
    group = models.ForeignKey(
        ControlPointGroup,
        on_delete=models.CASCADE,
        related_name='control_points',
    )
    code = models.CharField(max_length=100, unique=True, db_index=True)
    label = models.CharField(max_length=255)
    description = models.TextField(blank=True)

    class Meta:
        ordering = ['group__sort_order', 'group__name', 'label']
        db_table = 'rbac_control_point'

    def __str__(self):
        return f"{self.group.name} > {self.label}"


class Role(BaseModel):
    """
    A named collection of control points.
    Users can have many roles. A role can have many control points.
    """
    name = models.CharField(max_length=100, unique=True)
    description = models.TextField(blank=True)
    control_points = models.ManyToManyField(
        ControlPoint,
        blank=True,
        related_name='roles',
    )

    class Meta:
        ordering = ['name']
        db_table = 'rbac_role'

    def __str__(self):
        return self.name
