from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from encrypted_model_fields.fields import EncryptedTextField
from apps.core.models import BaseModel


class UserManager(BaseUserManager):
    def create_user(self, email, **extra_fields):
        if not email:
            raise ValueError('Email is required')
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_unusable_password()
        # Set 14-day free trial
        if not user.trial_end and not user.is_superuser:
            from django.utils import timezone
            from datetime import timedelta
            from django.conf import settings
            trial_days = getattr(settings, 'STRIPE_TRIAL_DAYS', 14)
            user.trial_end = timezone.now() + timedelta(days=trial_days)
            user.subscription_status = 'trialing'
        user.save(using=self._db)
        return user

    def create_superuser(self, email, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        return self.create_user(email, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin, BaseModel):
    """
    Custom user model. Authentication is exclusively via social OAuth.
    No password field is populated - set_unusable_password() called on creation.
    UUID primary key inherited from BaseModel.
    """
    class SubscriptionStatus(models.TextChoices):
        TRIALING = "trialing", "Trialing"
        ACTIVE = "active", "Active"
        PAST_DUE = "past_due", "Past Due"
        CANCELED = "canceled", "Canceled"
        NONE = "none", "None"

    email = models.EmailField(unique=True, db_index=True)
    first_name = models.CharField(max_length=150, blank=True)
    last_name = models.CharField(max_length=150, blank=True)
    avatar_url = models.URLField(blank=True)
    is_staff = models.BooleanField(default=False)
    last_login_provider = models.CharField(max_length=50, blank=True)
    roles = models.ManyToManyField('rbac.Role', blank=True, related_name='users')

    # Preferences
    timezone = models.CharField(max_length=63, blank=True, default="America/New_York",
                                help_text="IANA timezone (e.g. America/New_York)")

    # Stripe subscription
    stripe_customer_id = models.CharField(max_length=255, blank=True, db_index=True)
    subscription_status = models.CharField(
        max_length=20, choices=SubscriptionStatus.choices, default=SubscriptionStatus.TRIALING,
    )
    subscription_plan = models.CharField(max_length=20, blank=True)  # "monthly" or "yearly"
    stripe_subscription_id = models.CharField(max_length=255, blank=True)
    trial_end = models.DateTimeField(null=True, blank=True)

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []

    objects = UserManager()

    class Meta:
        db_table = 'users_user'

    @property
    def full_name(self):
        return f"{self.first_name} {self.last_name}".strip() or self.email

    @property
    def has_active_subscription(self):
        """User has access if in trial period, active subscription, or is superuser."""
        if self.is_superuser:
            return True
        # Active Stripe subscription always grants access
        if self.subscription_status == self.SubscriptionStatus.ACTIVE:
            return True
        # Trial period grants access regardless of subscription status
        if self.trial_end:
            from django.utils import timezone
            if timezone.now() < self.trial_end:
                return True
        return False

    @property
    def is_in_trial(self):
        """User is still within the trial window (regardless of subscription status)."""
        if not self.trial_end:
            return False
        from django.utils import timezone
        return timezone.now() < self.trial_end

    @property
    def trial_days_remaining(self):
        if not self.trial_end:
            return 0
        from django.utils import timezone
        delta = self.trial_end - timezone.now()
        return max(0, delta.days)


class SocialAccount(BaseModel):
    """
    Links a User to one or more social provider accounts.
    A user may have both Google and Microsoft linked.
    """
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='social_accounts')
    provider = models.CharField(max_length=50)
    provider_uid = models.CharField(max_length=255)
    access_token = EncryptedTextField(blank=True)
    refresh_token = EncryptedTextField(blank=True)
    token_expires_at = models.DateTimeField(null=True)
    raw_data = models.JSONField(default=dict)

    class Meta:
        unique_together = [('provider', 'provider_uid')]
        db_table = 'users_social_account'
