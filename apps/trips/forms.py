from django import forms

from apps.trips.models import Trip


class TripForm(forms.ModelForm):
    class Meta:
        model = Trip
        fields = ["name", "scheduled_date"]
        widgets = {
            "scheduled_date": forms.DateInput(attrs={"type": "date"}),
        }
