from django import forms

from apps.wineries.models import MenuItem, Place


class PlaceForm(forms.ModelForm):
    class Meta:
        model = Place
        fields = ["name", "description", "address", "city", "state", "country", "website", "phone"]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 3}),
        }


class PlaceAdminForm(forms.ModelForm):
    class Meta:
        model = Place
        fields = ["name", "place_type", "description", "address", "city", "state", "country",
                  "latitude", "longitude", "website", "phone", "image_url", "is_active"]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 4, "style": "min-height: 80px;"}),
        }


class MenuItemForm(forms.ModelForm):
    class Meta:
        model = MenuItem
        fields = ["name", "varietal", "vintage", "description"]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 3}),
        }
