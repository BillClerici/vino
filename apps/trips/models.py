from django.conf import settings
from django.db import models

from apps.core.models import BaseModel


class Trip(BaseModel):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        PLANNING = "planning", "Planning"
        CONFIRMED = "confirmed", "Confirmed"
        IN_PROGRESS = "in_progress", "In Progress"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"

    name = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="created_trips"
    )
    members = models.ManyToManyField(
        settings.AUTH_USER_MODEL, through="TripMember", related_name="trips"
    )
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.DRAFT)
    itinerary = models.JSONField(default=list, blank=True)
    scheduled_date = models.DateField(null=True, blank=True)
    end_date = models.DateField(null=True, blank=True)
    meeting_location = models.CharField(max_length=500, blank=True)
    meeting_time = models.TimeField(null=True, blank=True)
    meeting_notes = models.TextField(blank=True)
    transportation = models.CharField(max_length=255, blank=True)
    budget_notes = models.TextField(blank=True)
    notes = models.TextField(blank=True)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "trips_trip"
        ordering = ["-scheduled_date"]

    def __str__(self):
        return f"{self.name} ({self.get_status_display()})"


class TripMember(BaseModel):
    class Role(models.TextChoices):
        ORGANIZER = "organizer", "Organizer"
        MEMBER = "member", "Member"
        INVITED = "invited", "Invited"

    RSVP_CHOICES = [
        ("pending", "Pending"),
        ("accepted", "Accepted"),
        ("declined", "Declined"),
    ]

    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name="trip_members")
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="trip_memberships",
        null=True, blank=True,
    )
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.MEMBER)
    rsvp_status = models.CharField(
        max_length=20, choices=RSVP_CHOICES, default="pending",
    )

    notes = models.TextField(blank=True)

    # Invitation fields
    invite_email = models.EmailField(max_length=254, blank=True)
    invite_first_name = models.CharField(max_length=150, blank=True)
    invite_last_name = models.CharField(max_length=150, blank=True)
    invite_message = models.TextField(blank=True)
    invited_at = models.DateTimeField(null=True, blank=True)
    responded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "trips_tripmember"

    @property
    def display_name(self):
        if self.user:
            return self.user.full_name or self.user.email
        name = f"{self.invite_first_name} {self.invite_last_name}".strip()
        return name or self.invite_email

    @property
    def display_initial(self):
        if self.user and self.user.first_name:
            return self.user.first_name[0].upper()
        if self.invite_first_name:
            return self.invite_first_name[0].upper()
        email = self.invite_email or (self.user.email if self.user else "?")
        return email[0].upper()

    def __str__(self):
        return f"{self.display_name} — {self.trip.name} ({self.get_role_display()})"


class TripWinery(BaseModel):
    """Wineries on the trip itinerary with ordering."""
    trip = models.ForeignKey(Trip, on_delete=models.CASCADE, related_name="trip_wineries")
    winery = models.ForeignKey(
        "wineries.Winery", on_delete=models.CASCADE, related_name="trip_stops"
    )
    order = models.PositiveIntegerField(default=0)
    arrival_time = models.DateTimeField(null=True, blank=True)
    duration_minutes = models.PositiveIntegerField(null=True, blank=True)
    description = models.TextField(blank=True)
    notes = models.TextField(blank=True)
    meeting_details = models.TextField(blank=True)
    travel_details = models.TextField(blank=True)

    class Meta:
        db_table = "trips_tripwinery"
        ordering = ["order"]
        unique_together = [("trip", "winery")]

    def __str__(self):
        return f"Stop #{self.order}: {self.winery.name}"
