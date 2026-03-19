from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from apps.core.models import BaseModel


class VisitLog(BaseModel):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="visits"
    )
    place = models.ForeignKey(
        "wineries.Place", on_delete=models.CASCADE, related_name="visits"
    )
    visited_at = models.DateTimeField()
    notes = models.TextField(blank=True)

    # Multi-factor ratings (1-5 scale)
    rating_staff = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)],
        null=True, blank=True,
    )
    rating_ambience = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)],
        null=True, blank=True,
    )
    rating_food = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)],
        null=True, blank=True,
    )
    rating_overall = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)],
        null=True, blank=True,
    )

    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "visits_visitlog"
        ordering = ["-visited_at"]

    def __str__(self):
        return f"{self.user} @ {self.place} ({self.visited_at:%Y-%m-%d})"


class VisitWine(BaseModel):
    """Wines tasted during a visit."""

    class ServingType(models.TextChoices):
        TASTING = "tasting", "Tasting"
        GLASS = "glass", "Glass"
        FLIGHT = "flight", "Flight"
        BOTTLE = "bottle", "Bottle"
        SPLIT = "split", "Split"

    visit = models.ForeignKey(VisitLog, on_delete=models.CASCADE, related_name="wines_tasted")
    menu_item = models.ForeignKey(
        "wineries.MenuItem", on_delete=models.CASCADE, related_name="visit_records",
        null=True, blank=True,
    )

    # Ad-hoc wine entry (when wine isn't in the database)
    wine_name = models.CharField(max_length=255, blank=True)
    wine_type = models.CharField(max_length=100, blank=True)  # e.g. Red, White, Rosé, Sparkling
    wine_vintage = models.PositiveIntegerField(null=True, blank=True)

    serving_type = models.CharField(
        max_length=20, choices=ServingType.choices, default=ServingType.TASTING,
    )
    quantity = models.PositiveSmallIntegerField(default=1)
    is_favorite = models.BooleanField(default=False)
    tasting_notes = models.TextField(blank=True)
    rating = models.PositiveSmallIntegerField(
        validators=[MinValueValidator(1), MaxValueValidator(5)],
        null=True, blank=True,
    )

    # Purchase tracking
    purchased = models.BooleanField(default=False)
    purchased_quantity = models.PositiveSmallIntegerField(null=True, blank=True)
    purchased_price = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    purchased_notes = models.TextField(blank=True)

    class Meta:
        db_table = "visits_visitwine"

    @property
    def display_name(self):
        if self.menu_item:
            return self.menu_item.name
        return self.wine_name or "Unknown wine"

    def __str__(self):
        return f"{self.display_name} — Visit {self.visit_id}"
