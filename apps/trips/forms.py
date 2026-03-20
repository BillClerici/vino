from datetime import date, time

from django import forms

from apps.trips.models import Trip


class TripForm(forms.ModelForm):
    class Meta:
        model = Trip
        fields = ["name", "scheduled_date", "end_date", "meeting_time"]
        labels = {
            "scheduled_date": "Start Date",
            "end_date": "End Date",
            "meeting_time": "Start Time",
        }
        widgets = {
            "scheduled_date": forms.DateInput(attrs={"type": "date"}),
            "end_date": forms.DateInput(attrs={"type": "date"}),
            "meeting_time": forms.TimeInput(attrs={"type": "time"}),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if not self.instance.pk:
            today = date.today().isoformat()
            noon = time(12, 0).strftime("%H:%M")
            for field_name, default in [
                ("scheduled_date", today),
                ("end_date", today),
                ("meeting_time", noon),
            ]:
                if not self.initial.get(field_name):
                    self.initial[field_name] = default
                if not self.fields[field_name].widget.attrs.get("value"):
                    self.fields[field_name].widget.attrs["value"] = default
