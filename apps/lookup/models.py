from django.db import models

from apps.core.models import BaseModel


class LookupValue(BaseModel):
    """
    Universal lookup/reference table using parent-child hierarchy.
    Parent records define the lookup TYPE (e.g. "Customer Type").
    Child records define the valid VALUES for that type (e.g. "Enterprise", "SMB").
    """
    parent = models.ForeignKey(
        'self',
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name='children',
        help_text="Null = this record IS a lookup type. Non-null = this is a value within that type."
    )
    code = models.CharField(max_length=100, db_index=True)
    label = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    sort_order = models.PositiveIntegerField(default=0)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        unique_together = [('parent', 'code')]
        ordering = ['sort_order', 'label']

    def __str__(self):
        prefix = self.parent.label if self.parent else 'TYPE'
        return f"{prefix} > {self.label}"
