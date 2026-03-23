import json
import logging

from django.db.models import Avg, Count, F
from django.utils import timezone
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.palate.models import PalateProfile
from apps.visits.models import VisitLog, VisitWine

from ..permissions import HasActiveSubscription
from .serializers import PalateProfileSerializer

logger = logging.getLogger(__name__)


class PalateProfileView(APIView):
    permission_classes = [HasActiveSubscription]

    def get(self, request):
        """User's palate profile with visit stats and top varietals."""
        profile, _ = PalateProfile.objects.get_or_create(user=request.user)

        visits = VisitLog.objects.filter(user=request.user, is_active=True)
        visit_stats = visits.aggregate(
            total_visits=Count("id"),
            avg_staff=Avg("rating_staff"),
            avg_ambience=Avg("rating_ambience"),
            avg_food=Avg("rating_food"),
            avg_overall=Avg("rating_overall"),
        )

        # Top varietals from wines tasted
        wines = VisitWine.objects.filter(
            visit__user=request.user, is_active=True
        )

        # Count varietals from menu items
        top_from_menu = list(
            wines.filter(menu_item__isnull=False)
            .values(varietal=F("menu_item__varietal"))
            .annotate(count=Count("id"), avg_rating=Avg("rating"))
            .order_by("-count")[:10]
        )

        # Count varietals from ad-hoc entries
        top_from_adhoc = list(
            wines.filter(wine_type__gt="")
            .values(varietal=F("wine_type"))
            .annotate(count=Count("id"), avg_rating=Avg("rating"))
            .order_by("-count")[:10]
        )

        # Merge and sort
        varietal_map = {}
        for v in top_from_menu + top_from_adhoc:
            key = v["varietal"]
            if not key:
                continue
            if key in varietal_map:
                varietal_map[key]["count"] += v["count"]
            else:
                varietal_map[key] = {
                    "varietal": key,
                    "count": v["count"],
                    "avg_rating": v["avg_rating"],
                }

        top_varietals = sorted(varietal_map.values(), key=lambda x: -x["count"])[:10]

        return Response({
            "profile": PalateProfileSerializer(profile).data,
            "visit_stats": visit_stats,
            "top_varietals": top_varietals,
        })


def _build_tasting_history(user) -> str:
    """Build a text summary of the user's tasting history for Claude."""
    wines = (
        VisitWine.objects.filter(visit__user=user, is_active=True)
        .select_related("visit__place", "menu_item")
        .order_by("-visit__visited_at")[:50]
    )
    visits = (
        VisitLog.objects.filter(user=user, is_active=True)
        .select_related("place")
        .order_by("-visited_at")[:20]
    )

    lines = ["## Recent Visits"]
    for v in visits:
        place_name = v.place.name if v.place else "Unknown"
        lines.append(
            f"- {place_name} ({v.visited_at:%Y-%m-%d}): "
            f"overall={v.rating_overall}/5, staff={v.rating_staff}/5, "
            f"ambience={v.rating_ambience}/5, food={v.rating_food}/5"
            f"{f' — {v.notes}' if v.notes else ''}"
        )

    lines.append("\n## Wines Tasted")
    for w in wines:
        name = w.display_name or "Unknown"
        wine_type = w.wine_type or (w.menu_item.varietal if w.menu_item else "")
        rating_str = f"{w.rating}/5" if w.rating else "unrated"
        fav = " [FAVORITE]" if w.is_favorite else ""
        notes = f" — {w.tasting_notes}" if w.tasting_notes else ""
        lines.append(f"- {name} ({wine_type}): {rating_str}{fav}{notes}")

    return "\n".join(lines)


