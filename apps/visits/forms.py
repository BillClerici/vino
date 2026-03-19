from django import forms
from django.utils import timezone

from apps.visits.models import VisitLog
from apps.wineries.models import Place


class VisitLogForm(forms.ModelForm):
    place = forms.ModelChoiceField(
        queryset=Place.objects.all(),
        widget=forms.Select(),
    )

    class Meta:
        model = VisitLog
        fields = ["place", "visited_at", "notes", "rating_staff", "rating_ambience", "rating_food", "rating_overall"]
        widgets = {
            "visited_at": forms.DateTimeInput(attrs={"type": "datetime-local"}),
            "notes": forms.Textarea(attrs={"class": "materialize-textarea", "rows": 3}),
        }

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if not self.initial.get("visited_at"):
            self.initial["visited_at"] = timezone.now().strftime("%Y-%m-%dT%H:%M")
        # Star rating widgets — rendered custom in template
        for field_name in ["rating_staff", "rating_ambience", "rating_food", "rating_overall"]:
            self.fields[field_name].widget = forms.HiddenInput()
            self.fields[field_name].required = False
