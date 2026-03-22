from collections import OrderedDict

from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response


class VinoPagination(PageNumberPagination):
    """Pagination that returns data in a format the VinoJSONRenderer can unpack."""

    page_size = 25
    page_size_query_param = "page_size"
    max_page_size = 100

    def get_paginated_response(self, data):
        return Response(OrderedDict([
            ("count", self.page.paginator.count),
            ("page", self.page.number),
            ("page_size", self.get_page_size(self.request) or self.page_size),
            ("results", data),
        ]))

    def get_paginated_response_schema(self, schema):
        return {
            "type": "object",
            "properties": {
                "count": {"type": "integer"},
                "page": {"type": "integer"},
                "page_size": {"type": "integer"},
                "results": schema,
            },
        }
