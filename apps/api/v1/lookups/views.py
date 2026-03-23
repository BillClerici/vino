from rest_framework.viewsets import ReadOnlyModelViewSet

from apps.lookup.models import LookupValue

from ..permissions import HasActiveSubscription
from .serializers import LookupValueSerializer


class LookupValueViewSet(ReadOnlyModelViewSet):
    permission_classes = [HasActiveSubscription]
    serializer_class = LookupValueSerializer
    ordering = ["sort_order", "label"]

    def get_queryset(self):
        qs = LookupValue.objects.filter(is_active=True)
        parent_code = self.request.query_params.get("parent_code")
        if parent_code:
            qs = qs.filter(parent__code=parent_code)
        return qs
