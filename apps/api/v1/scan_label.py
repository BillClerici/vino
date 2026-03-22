"""
Wine label scanner endpoint — accepts an image and uses Gemini Vision
to extract wine details (name, varietal, vintage, description).
"""

import base64
import io
import logging

from PIL import Image
from rest_framework import status
from rest_framework.parsers import MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .permissions import HasActiveSubscription

logger = logging.getLogger(__name__)

MAX_PHOTO_SIZE = 5 * 1024 * 1024  # 5 MB
MAX_DIMENSION = 1024


def _prepare_image_for_vision(uploaded_file) -> str:
    """Resize image and return as base64 JPEG string for Gemini Vision."""
    img = Image.open(uploaded_file)
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    if max(img.size) > MAX_DIMENSION:
        img.thumbnail((MAX_DIMENSION, MAX_DIMENSION), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=85, optimize=True)
    return base64.b64encode(buf.getvalue()).decode("utf-8")


SCAN_PROMPT = """You are a wine/beer label expert. Analyze this label image and extract:

1. **name** — The full product name (e.g. "Château Margaux 2015")
2. **varietal** — The grape variety or beer style (e.g. "Cabernet Sauvignon", "IPA")
3. **vintage** — The vintage year as a string, or empty string if none
4. **description** — A brief 1-2 sentence tasting note or description based on what you can see on the label

Return ONLY valid JSON with these four keys, no markdown formatting:
{"name": "...", "varietal": "...", "vintage": "...", "description": "..."}

If you cannot determine a field, use an empty string. Do not guess — only extract what is clearly visible on the label."""


class ScanLabelView(APIView):
    """POST an image of a wine/beer label and get extracted details via Gemini Vision."""

    permission_classes = [IsAuthenticated, HasActiveSubscription]
    parser_classes = [MultiPartParser]

    def post(self, request):
        uploaded = request.FILES.get("file")
        if not uploaded:
            return Response(
                {"detail": "No file provided."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if uploaded.size > MAX_PHOTO_SIZE:
            return Response(
                {"detail": "File too large. Maximum size is 5 MB."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            image_b64 = _prepare_image_for_vision(uploaded)
        except Exception:
            return Response(
                {"detail": "Invalid image file."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            from apps.api.ai_utils import get_gemini
            from langchain_core.messages import HumanMessage

            llm = get_gemini()
            message = HumanMessage(
                content=[
                    {"type": "text", "text": SCAN_PROMPT},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{image_b64}",
                        },
                    },
                ],
            )
            response = llm.invoke([message])
            raw = response.content.strip()

            # Strip markdown fences if present
            if raw.startswith("```"):
                raw = raw.split("\n", 1)[1] if "\n" in raw else raw[3:]
                if raw.endswith("```"):
                    raw = raw[:-3]
                raw = raw.strip()

            import json

            result = json.loads(raw)
            return Response({
                "name": result.get("name", ""),
                "varietal": result.get("varietal", ""),
                "vintage": result.get("vintage", ""),
                "description": result.get("description", ""),
            })

        except json.JSONDecodeError:
            logger.exception("Gemini returned invalid JSON: %s", raw)
            return Response(
                {"detail": "Could not parse label. Try a clearer photo."},
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )
        except Exception:
            logger.exception("Label scan failed")
            return Response(
                {"detail": "Label scan failed. Please try again."},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
