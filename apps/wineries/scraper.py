"""
Wine menu scraper — fetches a winery's website, discovers wine-specific pages,
and uses Claude to extract their wine list into structured data.
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
        timeout=12,
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

    # Third-party shops come first (most reliable for JS-rendered winery sites)
    result = sorted(third_party_shops)
    result.extend(sorted(wine_urls, key=priority))
    return result


def extract_wines_from_html(html: str, winery_name: str) -> list[dict]:
    """Use Claude to extract a structured wine list from HTML."""
    from apps.api.ai_utils import get_claude

    prompt = f"""You are extracting drinks/beverages from the website of "{winery_name}".

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
        logger.warning("Claude wine extraction failed for %s: %s", winery_name, e)
        return []


def scrape_and_cache_wines(winery) -> list:
    """
    Main entry point: scrape winery website, discover wine pages,
    extract wines, cache as Wine records.
    """
    from apps.wineries.models import Wine

    if not winery.website:
        return list(Wine.objects.filter(winery=winery))

    # Return cached if scraped recently
    if (
        winery.wine_menu_last_scraped
        and winery.wine_menu_last_scraped > timezone.now() - timedelta(days=CACHE_DAYS)
        and Wine.objects.filter(winery=winery).exists()
    ):
        return list(Wine.objects.filter(winery=winery))

    try:
        # Fetch homepage
        homepage_html = fetch_wine_page(winery.website)
        if not homepage_html:
            return list(Wine.objects.filter(winery=winery))

        # Discover wine-specific pages from links
        wine_page_urls = discover_wine_pages(winery.website, homepage_html)

        # If no wine pages discovered, try common subpaths
        if not wine_page_urls:
            base = winery.website.rstrip("/")
            for path in COMMON_WINE_PATHS:
                wine_page_urls.append(base + path)

        logger.info("Trying %d wine pages for %s: %s", len(wine_page_urls), winery.name, wine_page_urls[:5])

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

        # Combine all known third-party URLs
        all_third_party = list(set(third_party + discovered_third_party))
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

        extracted = extract_wines_from_html(all_html, winery.name)
        logger.info("Extracted %d wines for %s (from %d subpages)", len(extracted), winery.name, pages_fetched)

        if not extracted:
            winery.wine_menu_last_scraped = timezone.now()
            winery.save(update_fields=["wine_menu_last_scraped", "updated_at"])
            return list(Wine.objects.filter(winery=winery))

        # Deduplicate by name+vintage
        seen = set()
        wines = []
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

            wine, created = Wine.objects.get_or_create(
                winery=winery,
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
                if not wine.varietal and item.get("varietal"):
                    wine.varietal = item["varietal"]
                    changed.append("varietal")
                if not wine.description and item.get("description"):
                    wine.description = item["description"]
                    changed.append("description")
                if price and wine.price != price:
                    wine.price = price
                    changed.append("price")
                if image_url and wine.image_url != image_url:
                    wine.image_url = image_url
                    changed.append("image_url")
                if changed:
                    wine.save(update_fields=changed + ["updated_at"])
            wines.append(wine)

        winery.wine_menu_last_scraped = timezone.now()
        winery.save(update_fields=["wine_menu_last_scraped", "updated_at"])
        # Return all wines for this winery (including previously scraped ones)
        return list(Wine.objects.filter(winery=winery))

    except Exception as e:
        logger.exception("Wine scraping failed for %s: %s", winery.name, e)
        return list(Wine.objects.filter(winery=winery))
