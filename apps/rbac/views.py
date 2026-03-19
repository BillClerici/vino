from django.contrib.auth import get_user_model
from django.contrib.auth.mixins import LoginRequiredMixin, UserPassesTestMixin
from django.contrib import messages
from django.shortcuts import get_object_or_404, redirect
from django.urls import reverse, reverse_lazy
from django.views.generic import ListView, CreateView, UpdateView, View

from apps.rbac.models import Role, ControlPoint, ControlPointGroup
from apps.rbac.forms import RoleForm, ControlPointForm, ControlPointGroupForm, UserEditForm
from apps.lookup.models import LookupValue
from apps.lookup.forms import LookupValueForm

User = get_user_model()


class SuperuserRequiredMixin(LoginRequiredMixin, UserPassesTestMixin):
    """Only allow superusers to access admin views."""
    def test_func(self):
        return self.request.user.is_superuser


# ── Users ──

class UserListView(SuperuserRequiredMixin, ListView):
    model = User
    template_name = 'admin/list.html'

    def get_queryset(self):
        return User.all_objects.all().order_by('email')

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = 'Users'
        ctx['icon'] = 'people'
        ctx['create_url'] = reverse('admin_users_create')
        ctx['columns'] = ['Email', 'Name', 'Staff', 'Superuser', 'Active', 'Roles']
        ctx['rows'] = [
            {
                'values': [
                    u.email,
                    u.full_name,
                    'Yes' if u.is_staff else 'No',
                    'Yes' if u.is_superuser else 'No',
                    'Yes' if u.is_active else 'No',
                    ', '.join(r.name for r in u.roles.all()) if hasattr(u, 'roles') else '-',
                ],
                'edit_url': reverse('admin_users_edit', args=[u.pk]),
                'delete_url': reverse('admin_users_delete', args=[u.pk]),
            }
            for u in ctx['object_list']
        ]
        return ctx


class UserCreateView(SuperuserRequiredMixin, CreateView):
    model = User
    form_class = UserEditForm
    template_name = 'admin/form.html'
    success_url = reverse_lazy('admin_users_list')

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = 'Create User'
        ctx['icon'] = 'person_add'
        ctx['cancel_url'] = reverse('admin_users_list')
        return ctx

    def form_valid(self, form):
        user = form.save(commit=False)
        user.set_unusable_password()
        user.save()
        form.save_m2m()
        messages.success(self.request, f'User {user.email} created.')
        return redirect(self.success_url)


class UserEditView(SuperuserRequiredMixin, UpdateView):
    model = User
    form_class = UserEditForm
    template_name = 'admin/form.html'
    success_url = reverse_lazy('admin_users_list')

    def get_queryset(self):
        return User.all_objects.all()

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = f'Edit User: {self.object.email}'
        ctx['icon'] = 'edit'
        ctx['cancel_url'] = reverse('admin_users_list')
        return ctx

    def form_valid(self, form):
        user = form.save()
        messages.success(self.request, f'User {user.email} updated.')
        return redirect(self.success_url)


class UserDeleteView(SuperuserRequiredMixin, View):
    def post(self, request, pk):
        user = get_object_or_404(User.all_objects, pk=pk)
        user.is_active = False
        user.save(update_fields=['is_active', 'updated_at'])
        messages.success(request, f'User {user.email} deactivated.')
        return redirect('admin_users_list')

    def get(self, request, pk):
        user = get_object_or_404(User.all_objects, pk=pk)
        return self.render_delete_confirm(request, user)

    def render_delete_confirm(self, request, user):
        from django.shortcuts import render
        return render(request, 'admin/delete.html', {
            'object_name': user.email,
            'cancel_url': reverse('admin_users_list'),
        })


# ── Roles ──

class RoleListView(SuperuserRequiredMixin, ListView):
    model = Role
    template_name = 'admin/list.html'

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = 'Roles'
        ctx['icon'] = 'badge'
        ctx['create_url'] = reverse('admin_roles_create')
        ctx['columns'] = ['Name', 'Description', 'Control Points']
        ctx['rows'] = [
            {
                'values': [
                    r.name,
                    r.description[:80] + ('...' if len(r.description) > 80 else ''),
                    r.control_points.count(),
                ],
                'edit_url': reverse('admin_roles_edit', args=[r.pk]),
                'delete_url': reverse('admin_roles_delete', args=[r.pk]),
            }
            for r in ctx['object_list']
        ]
        return ctx


