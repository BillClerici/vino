"""
Menu item scraper — fetches a place's website, discovers menu-specific pages,
and uses Claude to extract their wine/beer list into structured data.
"""

import json
import logging
import re
from datetime import timedelta
from urllib.parse import urljoin

import httpx
from django.utils import timezone

logger = logging.getLogger(__name__)

CACHE_DAYS = 7

# Patterns that indicate a wine or beer menu page
WINE_PATH_PATTERNS = re.compile(
    r"/(our-)?wines?(/|$)|/wine-menu|/wine-list|/tasting|/varietals|/collection|/cellar"
    r"|/(our-)?beers?(/|$)|/beer-menu|/beer-list|/tap-list|/on-tap|/brews"
    r"|/shop|/menu|/products|/store|/purchase",
    re.IGNORECASE,
)

# Common subpaths to try if nothing found in links
COMMON_WINE_PATHS = [
    "/wines", "/our-wines", "/wine-menu", "/wine-list",
    "/beers", "/our-beers", "/beer-menu", "/tap-list", "/on-tap",
    "/shop", "/menu", "/tasting-menu", "/products",
]


def _make_client():
    return httpx.Client(
        timeout=120,
        follow_redirects=True,
        headers={
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        },
    )


def _clean_html(html: str) -> str:
    """Strip scripts, styles, SVGs, and nav/footer clutter."""
    html = re.sub(r"<(script|style|svg|noscript|iframe)[^>]*>.*?</\1>", "", html, flags=re.DOTALL | re.IGNORECASE)
    # Remove HTML comments
    html = re.sub(r"<!--.*?-->", "", html, flags=re.DOTALL)
    # Collapse whitespace
    html = re.sub(r"\s{2,}", " ", html)
    if len(html) > 80_000:
        html = html[:80_000]
    return html


def fetch_wine_page(url: str) -> str | None:
    """Fetch a URL and return cleaned HTML, or None on failure."""
    if not url:
        return None
    try:
        with _make_client() as client:
            resp = client.get(url)
            resp.raise_for_status()
            return _clean_html(resp.text)
    except Exception as e:
        logger.warning("Failed to fetch %s: %s", url, e)
        return None


def discover_wine_pages(base_url: str, homepage_html: str) -> list[str]:
    """Find links to wine-specific pages from the homepage HTML."""
    links = re.findall(r'href="([^"]*)"', homepage_html, re.IGNORECASE)
    wine_urls = set()
    third_party_shops = set()

    for link in links:
        full = urljoin(base_url, link).rstrip("/")

        # Check for third-party wine shop platforms (server-rendered, reliable)
        if re.search(r"vinoshipper\.com/shop/|shop\.\w+\.com|\.myshopify\.com", full, re.IGNORECASE):
            # Get the shop root, not a specific product/join page
            match = re.match(r"(https?://vinoshipper\.com/shop/[^/]+)", full)
            if match:
                third_party_shops.add(match.group(1))
            else:
                third_party_shops.add(full)
            continue

        # Same-domain wine pages
        base_domain = base_url.split("//")[-1].split("/")[0]
        if base_domain not in full:
            continue
        if WINE_PATH_PATTERNS.search(full):
            wine_urls.add(full)
    # Prioritize: third-party shops first (server-rendered), then menu/list pages
    def priority(url):
        u = url.lower()
        if "menu" in u or "list" in u:
            return 0
        if "shop" in u or "purchase" in u:
            return 1
        if "tasting" in u:
            return 2
        return 3

    # Third-party shops come first (most reliable for JS-rendered sites)
    result = sorted(third_party_shops)
    result.extend(sorted(wine_urls, key=priority))
    return result


def extract_wines_from_html(html: str, place_name: str) -> list[dict]:
    """Use Claude to extract a structured wine list from HTML."""
    from apps.api.ai_utils import get_claude

    prompt = f"""You are extracting drinks/beverages from the website of "{place_name}".

Analyze the HTML below and find every wine or beer mentioned. For each item, extract:
- "name": string (the drink's name, e.g. "Reserve Chardonnay" or "Hazy IPA")
- "varietal": string (for wine: e.g. "Chardonnay", "Cabernet Sauvignon". For beer: e.g. "IPA", "Stout", "Lager", "Pilsner", "Amber Ale")
- "vintage": integer or null (mainly for wine, e.g. 2022. Usually null for beer.)
- "description": string (brief tasting notes or description from the site, 1-2 sentences)
- "wine_type": string (for wine: one of "Red", "White", "Rosé", "Sparkling". For beer: one of "Ale", "Lager", "Stout", "IPA", "Sour", "Other". Use "Other" if unsure.)
- "price": number or null (price in dollars, e.g. 29.99. Look for prices near each item. Use null if no price found.)
- "image_url": string or null (the full absolute URL of the product image if found in a nearby <img> tag src attribute. Must be a complete URL starting with http. Use null if no image found.)

Be thorough — look for drink names in menus, product listings, tasting notes, tap lists, club pages, and anywhere drinks are listed.
For images, look for <img> tags near each entry — product photos, bottle/can shots, or label images. Convert relative URLs to absolute using the site's domain. Ignore tiny icons, logos, and decorative images.
If a varietal isn't explicitly stated, infer it from the name if possible.
Return a JSON array. If no drinks found, return [].
Return ONLY the JSON array, no other text.

HTML:
{html}"""

    try:
        llm = get_claude()
        response = llm.invoke(prompt)
        content = response.content.strip()
        if "```" in content:
            match = re.search(r"\[.*\]", content, re.DOTALL)
            if match:
                content = match.group(0)
        wines = json.loads(content)
        if not isinstance(wines, list):
            return []
        return wines
    except Exception as e:
        logger.warning("Claude menu extraction failed for %s: %s", place_name, e)
        return []


