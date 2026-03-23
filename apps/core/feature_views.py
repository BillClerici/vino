"""
Web views for features that were originally mobile-only.
Wishlist, Cellar, Badges, Journey Map, Trip Recap, Sippy Chat.
All use existing API logic — no new backend code needed.
"""

import json
import logging

from django.contrib.auth.mixins import LoginRequiredMixin
from django.db.models import Avg, Count, F, Max, Q, Sum
from django.views.generic import TemplateView

from apps.trips.models import SippyConversation, Trip
from apps.visits.models import VisitLog, VisitWine
from apps.wineries.models import WineWishlist

logger = logging.getLogger(__name__)


# ── Onboarding ───────────────────────────────────────────────────

class UpdateOnboardingView(LoginRequiredMixin, TemplateView):
    """POST to update onboarding_status."""
    template_name = 'base.html'  # unused

    def post(self, request, *args, **kwargs):
        from django.http import JsonResponse
        status_val = request.POST.get('status', '')
        if status_val in ('completed', 'skipped', 'later', 'pending'):
            request.user.onboarding_status = status_val
            request.user.save(update_fields=['onboarding_status', 'updated_at'])
        return JsonResponse({'ok': True})


class HelpView(LoginRequiredMixin, TemplateView):
    template_name = 'features/help.html'


class SubscriptionRequiredMixin(LoginRequiredMixin):
    """Mixin that checks the user has an active subscription."""
    def dispatch(self, request, *args, **kwargs):
        if request.user.is_authenticated and not request.user.has_active_subscription:
            from django.shortcuts import redirect
            return redirect('pricing')
        return super().dispatch(request, *args, **kwargs)


# ── Sippy Chat Views ─────────────────────────────────────────────

class SippyPlannerView(SubscriptionRequiredMixin, TemplateView):
    template_name = 'features/sippy_planner.html'


class SippyChatView(SubscriptionRequiredMixin, TemplateView):
    template_name = 'features/sippy_chat.html'

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        trip_id = self.kwargs.get('trip_pk') or self.request.GET.get('trip')
        if trip_id:
            try:
                ctx['trip'] = Trip.objects.get(pk=trip_id, members=self.request.user, is_active=True)
            except Trip.DoesNotExist:
                pass
        return ctx


class SippyHistoryView(SubscriptionRequiredMixin, TemplateView):
    template_name = 'features/sippy_history.html'

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        chat_type = self.request.GET.get('type', 'plan')
        ctx['chat_type'] = chat_type
        ctx['conversations'] = SippyConversation.objects.filter(
            user=self.request.user, is_active=True, chat_type=chat_type
        ).order_by('-updated_at')[:20]
        return ctx

    def post(self, request, *args, **kwargs):
        """Handle delete."""
        delete_id = request.POST.get('delete_id')
        if delete_id:
            SippyConversation.objects.filter(
                pk=delete_id, user=request.user, is_active=True
            ).update(is_active=False)
        from django.shortcuts import redirect
        return redirect(request.get_full_path())


# ── Wishlist ─────────────────────────────────────────────────────

class WishlistView(SubscriptionRequiredMixin, TemplateView):
    template_name = 'features/wishlist.html'

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        items = WineWishlist.objects.filter(
            user=self.request.user, is_active=True
        ).select_related('menu_item', 'source_place').order_by('-created_at')
        ctx['items'] = items
        return ctx

    def post(self, request, *args, **kwargs):
        """Handle delete via htmx."""
        from django.http import HttpResponse
        item_id = request.POST.get('item_id')
        if item_id:
            WineWishlist.objects.filter(
                pk=item_id, user=request.user, is_active=True
            ).update(is_active=False)
        return HttpResponse('')


# ── Cellar ───────────────────────────────────────────────────────