class RoleCreateView(SuperuserRequiredMixin, CreateView):
    model = Role
    form_class = RoleForm
    template_name = 'admin/form.html'
    success_url = reverse_lazy('admin_roles_list')

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = 'Create Role'
        ctx['icon'] = 'badge'
        ctx['cancel_url'] = reverse('admin_roles_list')
        return ctx

    def form_valid(self, form):
        messages.success(self.request, f'Role {form.instance.name} created.')
        return super().form_valid(form)


class RoleEditView(SuperuserRequiredMixin, UpdateView):
    model = Role
    form_class = RoleForm
    template_name = 'admin/form.html'
    success_url = reverse_lazy('admin_roles_list')

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = f'Edit Role: {self.object.name}'
        ctx['icon'] = 'edit'
        ctx['cancel_url'] = reverse('admin_roles_list')
        return ctx

    def form_valid(self, form):
        messages.success(self.request, f'Role {form.instance.name} updated.')
        return super().form_valid(form)


class RoleDeleteView(SuperuserRequiredMixin, View):
    def post(self, request, pk):
        role = get_object_or_404(Role, pk=pk)
        role.is_active = False
        role.save(update_fields=['is_active', 'updated_at'])
        messages.success(request, f'Role {role.name} deactivated.')
        return redirect('admin_roles_list')

    def get(self, request, pk):
        role = get_object_or_404(Role, pk=pk)
        from django.shortcuts import render
        return render(request, 'admin/delete.html', {
            'object_name': role.name,
            'cancel_url': reverse('admin_roles_list'),
        })


# ── Control Points ──

class ControlPointListView(SuperuserRequiredMixin, ListView):
    model = ControlPoint
    template_name = 'admin/list.html'

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = 'Control Points'
        ctx['icon'] = 'security'
        ctx['create_url'] = reverse('admin_controlpoints_create')
        ctx['columns'] = ['Group', 'Code', 'Label', 'Roles Using']
        ctx['rows'] = [
            {
                'values': [
                    cp.group.name,
                    cp.code,
                    cp.label,
                    cp.roles.count(),
                ],
                'edit_url': reverse('admin_controlpoints_edit', args=[cp.pk]),
                'delete_url': reverse('admin_controlpoints_delete', args=[cp.pk]),
            }
            for cp in ctx['object_list']
        ]
        return ctx


class ControlPointCreateView(SuperuserRequiredMixin, CreateView):
    model = ControlPoint
    form_class = ControlPointForm
    template_name = 'admin/form.html'
    success_url = reverse_lazy('admin_controlpoints_list')

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = 'Create Control Point'
        ctx['icon'] = 'security'
        ctx['cancel_url'] = reverse('admin_controlpoints_list')
        return ctx


class ControlPointEditView(SuperuserRequiredMixin, UpdateView):
    model = ControlPoint
    form_class = ControlPointForm
    template_name = 'admin/form.html'
    success_url = reverse_lazy('admin_controlpoints_list')

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = f'Edit Control Point: {self.object.label}'
        ctx['icon'] = 'edit'
        ctx['cancel_url'] = reverse('admin_controlpoints_list')
        return ctx


class ControlPointDeleteView(SuperuserRequiredMixin, View):
    def post(self, request, pk):
        cp = get_object_or_404(ControlPoint, pk=pk)
        cp.is_active = False
        cp.save(update_fields=['is_active', 'updated_at'])
        messages.success(request, f'Control point {cp.label} deactivated.')
        return redirect('admin_controlpoints_list')

    def get(self, request, pk):
        cp = get_object_or_404(ControlPoint, pk=pk)
        from django.shortcuts import render
        return render(request, 'admin/delete.html', {
            'object_name': cp.label,
            'cancel_url': reverse('admin_controlpoints_list'),
        })


# ── Control Point Groups ──

class ControlPointGroupListView(SuperuserRequiredMixin, ListView):
    model = ControlPointGroup
    template_name = 'admin/list.html'

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = 'Control Point Groups'
        ctx['icon'] = 'folder'
        ctx['create_url'] = reverse('admin_cpgroups_create')
        ctx['columns'] = ['Name', 'Description', 'Sort Order', 'Control Points']
        ctx['rows'] = [
            {
                'values': [
                    g.name,
                    g.description[:80] + ('...' if len(g.description) > 80 else ''),
                    g.sort_order,
                    g.control_points.count(),
                ],
                'edit_url': reverse('admin_cpgroups_edit', args=[g.pk]),
                'delete_url': reverse('admin_cpgroups_delete', args=[g.pk]),
            }
            for g in ctx['object_list']
        ]
        return ctx


