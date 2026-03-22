from rest_framework.renderers import JSONRenderer


class VinoJSONRenderer(JSONRenderer):
    """Wraps all API responses in the standard Vino envelope."""

    def render(self, data, accepted_media_type=None, renderer_context=None):
        response = renderer_context.get("response") if renderer_context else None
        status_code = response.status_code if response else 200

        if status_code >= 400:
            envelope = {
                "success": False,
                "data": None,
                "meta": {},
                "errors": data if isinstance(data, list) else [data] if data else [],
            }
        else:
            meta = {}
            payload = data

            # Handle paginated responses (DRF pagination wraps in results/count)
            if isinstance(data, dict) and "results" in data:
                payload = data["results"]
                meta = {
                    "page": data.get("page", 1),
                    "page_size": data.get("page_size", 25),
                    "total": data.get("count", 0),
                }

            envelope = {
                "success": True,
                "data": payload,
                "meta": meta,
                "errors": [],
            }

        return super().render(envelope, accepted_media_type, renderer_context)