class CellarView(SubscriptionRequiredMixin, TemplateView):
    template_name = 'features/cellar.html'

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        purchases = VisitWine.objects.filter(
            visit__user=self.request.user, is_active=True, purchased=True
        ).select_related('visit__place', 'menu_item')

        from decimal import Decimal
        ctx['total_bottles'] = purchases.aggregate(t=Sum('purchased_quantity'))['t'] or 0
        ctx['total_spend'] = purchases.aggregate(
            t=Sum(F('purchased_price') * F('purchased_quantity'))
        )['t'] or Decimal('0.00')
        ctx['unique_wines'] = purchases.values('wine_name').distinct().count()
        ctx['avg_price'] = purchases.filter(
            purchased_price__isnull=False
        ).aggregate(a=Avg('purchased_price'))['a']
        ctx['recent'] = purchases.order_by('-visit__visited_at')[:20]
        ctx['top_places'] = list(
            purchases.filter(purchased_price__isnull=False)
            .values(place_name=F('visit__place__name'))
            .annotate(
                total_spend=Sum(F('purchased_price') * F('purchased_quantity')),
                bottle_count=Sum('purchased_quantity'),
            ).order_by('-total_spend')[:5]
        )
        ctx['top_varietals'] = list(
            purchases.exclude(wine_type='')
            .values(varietal=F('wine_type'))
            .annotate(count=Sum('purchased_quantity'), avg_price=Avg('purchased_price'))
            .order_by('-count')[:8]
        )
        return ctx


# ── Badges ───────────────────────────────────────────────────────

BADGE_DEFINITIONS = [
    ("first_visit", "First Sip", "local_drink", "Complete your first check-in", "visits", 1),
    ("explorer_5", "Explorer", "explore", "Visit 5 different places", "visits", 5),
    ("explorer_10", "Seasoned Explorer", "travel_explore", "Visit 10 different places", "visits", 10),
    ("explorer_25", "Trailblazer", "public", "Visit 25 different places", "visits", 25),
    ("regular", "Regular", "repeat", "Visit the same place 3 times", "visits", 3),
    ("first_wine", "Wine Curious", "wine_bar", "Log your first wine", "wines", 1),
    ("wine_10", "Taster", "local_bar", "Log 10 wines", "wines", 10),
    ("wine_50", "Connoisseur", "emoji_events", "Log 50 wines", "wines", 50),
    ("wine_100", "Sommelier", "workspace_premium", "Log 100 wines", "wines", 100),
    ("variety_5", "Variety Seeker", "category", "Try 5 different varietals", "wines", 5),
    ("variety_10", "Open Minded", "psychology", "Try 10 different varietals", "wines", 10),
    ("five_star", "Five Star Find", "star", "Rate a wine 5 out of 5", "wines", 1),
    ("favorite_3", "Heart Collector", "favorite", "Mark 3 wines as favorites", "wines", 3),
    ("first_trip", "Road Tripper", "directions_car", "Complete your first trip", "trips", 1),
    ("trip_5", "Journey Master", "map", "Complete 5 trips", "trips", 5),
    ("big_trip", "Marathon Taster", "route", "Complete a trip with 5+ stops", "trips", 5),
    ("sippy_planner", "Sippy's Friend", "auto_awesome", "Plan a trip with Sippy", "ai", 1),
    ("sippy_3", "AI Explorer", "smart_toy", "Plan 3 trips with Sippy", "ai", 3),
    ("wishlist_5", "Bucket Lister", "bookmark", "Add 5 wines to your wishlist", "ai", 5),
    ("critic", "The Critic", "rate_review", "Rate 10 visits", "ratings", 10),
    ("generous", "Generous Pour", "thumb_up", "Give 5 ratings of 5/5", "ratings", 5),
    ("first_purchase", "Take-Home", "shopping_bag", "Buy your first bottle", "purchases", 1),
    ("collector", "Collector", "inventory_2", "Buy 10 bottles", "purchases", 10),
]