ANALYZE_PROMPT = """You are an expert sommelier analyzing a wine lover's tasting history.
Based on the data below, create a detailed palate profile. Return valid JSON with these keys:

{
  "summary": "A 2-3 sentence natural-language description of their palate (write in second person, e.g. 'You tend to...')",
  "sweetness": "dry|off-dry|medium|sweet",
  "body": "light|medium-light|medium|medium-full|full",
  "acidity": "low|medium|high",
  "tannin": "low|medium|high",
  "flavor_notes": ["list", "of", "preferred", "flavors"],
  "favorite_styles": ["list", "of", "wine/beer", "styles"],
  "adventurousness": "low|medium|high",
  "recommendations": ["3-5 specific wines or styles they should try next"]
}

TASTING HISTORY:
"""


class PalateAnalyzeView(APIView):
    """POST to analyze the user's tasting history and generate an AI palate profile."""

    permission_classes = [HasActiveSubscription]

    def post(self, request):
        history = _build_tasting_history(request.user)

        if "No wines" in history and "No visits" in history:
            return Response(
                {"detail": "Log some tastings first to generate your palate profile."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            from langchain_core.messages import HumanMessage

            from apps.api.ai_utils import get_claude

            llm = get_claude()
            message = HumanMessage(content=ANALYZE_PROMPT + history)
            response = llm.invoke([message])
            raw = response.content.strip()

            # Strip markdown fences
            if raw.startswith("```"):
                raw = raw.split("\n", 1)[1] if "\n" in raw else raw[3:]
                if raw.endswith("```"):
                    raw = raw[:-3]
                raw = raw.strip()

            preferences = json.loads(raw)

            # Save to profile
            profile, _ = PalateProfile.objects.get_or_create(user=request.user)
            profile.preferences = preferences
            profile.last_analyzed_at = timezone.now()
            profile.analysis_version = (profile.analysis_version or 0) + 1
            profile.save(update_fields=["preferences", "last_analyzed_at", "analysis_version", "updated_at"])

            return Response({
                "profile": PalateProfileSerializer(profile).data,
                "preferences": preferences,
            })

        except Exception:
            logger.exception("Palate analysis failed")
            return Response(
                {"detail": "Analysis failed. Please try again."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )


CHAT_SYSTEM = """You are Vino, a friendly and knowledgeable AI sommelier. You have access to the user's palate profile and tasting history. Give personalized wine and beer recommendations, answer questions about varietals and styles, and help them explore new flavors.

Keep responses conversational but concise (2-4 sentences unless they ask for detail). Use the tasting data to personalize every answer. If they ask about something unrelated to wine, beer, or food, gently redirect."""


class PalateChatView(APIView):
    """POST with a message to chat with the AI sommelier."""

    permission_classes = [HasActiveSubscription]

    def post(self, request):
        user_message = request.data.get("message", "").strip()
        if not user_message:
            return Response(
                {"detail": "Message is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        history = _build_tasting_history(request.user)
        profile, _ = PalateProfile.objects.get_or_create(user=request.user)
        prefs = profile.preferences or {}

        context = f"""## User's Palate Profile
{json.dumps(prefs, indent=2) if prefs else 'Not yet analyzed — base your answers on their tasting history.'}

{history}"""

        try:
            from langchain_core.messages import HumanMessage, SystemMessage

            from apps.api.ai_utils import get_claude

            llm = get_claude()
            messages = [
                SystemMessage(content=CHAT_SYSTEM + "\n\n" + context),
                HumanMessage(content=user_message),
            ]

            # Include conversation history if provided
            chat_history = request.data.get("history", [])
            if chat_history:
                from langchain_core.messages import AIMessage
                full_messages = [messages[0]]  # system
                for msg in chat_history[-10:]:  # last 10 messages
                    role = msg.get("role", "")
                    content = msg.get("content", "")
                    if role == "user":
                        full_messages.append(HumanMessage(content=content))
                    elif role == "assistant":
                        full_messages.append(AIMessage(content=content))
                full_messages.append(messages[-1])  # current user message
                messages = full_messages

            response = llm.invoke(messages)
            return Response({"reply": response.content})

        except Exception:
            logger.exception("Palate chat failed")
            return Response(
                {"detail": "Chat failed. Please try again."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
