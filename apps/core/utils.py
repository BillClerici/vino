import re


def parse_google_address(formatted_address):
    """Parse a Google Maps formatted address into components.

    Handles US-style addresses like:
        "125 Hidden Vines Ln, Dobson, NC 27017, USA"
        "5543 Crater Rd, Hamptonville, NC 27020, USA"
        "170 Heritage Vines Way, Elkin, NC 28621"
        "Dobson, NC 27017"

    Returns dict with: address, city, state, zip_code, country
    """
    result = {
        "address": "",
        "city": "",
        "state": "",
        "zip_code": "",
        "country": "US",
    }

    if not formatted_address:
        return result

    addr = formatted_address.strip()
    parts = [p.strip() for p in addr.split(",")]

    if not parts:
        return result

    # Remove country if last part (e.g., "USA", "US", "United States")
    country_patterns = {"usa", "us", "united states"}
    if parts[-1].strip().lower() in country_patterns:
        result["country"] = "US"
        parts = parts[:-1]

    if not parts:
        return result

    if len(parts) >= 3:
        # "125 Hidden Vines Ln, Dobson, NC 27017"
        result["address"] = parts[0]
        result["city"] = parts[-2].strip()
        state_zip = parts[-1].strip()
    elif len(parts) == 2:
        # Could be "Dobson, NC 27017" or "125 Main St, Dobson"
        state_zip_match = re.match(r"^([A-Z]{2})\s+(\d{5}(?:-\d{4})?)$", parts[-1].strip())
        if state_zip_match:
            result["city"] = parts[0].strip()
            state_zip = parts[-1].strip()
        else:
            result["address"] = parts[0]
            result["city"] = parts[1].strip()
            return result
    elif len(parts) == 1:
        result["address"] = parts[0]
        return result
    else:
        return result

    # Parse "NC 27017" from the last meaningful part
    state_zip_match = re.match(r"^([A-Z]{2})\s+(\d{5}(?:-\d{4})?)$", state_zip)
    if state_zip_match:
        result["state"] = state_zip_match.group(1)
        result["zip_code"] = state_zip_match.group(2)
    else:
        # Maybe just a state like "NC" or "North Carolina"
        result["state"] = state_zip

    return result
