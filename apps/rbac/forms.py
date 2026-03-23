from django import forms
from django.contrib.auth import get_user_model

from apps.rbac.models import ControlPoint, ControlPointGroup, Role

User = get_user_model()


class UserEditForm(forms.ModelForm):
    roles = forms.ModelMultipleChoiceField(
        queryset=Role.objects.all(),
        required=False,
        widget=forms.SelectMultiple(attrs={'class': 'browser-default', 'style': 'height: 250px;'}),
        help_text='Hold Ctrl/Cmd to select multiple roles.',
    )

    class Meta:
        model = User
        fields = ['email', 'first_name', 'last_name', 'is_active', 'is_staff', 'is_superuser', 'roles']

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        if self.instance.pk:
            self.fields['roles'].initial = self.instance.roles.all()

    def save(self, commit=True):
        user = super().save(commit=commit)
        if commit:
            user.roles.set(self.cleaned_data['roles'])
        return user


class RoleForm(forms.ModelForm):
    control_points = forms.ModelMultipleChoiceField(
        queryset=ControlPoint.objects.all(),
        required=False,
        widget=forms.SelectMultiple(attrs={'class': 'browser-default', 'style': 'height: 250px;'}),
        help_text='Hold Ctrl/Cmd to select multiple control points.',
    )

    class Meta:
        model = Role
        fields = ['name', 'description', 'control_points']


class ControlPointForm(forms.ModelForm):
    group = forms.ModelChoiceField(
        queryset=ControlPointGroup.objects.all(),
        empty_label='Select a group...',
        widget=forms.Select(attrs={'class': 'browser-default'}),
    )

    class Meta:
        model = ControlPoint
        fields = ['group', 'code', 'label', 'description']


class ControlPointGroupForm(forms.ModelForm):
    class Meta:
        model = ControlPointGroup
        fields = ['name', 'description', 'sort_order']