def scrape_and_cache_menu_items(place) -> list:
    """
    Main entry point: scrape place website, discover menu pages,
    extract menu items, cache as MenuItem records.
    """
    from apps.wineries.models import MenuItem

    if not place.website:
        return list(MenuItem.objects.filter(place=place))

    # Return cached if scraped recently
    if (
        place.wine_menu_last_scraped
        and place.wine_menu_last_scraped > timezone.now() - timedelta(days=CACHE_DAYS)
        and MenuItem.objects.filter(place=place).exists()
    ):
        return list(MenuItem.objects.filter(place=place))

    try:
        # Fetch homepage
        homepage_html = fetch_wine_page(place.website)
        if not homepage_html:
            return list(MenuItem.objects.filter(place=place))

        # Discover wine-specific pages from links
        wine_page_urls = discover_wine_pages(place.website, homepage_html)

        # If no wine pages discovered, try common subpaths
        if not wine_page_urls:
            base = place.website.rstrip("/")
            for path in COMMON_WINE_PATHS:
                wine_page_urls.append(base + path)

        logger.info("Trying %d menu pages for %s: %s", len(wine_page_urls), place.name, wine_page_urls[:5])

        # Separate third-party shops from same-domain pages
        third_party = [u for u in wine_page_urls if "vinoshipper.com" in u or ".myshopify.com" in u]
        same_domain = [u for u in wine_page_urls if u not in third_party]

        all_html = ""
        pages_fetched = 0
        discovered_third_party = []

        # First: try same-domain wine pages (up to 3) and look for third-party links
        for wp_url in same_domain[:3]:
            page_html = fetch_wine_page(wp_url)
            if page_html and len(page_html) > 500:
                # Scan for third-party shop links before adding
                for match in re.finditer(r'href="(https?://vinoshipper\.com/shop/[^"/]+)', page_html, re.IGNORECASE):
                    discovered_third_party.append(match.group(1))
                for match in re.finditer(r'href="(https?://[^"]*\.myshopify\.com[^"]*)"', page_html, re.IGNORECASE):
                    discovered_third_party.append(match.group(1))
                all_html += f"\n<!-- PAGE: {wp_url} -->\n{page_html}"
                pages_fetched += 1

        # Combine all known third-party URLs, prioritize Vinoshipper (server-rendered)
        all_third_party = list(set(third_party + discovered_third_party))
        # Sort: vinoshipper first (most reliable), then others
        all_third_party.sort(key=lambda u: 0 if "vinoshipper.com" in u else 1)
        if all_third_party:
            logger.info("Found third-party shops: %s", all_third_party)

        # If we have third-party shops, use ONLY those for extraction (cleanest data)
        if all_third_party:
            all_html = ""
            pages_fetched = 0
            for tp_url in all_third_party[:2]:
                page_html = fetch_wine_page(tp_url)
                if page_html and len(page_html) > 500:
                    all_html += f"\n<!-- PAGE: {tp_url} -->\n{page_html}"
                    pages_fetched += 1

        # Fallback to homepage if nothing else worked
        if not all_html:
            all_html = homepage_html

        # Truncate combined HTML if needed
        if len(all_html) > 80_000:
            all_html = all_html[:80_000]

        extracted = extract_wines_from_html(all_html, place.name)
        logger.info("Extracted %d menu items for %s (from %d subpages)", len(extracted), place.name, pages_fetched)

        if not extracted:
            place.wine_menu_last_scraped = timezone.now()
            place.save(update_fields=["wine_menu_last_scraped", "updated_at"])
            return list(MenuItem.objects.filter(place=place))

        # Deduplicate by name+vintage
        seen = set()
        menu_items = []
        for item in extracted:
            name = item.get("name", "").strip()
            if not name:
                continue
            key = (name.lower(), item.get("vintage"))
            if key in seen:
                continue
            seen.add(key)

            image_url = item.get("image_url", "") or ""
            price = item.get("price")
            if price is not None:
                try:
                    price = round(float(price), 2)
                except (ValueError, TypeError):
                    price = None

            menu_item, created = MenuItem.objects.get_or_create(
                place=place,
                name=name,
                vintage=item.get("vintage"),
                defaults={
                    "varietal": item.get("varietal", "") or "",
                    "description": item.get("description", "") or "",
                    "price": price,
                    "image_url": image_url,
                    "metadata": {"scraped": True, "wine_type": item.get("wine_type", "")},
                },
            )
            if not created:
                changed = []
                if not menu_item.varietal and item.get("varietal"):
                    menu_item.varietal = item["varietal"]
                    changed.append("varietal")
                if not menu_item.description and item.get("description"):
                    menu_item.description = item["description"]
                    changed.append("description")
                if price and menu_item.price != price:
                    menu_item.price = price
                    changed.append("price")
                if image_url and menu_item.image_url != image_url:
                    menu_item.image_url = image_url
                    changed.append("image_url")
                if changed:
                    menu_item.save(update_fields=changed + ["updated_at"])
            menu_items.append(menu_item)

        place.wine_menu_last_scraped = timezone.now()
        place.save(update_fields=["wine_menu_last_scraped", "updated_at"])
        # Return all menu items for this place (including previously scraped ones)
        return list(MenuItem.objects.filter(place=place))

    except Exception as e:
        logger.exception("Menu scraping failed for %s: %s", place.name, e)
        return list(MenuItem.objects.filter(place=place))
