from django.contrib.auth import logout
from django.shortcuts import redirect
from django.views import View
from django.views.generic import TemplateView


class LoginView(TemplateView):
    template_name = "auth/login.html"


class RegisterView(TemplateView):
    template_name = "auth/register.html"


class LogoutView(View):
    def get(self, request):
        logout(request)
        return redirect('landing')

    def post(self, request):
        logout(request)
        return redirect('landing')
