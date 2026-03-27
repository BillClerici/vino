"""
Multi-LLM initialization utilities for Vino Trip.

- Claude 3.5 Sonnet (via ChatAnthropic): general reasoning, palate analysis,
  sentiment analysis, invitation text, itinerary planning.
- Gemini 1.5 Pro (via ChatGoogleGenerativeAI): vision tasks such as
  wine label recognition and image processing.
"""

from functools import lru_cache

from django.conf import settings


@lru_cache(maxsize=1)
def get_claude():
    """
    Initialize ChatAnthropic with Claude Sonnet for general logic tasks.

    Returns a singleton instance (cached). Thread-safe for Django request handling.
    """
    from langchain_anthropic import ChatAnthropic

    return ChatAnthropic(
        model="claude-sonnet-4-20250514",
        api_key=settings.ANTHROPIC_API_KEY,
        max_tokens=4096,
        temperature=0.3,
    )


@lru_cache(maxsize=1)
def get_claude_fast():
    """
    Initialize ChatAnthropic with Claude Haiku for fast tool-calling tasks.

    Used for trip planning where speed matters more than deep reasoning.
    ~5-8x faster output than Sonnet with strong tool-calling capability.
    """
    from langchain_anthropic import ChatAnthropic

    return ChatAnthropic(
        model="claude-haiku-4-5-20251001",
        api_key=settings.ANTHROPIC_API_KEY,
        max_tokens=4096,
        temperature=0.3,
    )


@lru_cache(maxsize=1)
def get_gemini():
    """
    Initialize ChatGoogleGenerativeAI with Gemini 1.5 Pro for vision tasks.

    Used primarily for wine label image processing.
    """
    from langchain_google_genai import ChatGoogleGenerativeAI

    return ChatGoogleGenerativeAI(
        model="gemini-1.5-pro",
        google_api_key=settings.GOOGLE_API_KEY,
        temperature=0.1,
    )