class ControlPointGroupCreateView(SuperuserRequiredMixin, CreateView):
    model = ControlPointGroup
    form_class = ControlPointGroupForm
    template_name = 'admin/form.html'
    success_url = reverse_lazy('admin_cpgroups_list')

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = 'Create Control Point Group'
        ctx['icon'] = 'create_new_folder'
        ctx['cancel_url'] = reverse('admin_cpgroups_list')
        return ctx

    def form_valid(self, form):
        messages.success(self.request, f'Group {form.instance.name} created.')
        return super().form_valid(form)


class ControlPointGroupEditView(SuperuserRequiredMixin, UpdateView):
    model = ControlPointGroup
    form_class = ControlPointGroupForm
    template_name = 'admin/form.html'
    success_url = reverse_lazy('admin_cpgroups_list')

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = f'Edit Group: {self.object.name}'
        ctx['icon'] = 'edit'
        ctx['cancel_url'] = reverse('admin_cpgroups_list')
        return ctx

    def form_valid(self, form):
        messages.success(self.request, f'Group {form.instance.name} updated.')
        return super().form_valid(form)


class ControlPointGroupDeleteView(SuperuserRequiredMixin, View):
    def post(self, request, pk):
        group = get_object_or_404(ControlPointGroup, pk=pk)
        group.is_active = False
        group.save(update_fields=['is_active', 'updated_at'])
        messages.success(request, f'Group {group.name} deactivated.')
        return redirect('admin_cpgroups_list')

    def get(self, request, pk):
        group = get_object_or_404(ControlPointGroup, pk=pk)
        from django.shortcuts import render
        return render(request, 'admin/delete.html', {
            'object_name': group.name,
            'cancel_url': reverse('admin_cpgroups_list'),
        })


# ── Lookup Items ──

class LookupListView(SuperuserRequiredMixin, ListView):
    model = LookupValue
    template_name = 'admin/list.html'

    def get_queryset(self):
        return LookupValue.all_objects.all().order_by('parent__label', 'sort_order', 'label')

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = 'Lookup Items'
        ctx['icon'] = 'list'
        ctx['create_url'] = reverse('admin_lookups_create')
        ctx['columns'] = ['Type/Parent', 'Code', 'Label', 'Sort Order', 'Active']
        ctx['rows'] = [
            {
                'values': [
                    lv.parent.label if lv.parent else '(Type)',
                    lv.code,
                    lv.label,
                    lv.sort_order,
                    'Yes' if lv.is_active else 'No',
                ],
                'edit_url': reverse('admin_lookups_edit', args=[lv.pk]),
                'delete_url': reverse('admin_lookups_delete', args=[lv.pk]),
            }
            for lv in ctx['object_list']
        ]
        return ctx


class LookupCreateView(SuperuserRequiredMixin, CreateView):
    model = LookupValue
    form_class = LookupValueForm
    template_name = 'admin/form.html'
    success_url = reverse_lazy('admin_lookups_list')

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = 'Create Lookup Item'
        ctx['icon'] = 'list'
        ctx['cancel_url'] = reverse('admin_lookups_list')
        return ctx


class LookupEditView(SuperuserRequiredMixin, UpdateView):
    model = LookupValue
    form_class = LookupValueForm
    template_name = 'admin/form.html'
    success_url = reverse_lazy('admin_lookups_list')

    def get_queryset(self):
        return LookupValue.all_objects.all()

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        ctx['page_title'] = f'Edit Lookup: {self.object.label}'
        ctx['icon'] = 'edit'
        ctx['cancel_url'] = reverse('admin_lookups_list')
        return ctx


class LookupDeleteView(SuperuserRequiredMixin, View):
    def post(self, request, pk):
        lv = get_object_or_404(LookupValue.all_objects, pk=pk)
        lv.is_active = False
        lv.save(update_fields=['is_active', 'updated_at'])
        messages.success(request, f'Lookup {lv.label} deactivated.')
        return redirect('admin_lookups_list')

    def get(self, request, pk):
        lv = get_object_or_404(LookupValue.all_objects, pk=pk)
        from django.shortcuts import render
        return render(request, 'admin/delete.html', {
            'object_name': lv.label,
            'cancel_url': reverse('admin_lookups_list'),
        })
