from django import forms
from django.contrib import messages
from django.contrib.auth import logout
from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Avg
from django.shortcuts import redirect, render
from django.views import View
from django.views.generic import TemplateView

from apps.users.models import User


class ProfileForm(forms.ModelForm):
    class Meta:
        model = User
        fields = ["first_name", "last_name", "avatar_url"]
        widgets = {
            "avatar_url": forms.URLInput(attrs={"placeholder": "https://..."}),
        }


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


class ProfileView(LoginRequiredMixin, View):
    """Comprehensive user profile page."""

    def get(self, request):
        from apps.trips.models import Trip
        from apps.visits.models import VisitLog, VisitWine

        user = request.user

        # Activity stats
        my_visits = VisitLog.objects.filter(user=user, is_active=True)
        visit_count = my_visits.count()
        places_visited = my_visits.values("place").distinct().count()
        avg_rating = my_visits.aggregate(avg=Avg("rating_overall"))["avg"]

        trips_total = Trip.objects.filter(members=user, is_active=True).count()
        trips_completed = Trip.objects.filter(members=user, is_active=True, status="completed").count()
        trips_in_progress = Trip.objects.filter(members=user, is_active=True, status="in_progress").count()

        wines_logged = VisitWine.objects.filter(visit__user=user, is_active=True).count()
        favorites = VisitWine.objects.filter(visit__user=user, is_active=True, is_favorite=True).count()

        # Linked social accounts
        social_accounts = user.social_accounts.filter(is_active=True)

        # Recent visits
        recent_visits = my_visits.select_related("place").order_by("-visited_at")[:5]

        return render(request, "users/profile.html", {
            "profile_user": user,
            "form": ProfileForm(instance=user),
            "visit_count": visit_count,
            "places_visited": places_visited,
            "avg_rating": round(avg_rating, 1) if avg_rating else None,
            "trips_total": trips_total,
            "trips_completed": trips_completed,
            "trips_in_progress": trips_in_progress,
            "wines_logged": wines_logged,
            "favorites": favorites,
            "social_accounts": social_accounts,
            "recent_visits": recent_visits,
        })

    def post(self, request):
        user = request.user
        form = ProfileForm(request.POST, instance=user)
        if form.is_valid():
            form.save()
            messages.success(request, "Profile updated.")
            return redirect("profile")
        return render(request, "users/profile.html", {
            "profile_user": user,
            "form": form,
        })
