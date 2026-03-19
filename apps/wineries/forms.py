from django import forms

from apps.wineries.models import Wine, Winery


class WineryForm(forms.ModelForm):
    class Meta:
        model = Winery
        fields = ["name", "description", "address", "city", "state", "country", "website", "phone"]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 3}),
        }


class WineForm(forms.ModelForm):
    class Meta:
        model = Wine
        fields = ["name", "varietal", "vintage", "description"]
        widgets = {
            "description": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 3}),
        }