class BadgesView(SubscriptionRequiredMixin, TemplateView):
    template_name = 'features/badges.html'

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        user = self.request.user

        visits = VisitLog.objects.filter(user=user, is_active=True)
        total_visits = visits.count()
        unique_places = visits.values('place').distinct().count()
        max_visits_one_place = 0
        if total_visits:
            pc = visits.values('place').annotate(c=Count('id')).order_by('-c')
            if pc:
                max_visits_one_place = pc[0]['c']

        rated_visits = visits.filter(rating_overall__isnull=False).count()
        five_star_visits = visits.filter(rating_overall=5).count()

        wines = VisitWine.objects.filter(visit__user=user, is_active=True)
        total_wines = wines.count()
        unique_varietals = wines.exclude(wine_type='').values('wine_type').distinct().count()
        favorite_wines = wines.filter(is_favorite=True).count()
        five_star_wines = wines.filter(rating=5).count()
        purchased_count = wines.filter(purchased=True).count()

        completed_trips = Trip.objects.filter(
            members=user, is_active=True, status=Trip.Status.COMPLETED
        ).count()
        big_trips = Trip.objects.filter(
            members=user, is_active=True, status=Trip.Status.COMPLETED
        ).annotate(
            stop_count=Count('trip_stops', filter=Q(trip_stops__is_active=True))
        ).filter(stop_count__gte=5).count()

        sippy_plans = SippyConversation.objects.filter(
            user=user, chat_type='plan', phase='approved', is_active=True
        ).count()
        wishlist_count = WineWishlist.objects.filter(user=user, is_active=True).count()

        stats = {
            'total_visits': total_visits, 'unique_places': unique_places,
            'max_visits_one_place': max_visits_one_place,
            'rated_visits': rated_visits, 'five_star_visits': five_star_visits,
            'total_wines': total_wines, 'unique_varietals': unique_varietals,
            'favorite_wines': favorite_wines, 'five_star_wines': five_star_wines,
            'purchased_count': purchased_count, 'completed_trips': completed_trips,
            'big_trips': big_trips, 'sippy_plans': sippy_plans, 'wishlist_count': wishlist_count,
        }

        stat_map = {
            'first_visit': 'total_visits', 'explorer_5': 'unique_places',
            'explorer_10': 'unique_places', 'explorer_25': 'unique_places',
            'regular': 'max_visits_one_place',
            'first_wine': 'total_wines', 'wine_10': 'total_wines',
            'wine_50': 'total_wines', 'wine_100': 'total_wines',
            'variety_5': 'unique_varietals', 'variety_10': 'unique_varietals',
            'five_star': 'five_star_wines', 'favorite_3': 'favorite_wines',
            'first_trip': 'completed_trips', 'trip_5': 'completed_trips',
            'big_trip': 'big_trips',
            'sippy_planner': 'sippy_plans', 'sippy_3': 'sippy_plans',
            'wishlist_5': 'wishlist_count',
            'critic': 'rated_visits', 'generous': 'five_star_visits',
            'first_purchase': 'purchased_count', 'collector': 'purchased_count',
        }

        badges = []
        for badge_id, name, icon, description, category, threshold in BADGE_DEFINITIONS:
            current = stats.get(stat_map.get(badge_id, ''), 0)
            earned = current >= threshold
            progress = min(current / threshold, 1.0) if threshold > 0 else 0
            badges.append({
                'id': badge_id, 'name': name, 'icon': icon,
                'description': description, 'category': category,
                'earned': earned, 'progress': int(progress * 100),
            })

        earned_count = sum(1 for b in badges if b['earned'])
        ctx['badges'] = badges
        ctx['earned_count'] = earned_count
        ctx['total_count'] = len(badges)

        # Group by category
        categories = {}
        category_labels = {
            'visits': 'Explorer', 'wines': 'Wine & Beer', 'trips': 'Trips',
            'ai': 'Sippy & AI', 'ratings': 'Ratings', 'purchases': 'Purchases',
        }
        for b in badges:
            cat = b['category']
            categories.setdefault(cat, {'label': category_labels.get(cat, cat), 'badges': []})
            categories[cat]['badges'].append(b)
        ctx['categories'] = categories
        return ctx


# ── Journey Map ──────────────────────────────────────────────────

