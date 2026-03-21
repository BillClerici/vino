from django.conf import settings
from django.db import models

from apps.core.models import BaseModel


class Partner(BaseModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        APPROVED = "approved", "Approved"
        SUSPENDED = "suspended", "Suspended"
        REJECTED = "rejected", "Rejected"

    owners = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        through="PartnerOwner",
        related_name="partner_memberships",
    )
    business_name = models.CharField(max_length=255)
    business_email = models.EmailField(blank=True)
    business_phone = models.CharField(max_length=30, blank=True)
    website = models.URLField(blank=True)
    logo_url = models.URLField(max_length=1000, blank=True)
    description = models.TextField(blank=True)

    class Tier(models.TextChoices):
        FREE = "free", "Free"
        SILVER = "silver", "Silver"
        GOLD = "gold", "Gold"
        PLATINUM = "platinum", "Platinum"

    class SubscriptionStatus(models.TextChoices):
        NONE = "none", "None"
        TRIALING = "trialing", "Trialing"
        ACTIVE = "active", "Active"
        PAST_DUE = "past_due", "Past Due"
        CANCELED = "canceled", "Canceled"

    tier = models.CharField(max_length=20, choices=Tier.choices, default=Tier.FREE)
    subscription_status = models.CharField(
        max_length=20, choices=SubscriptionStatus.choices, default=SubscriptionStatus.NONE,
    )
    subscription_plan = models.CharField(max_length=30, blank=True, help_text="e.g. silver_monthly, gold_yearly")

    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    approved_at = models.DateTimeField(null=True, blank=True)
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="approved_partners",
    )
    rejected_at = models.DateTimeField(null=True, blank=True)
    rejected_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="rejected_partners",
    )
    decision_email_sent_at = models.DateTimeField(null=True, blank=True)
    stripe_customer_id = models.CharField(max_length=255, blank=True)
    stripe_subscription_id = models.CharField(max_length=255, blank=True)
    metadata = models.JSONField(default=dict, blank=True)

    @property
    def has_active_subscription(self):
        return self.subscription_status in (
            self.SubscriptionStatus.ACTIVE,
            self.SubscriptionStatus.TRIALING,
        )

    class Meta:
        db_table = "partners_partner"
        ordering = ["-created_at"]

    def __str__(self):
        return self.business_name

    @property
    def primary_owner(self):
        """Return the primary owner's PartnerOwner record, or the first owner."""
        return (
            self.partner_owners.filter(role=PartnerOwner.Role.PRIMARY, is_active=True).first()
            or self.partner_owners.filter(is_active=True).first()
        )


class PartnerOwner(BaseModel):
    """Through model linking users to partners with role and contact info."""

    class Role(models.TextChoices):
        PRIMARY = "primary", "Primary Owner"
        OWNER = "owner", "Owner"
        MANAGER = "manager", "Manager"

    partner = models.ForeignKey(Partner, on_delete=models.CASCADE, related_name="partner_owners")
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="partner_roles",
    )
    role = models.CharField(max_length=20, choices=Role.choices, default=Role.OWNER)
    title = models.CharField(max_length=100, blank=True, help_text="e.g. CEO, Head Winemaker")
    contact_email = models.EmailField(blank=True)
    contact_phone = models.CharField(max_length=30, blank=True)
    mobile_phone = models.CharField(max_length=30, blank=True)
    address = models.CharField(max_length=500, blank=True)
    city = models.CharField(max_length=100, blank=True)
    state = models.CharField(max_length=100, blank=True)
    zip_code = models.CharField(max_length=20, blank=True)
    notes = models.TextField(blank=True)

    class Meta:
        db_table = "partners_partnerowner"
        unique_together = [("partner", "user")]
        ordering = ["role", "user__first_name"]

    def __str__(self):
        return f"{self.user.full_name} — {self.get_role_display()} @ {self.partner.business_name}"

    @property
    def display_name(self):
        return self.user.full_name or self.user.email


class PlaceClaim(BaseModel):
    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        APPROVED = "approved", "Approved"
        REJECTED = "rejected", "Rejected"
        REVOKED = "revoked", "Revoked"

    partner = models.ForeignKey(Partner, on_delete=models.CASCADE, related_name="claims")
    place = models.OneToOneField(
        "wineries.Place",
        on_delete=models.CASCADE,
        related_name="claim",
    )
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    claimed_at = models.DateTimeField(auto_now_add=True)
    approved_at = models.DateTimeField(null=True, blank=True)
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    verification_notes = models.TextField(blank=True)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "partners_placeclaim"
        ordering = ["-claimed_at"]

    def __str__(self):
        return f"{self.partner.business_name} → {self.place.name}"


class Promotion(BaseModel):
    class Status(models.TextChoices):
        DRAFT = "draft", "Draft"
        PENDING_REVIEW = "pending_review", "Pending Review"
        ACTIVE = "active", "Active"
        PAUSED = "paused", "Paused"
        EXPIRED = "expired", "Expired"
        REJECTED = "rejected", "Rejected"

    partner = models.ForeignKey(Partner, on_delete=models.CASCADE, related_name="promotions")
    place = models.ForeignKey(
        "wineries.Place",
        on_delete=models.CASCADE,
        related_name="promotions",
    )
    name = models.CharField(max_length=255)
    promotion_type = models.ForeignKey(
        "lookup.LookupValue",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="promotions_by_type",
        help_text="Promotion type from Lookup: PROMOTION_TYPE",
    )
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.DRAFT)
    start_date = models.DateField()
    end_date = models.DateField()
    headline = models.CharField(max_length=255, blank=True)
    description = models.TextField(blank=True)
    image_url = models.URLField(max_length=1000, blank=True)
    cta_text = models.CharField(max_length=50, blank=True)
    cta_link = models.URLField(blank=True)
    target_regions = models.JSONField(default=list, blank=True)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "partners_promotion"
        ordering = ["-start_date"]

    def __str__(self):
        return self.name


class PromotionImpression(BaseModel):
    class ImpressionType(models.TextChoices):
        VIEW = "view", "View"
        CLICK = "click", "Click"
        CONVERSION = "conversion", "Conversion"

    promotion = models.ForeignKey(Promotion, on_delete=models.CASCADE, related_name="impressions")
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
    )
    impression_type = models.CharField(max_length=20, choices=ImpressionType.choices)
    context = models.CharField(max_length=50, blank=True)
    metadata = models.JSONField(default=dict, blank=True)

    class Meta:
        db_table = "partners_promotionimpression"
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.promotion.name} — {self.impression_type}"
