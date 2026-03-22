from django.conf import settings
from django.db import models

from apps.core.models import BaseModel


class Place(BaseModel):
    class PlaceType(models.TextChoices):
        WINERY = "winery", "Winery"
        BREWERY = "brewery", "Brewery"
        RESTAURANT = "restaurant", "Restaurant"
        OTHER = "other", "Other"

    name = models.CharField(max_length=255, db_index=True)
    place_type = models.CharField(max_length=20, choices=PlaceType.choices, default=PlaceType.WINERY)
    description = models.TextField(blank=True)

    # Location
    address = models.CharField(max_length=500, blank=True)
    city = models.CharField(max_length=100, blank=True)
    state = models.CharField(max_length=100, blank=True)
    zip_code = models.CharField(max_length=20, blank=True)
    country = models.CharField(max_length=100, default="US")
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

    # Contact & metadata
    website = models.URLField(blank=True)
    phone = models.CharField(max_length=30, blank=True)
    image_url = models.URLField(max_length=1000, blank=True)
    wine_menu_last_scraped = models.DateTimeField(null=True, blank=True)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "places_place"
        verbose_name_plural = "places"
        ordering = ["name"]

    def __str__(self):
        return self.name


class MenuItem(BaseModel):
    place = models.ForeignKey(Place, on_delete=models.CASCADE, related_name="menu_items")
    name = models.CharField(max_length=255)
    varietal = models.CharField(max_length=100, db_index=True)
    vintage = models.PositiveIntegerField(null=True, blank=True)
    description = models.TextField(blank=True)
    price = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    image_url = models.URLField(max_length=1000, blank=True)
    pinecone_vector_id = models.CharField(max_length=255, blank=True, db_index=True)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "places_menuitem"
        ordering = ["name", "-vintage"]

    def __str__(self):
        vintage = f" ({self.vintage})" if self.vintage else ""
        return f"{self.name}{vintage} — {self.place.name}"


class FavoritePlace(BaseModel):
    """Tracks which places a user has favorited."""
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="favorite_places"
    )
    place = models.ForeignKey(Place, on_delete=models.CASCADE, related_name="favorited_by")

    class Meta:
        db_table = "places_favoriteplace"
        unique_together = [("user", "place")]

    def __str__(self):
        return f"{self.user} ♥ {self.place}"


class WineWishlist(BaseModel):
    """Wines the user wants to try in the future."""
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="wine_wishlist"
    )
    # Link to a specific menu item if known
    menu_item = models.ForeignKey(
        MenuItem, on_delete=models.SET_NULL, null=True, blank=True, related_name="wishlisted_by"
    )
    # Ad-hoc wine details (when not from a menu)
    wine_name = models.CharField(max_length=255)
    wine_type = models.CharField(max_length=100, blank=True)  # varietal
    wine_vintage = models.PositiveIntegerField(null=True, blank=True)
    notes = models.TextField(blank=True)
    # Where they discovered it
    source_place = models.ForeignKey(
        Place, on_delete=models.SET_NULL, null=True, blank=True, related_name="wishlist_sources"
    )

    class Meta:
        db_table = "places_winewishlist"
        ordering = ["-created_at"]

    @property
    def display_name(self):
        if self.menu_item:
            return self.menu_item.name
        return self.wine_name

    def __str__(self):
        return f"{self.user} wants: {self.display_name}"