class JourneyMapView(SubscriptionRequiredMixin, TemplateView):
    template_name = 'features/journey_map.html'

    def get_context_data(self, **kwargs):
        from django.conf import settings
        ctx = super().get_context_data(**kwargs)
        user = self.request.user

        places = (
            VisitLog.objects.filter(user=user, is_active=True, place__is_active=True)
            .values(
                'place__id', 'place__name', 'place__place_type',
                'place__city', 'place__state',
                'place__latitude', 'place__longitude',
                'place__image_url', 'place__address', 'place__website', 'place__phone',
            )
            .annotate(visit_count=Count('id'), last_visited=Max('visited_at'))
            .filter(place__latitude__isnull=False, place__longitude__isnull=False)
            .order_by('-last_visited')
        )

        results = []
        for p in places:
            last_visit = (
                VisitLog.objects.filter(user=user, place_id=p['place__id'], is_active=True)
                .order_by('-visited_at').values_list('id', flat=True).first()
            )
            results.append({
                'place_id': str(p['place__id']),
                'name': p['place__name'],
                'place_type': p['place__place_type'],
                'city': p['place__city'] or '',
                'state': p['place__state'] or '',
                'lat': float(p['place__latitude']),
                'lng': float(p['place__longitude']),
                'image_url': p['place__image_url'] or '',
                'address': p['place__address'] or '',
                'website': p['place__website'] or '',
                'phone': p['place__phone'] or '',
                'visit_count': p['visit_count'],
                'last_visited': p['last_visited'].strftime('%b %d, %Y') if p['last_visited'] else '',
                'last_visit_id': str(last_visit) if last_visit else '',
            })

        ctx['places_json'] = json.dumps(results)
        ctx['total_places'] = len(results)
        ctx['google_maps_api_key'] = getattr(settings, 'GOOGLE_MAPS_API_KEY', '')
        return ctx


# ── Trip Recap ───────────────────────────────────────────────────

class TripRecapView(SubscriptionRequiredMixin, TemplateView):
    template_name = 'features/trip_recap.html'

    def get_context_data(self, **kwargs):
        ctx = super().get_context_data(**kwargs)
        trip = Trip.objects.get(pk=self.kwargs['pk'], members=self.request.user, is_active=True)
        ctx['trip'] = trip

        stops = trip.trip_stops.filter(is_active=True).select_related('place').order_by('order')
        member_user_ids = trip.trip_members.filter(
            is_active=True, user__isnull=False
        ).values_list('user_id', flat=True)
        place_ids = stops.values_list('place_id', flat=True)

        visits = VisitLog.objects.filter(
            user_id__in=member_user_ids, place_id__in=place_ids, is_active=True
        ).select_related('place', 'user')

        stop_recaps = []
        total_wines = 0
        for stop in stops:
            place = stop.place
            stop_visits = [v for v in visits if v.place_id == place.id]
            visit_ids = [v.id for v in stop_visits]
            wines = VisitWine.objects.filter(
                visit_id__in=visit_ids, is_active=True
            ).select_related('menu_item')

            wine_list = []
            for w in wines:
                total_wines += 1
                wine_list.append({
                    'name': w.display_name or w.wine_name or 'Unknown',
                    'type': w.wine_type or '',
                    'rating': w.rating,
                    'is_favorite': w.is_favorite,
                    'photo': w.photo or '',
                })

            avg_ratings = {}
            if stop_visits:
                avg_ratings = VisitLog.objects.filter(id__in=visit_ids).aggregate(
                    avg_overall=Avg('rating_overall'),
                    avg_staff=Avg('rating_staff'),
                    avg_ambience=Avg('rating_ambience'),
                    avg_food=Avg('rating_food'),
                )

            stop_recaps.append({
                'stop': stop, 'place': place,
                'checked_in': len(stop_visits) > 0,
                'wines': wine_list, 'avg_ratings': avg_ratings,
            })

        members = trip.trip_members.filter(is_active=True).select_related('user')
        total_miles = sum(float(s.travel_miles or 0) for s in stops)

        ctx['stop_recaps'] = stop_recaps
        ctx['total_wines'] = total_wines
        ctx['total_miles'] = round(total_miles, 1)
        ctx['members'] = members
        return ctx
