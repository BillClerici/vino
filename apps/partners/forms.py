from django import forms

from apps.partners.models import Partner, PlaceClaim, Promotion
from apps.wineries.models import Place


def _clean_url(value):
    """Prepend https:// if no scheme is present."""
    if not value:
        return value
    value = value.strip()
    if value and not value.startswith(("http://", "https://")):
        value = "https://" + value
    return value


class URLCleanMixin:
    """Mixin that auto-prepends https:// to website and logo_url fields.
    Also swaps URLInput widgets to TextInput to avoid browser-side validation."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        for field_name in ("website", "logo_url", "image_url", "cta_link"):
            if field_name in self.fields:
                self.fields[field_name].widget = forms.TextInput(
                    attrs=self.fields[field_name].widget.attrs
                )

    def clean_website(self):
        return _clean_url(self.cleaned_data.get("website", ""))

    def clean_logo_url(self):
        return _clean_url(self.cleaned_data.get("logo_url", ""))

    def clean_image_url(self):
        return _clean_url(self.cleaned_data.get("image_url", ""))

    def clean_cta_link(self):
        return _clean_url(self.cleaned_data.get("cta_link", ""))


def _promotion_type_queryset():
    from apps.lookup.models import LookupValue
    return LookupValue.objects.filter(parent__code="PROMOTION_TYPE").order_by("sort_order")


class PartnerApplyForm(URLCleanMixin, forms.ModelForm):
    """Form for users applying to become a partner."""

    class Meta:
        model = Partner
        fields = ["business_name", "business_email", "business_phone", "website", "description"]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 4}),
        }


class PartnerProfileForm(URLCleanMixin, forms.ModelForm):
    """Form for partners editing their business profile."""

    class Meta:
        model = Partner
        fields = [
            "business_name",
            "business_email",
            "business_phone",
            "website",
            "logo_url",
            "description",
        ]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 4}),
        }


class PlaceClaimForm(forms.ModelForm):
    """Form for claiming a place."""

    place = forms.ModelChoiceField(
        queryset=Place.objects.all(),
        widget=forms.Select(attrs={"class": "browser-default"}),
        help_text="Select the place you want to claim.",
    )

    class Meta:
        model = PlaceClaim
        fields = ["place"]

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Exclude places that already have an active claim
        claimed_place_ids = PlaceClaim.objects.filter(
            status__in=["pending", "approved"],
        ).values_list("place_id", flat=True)
        self.fields["place"].queryset = Place.objects.exclude(id__in=claimed_place_ids)


class PromotionForm(URLCleanMixin, forms.ModelForm):
    """Form for creating/editing promotions."""

    start_date = forms.DateField(widget=forms.DateInput(attrs={"type": "date"}))
    end_date = forms.DateField(widget=forms.DateInput(attrs={"type": "date"}))
    promotion_type = forms.ModelChoiceField(
        queryset=_promotion_type_queryset(),
        widget=forms.Select(attrs={"class": "browser-default"}),
        empty_label="— Select Type —",
    )

    class Meta:
        model = Promotion
        fields = [
            "name",
            "place",
            "promotion_type",
            "start_date",
            "end_date",
            "headline",
            "description",
            "image_url",
            "cta_text",
            "cta_link",
        ]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 4}),
        }

    def __init__(self, *args, partner=None, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["promotion_type"].queryset = _promotion_type_queryset()
        if partner:
            approved_place_ids = partner.claims.filter(status="approved").values_list(
                "place_id", flat=True
            )
            self.fields["place"].queryset = Place.objects.filter(id__in=approved_place_ids)

    def clean(self):
        cleaned_data = super().clean()
        start = cleaned_data.get("start_date")
        end = cleaned_data.get("end_date")
        if start and end and end < start:
            raise forms.ValidationError("End date must be after start date.")
        return cleaned_data


class AdminPartnerCreateForm(URLCleanMixin, forms.ModelForm):
    """Admin form for creating a new partner."""

    class Meta:
        model = Partner
        fields = [
            "business_name",
            "business_email",
            "business_phone",
            "website",
            "logo_url",
            "description",
        ]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 4}),
        }


class AdminPartnerForm(URLCleanMixin, forms.ModelForm):
    """Admin form for editing a partner."""

    class Meta:
        model = Partner
        fields = [
            "business_name",
            "business_email",
            "business_phone",
            "website",
            "logo_url",
            "description",
        ]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 4}),
        }


class AdminClaimForm(forms.ModelForm):
    """Admin form for editing a claim."""

    class Meta:
        model = PlaceClaim
        fields = ["status", "verification_notes"]
        widgets = {
            "verification_notes": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 4}),
        }


class AdminPromotionForm(URLCleanMixin, forms.ModelForm):
    """Admin form for editing a promotion."""

    start_date = forms.DateField(widget=forms.DateInput(attrs={"type": "date"}))
    end_date = forms.DateField(widget=forms.DateInput(attrs={"type": "date"}))
    promotion_type = forms.ModelChoiceField(
        queryset=_promotion_type_queryset(),
        required=False,
        widget=forms.Select(attrs={"class": "browser-default"}),
        empty_label="— Select Type —",
    )

    class Meta:
        model = Promotion
        fields = [
            "name",
            "promotion_type",
            "status",
            "start_date",
            "end_date",
            "headline",
            "description",
            "image_url",
            "cta_text",
            "cta_link",
        ]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 4}),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.fields["promotion_type"].queryset = _promotion_type_queryset()
