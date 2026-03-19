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
    email = models.EmailField(unique=True, db_index=True)
    first_name = models.CharField(max_length=150, blank=True)
    last_name = models.CharField(max_length=150, blank=True)
    avatar_url = models.URLField(blank=True)
    is_staff = models.BooleanField(default=False)
    last_login_provider = models.CharField(max_length=50, blank=True)
    roles = models.ManyToManyField('rbac.Role', blank=True, related_name='users')

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []

    objects = UserManager()

    class Meta:
        db_table = 'users_user'

    @property
    def full_name(self):
        return f"{self.first_name} {self.last_name}".strip() or self.email


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
