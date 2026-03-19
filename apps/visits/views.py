from django.contrib import messages
from django.contrib.auth.mixins import LoginRequiredMixin
from django.shortcuts import get_object_or_404, redirect, render
from django.views import View
from django.views.generic import ListView

from apps.visits.forms import VisitLogForm
from apps.visits.models import VisitLog
from apps.wineries.models import Winery


class VisitListView(LoginRequiredMixin, ListView):
    model = VisitLog
    template_name = "visits/list.html"
    context_object_name = "visits"
    paginate_by = 10

    def get_queryset(self):
        return (
            VisitLog.objects.filter(user=self.request.user)
            .select_related("winery")
            .prefetch_related("wines_tasted__wine")
            .order_by("-visited_at")
        )


class CheckInView(LoginRequiredMixin, View):
    """Log a new winery visit — the core user action."""

    def get(self, request):
        winery_id = request.GET.get("winery")
        initial = {}
        winery = None
        if winery_id:
            winery = get_object_or_404(Winery, pk=winery_id)
            initial["winery"] = winery.pk
        form = VisitLogForm(initial=initial)
        return render(request, "visits/checkin.html", {
            "form": form,
            "preselected_winery": winery,
        })

    def post(self, request):
        form = VisitLogForm(request.POST)
        if form.is_valid():
            visit = form.save(commit=False)
            visit.user = request.user
            visit.save()
            messages.success(request, f"Checked in at {visit.winery.name}!")
            return redirect("visit_detail", pk=visit.pk)
        return render(request, "visits/checkin.html", {"form": form})


class VisitDetailView(LoginRequiredMixin, View):
    def get(self, request, pk):
        visit = get_object_or_404(
            VisitLog.objects.select_related("winery").prefetch_related("wines_tasted__wine"),
            pk=pk,
            user=request.user,
        )
        return render(request, "visits/detail.html", {"visit": visit})
