from django import forms
from apps.lookup.models import LookupValue


class LookupValueForm(forms.ModelForm):
    parent = forms.ModelChoiceField(
        queryset=LookupValue.all_objects.filter(parent__isnull=True),
        required=False,
        empty_label='(This is a Type — no parent)',
        widget=forms.Select(attrs={'class': 'browser-default'}),
        help_text='Leave blank if this record defines a new lookup TYPE.',
    )

    class Meta:
        model = LookupValue
        fields = ['parent', 'code', 'label', 'description', 'sort_order', 'is_active']
