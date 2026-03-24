"""
LangChain tools for the Vino Trip Planner agent.

These tools are bound to the Claude LLM so the agent can search for places
and calculate drive times during trip planning conversations.
"""

import logging

from langchain_core.tools import tool

logger = logging.getLogger(__name__)


@tool
def search_places(query: str, region: str = "", place_type: str = "winery", latitude: float = 0.0, longitude: float = 0.0) -> list[dict]:  # noqa: E501
    """Search for wineries, breweries, or restaurants by name or region.

    Args:
        query: Search query (e.g. "Pinot Noir wineries", "craft breweries")
        region: City, state, or region to search in (e.g. "Napa Valley, CA")
        place_type: Type of place — "winery", "brewery", or "restaurant"
        latitude: Optional center latitude for "near me" searches (GPS coordinate)
        longitude: Optional center longitude for "near me" searches (GPS coordinate)

    Returns:
        List of places with name, address, city, state, lat, lng, description, etc.
    """
    from django.conf import settings

    from apps.wineries.models import Place

    results = []
    seen_names = set()

    # 1. Search local database first
    db_qs = Place.objects.filter(is_active=True)
    if place_type:
        db_qs = db_qs.filter(place_type=place_type)
    if latitude and longitude:
        # Location-based search: filter places within ~30 miles (~0.45 degrees)
        db_qs = db_qs.filter(
            latitude__isnull=False, longitude__isnull=False,
            latitude__gte=latitude - 0.45, latitude__lte=latitude + 0.45,
            longitude__gte=longitude - 0.55, longitude__lte=longitude + 0.55,
        )
    elif region:
        # Try city or state match
        parts = [p.strip() for p in region.split(",")]
        if len(parts) >= 2:
            db_qs = db_qs.filter(city__icontains=parts[0], state__icontains=parts[1])
        else:
            db_qs = db_qs.filter(city__icontains=parts[0]) | db_qs.filter(state__icontains=parts[0])
    if query:
        db_qs = db_qs.filter(name__icontains=query)

    for p in db_qs[:10]:
        key = p.name.lower().strip()
        if key not in seen_names:
            seen_names.add(key)
            results.append({
                "name": p.name,
                "address": p.address or "",
                "city": p.city or "",
                "state": p.state or "",
                "latitude": float(p.latitude) if p.latitude else None,
                "longitude": float(p.longitude) if p.longitude else None,
                "place_type": p.place_type,
                "website": p.website or "",
                "description": p.description or "",
                "image_url": p.image_url or "",
                "source": "database",
            })

    # 2. Search Google Places API if we have fewer than 5 results
    if len(results) < 5:
        api_key = getattr(settings, "GOOGLE_MAPS_API_KEY", "")
        if api_key:
            try:
                import httpx

                search_query = query
                if region:
                    search_query += f" {region}"
                if place_type and place_type not in query.lower():
                    search_query += f" {place_type}"

                with httpx.Client(timeout=10) as client:
                    request_body: dict = {
                        "textQuery": search_query,
                        "maxResultCount": 5,
                    }
                    # Add location bias when GPS coordinates are provided
                    if latitude and longitude:
                        request_body["locationBias"] = {
                            "circle": {
                                "center": {
                                    "latitude": latitude,
                                    "longitude": longitude,
                                },
                                "radius": 48280.0,  # 30 miles in meters
                            }
                        }
                    resp = client.post(
                        "https://places.googleapis.com/v1/places:searchText",
                        headers={
                            "Content-Type": "application/json",
                            "X-Goog-Api-Key": api_key,
                            "X-Goog-FieldMask": (
                                "places.displayName,places.formattedAddress,"
                                "places.nationalPhoneNumber,places.websiteUri,"
                                "places.editorialSummary,places.photos,places.location"
                            ),
                        },
                        json=request_body,
                    )
                    resp.raise_for_status()
                    data = resp.json()

                from apps.core.utils import parse_google_address

                for gp in data.get("places", []):
                    name = gp.get("displayName", {}).get("text", "")
                    key = name.lower().strip()
                    if key in seen_names:
                        continue
                    seen_names.add(key)

                    raw_addr = gp.get("formattedAddress", "")
                    parsed = parse_google_address(raw_addr)
                    location = gp.get("location", {})

                    image_url = ""
                    photos = gp.get("photos", [])
                    if photos:
                        photo_name = photos[0].get("name", "")
                        if photo_name:
                            image_url = f"https://places.googleapis.com/v1/{photo_name}/media?maxWidthPx=400&key={api_key}"

                    results.append({
                        "name": name,
                        "address": parsed["address"],
                        "city": parsed["city"],
                        "state": parsed["state"],
                        "latitude": location.get("latitude"),
                        "longitude": location.get("longitude"),
                        "place_type": place_type or "winery",
                        "website": gp.get("websiteUri", ""),
                        "phone": gp.get("nationalPhoneNumber", ""),
                        "description": (
                            gp.get("editorialSummary", {}).get("text", "")
                            if gp.get("editorialSummary")
                            else ""
                        ),
                        "image_url": image_url,
                        "source": "google",
                    })
            except Exception:
                logger.exception("Google Places search failed in tool")

    return results[:10]


@tool
def get_drive_time(
    origin_lat: float, origin_lng: float, dest_lat: float, dest_lng: float
) -> dict:
    """Get driving time and distance between two locations.

    Args:
        origin_lat: Origin latitude
        origin_lng: Origin longitude
        dest_lat: Destination latitude
        dest_lng: Destination longitude

    Returns:
        Dict with drive_minutes and miles.
    """
    from django.conf import settings

    api_key = getattr(settings, "GOOGLE_MAPS_API_KEY", "")
    if not api_key:
        return {"drive_minutes": None, "miles": None, "error": "No API key"}

    try:
        import httpx

        with httpx.Client(timeout=15) as client:
            resp = client.post(
                "https://routes.googleapis.com/directions/v2:computeRoutes",
                headers={
                    "Content-Type": "application/json",
                    "X-Goog-Api-Key": api_key,
                    "X-Goog-FieldMask": "routes.duration,routes.distanceMeters",
                },
                json={
                    "origin": {"location": {"latLng": {"latitude": origin_lat, "longitude": origin_lng}}},
                    "destination": {"location": {"latLng": {"latitude": dest_lat, "longitude": dest_lng}}},
                    "travelMode": "DRIVE",
                    "units": "IMPERIAL",
                },
            )
            resp.raise_for_status()
            data = resp.json()
            routes = data.get("routes", [])
            if routes:
                route = routes[0]
                duration_sec = int(route.get("duration", "0s").replace("s", ""))
                distance_m = route.get("distanceMeters", 0)
                return {
                    "drive_minutes": round(duration_sec / 60),
                    "miles": round(distance_m / 1609.34, 1),
                }
    except Exception:
        logger.exception("Drive time calculation failed in tool")

    return {"drive_minutes": None, "miles": None}
