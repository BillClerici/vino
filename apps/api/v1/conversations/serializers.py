from rest_framework import serializers

from apps.trips.models import SippyConversation


class SippyConversationListSerializer(serializers.ModelSerializer):
    class Meta:
        model = SippyConversation
        fields = [
            "id", "chat_type", "title", "phase", "trip",
            "session_id", "created_at", "updated_at",
        ]


class SippyConversationDetailSerializer(serializers.ModelSerializer):
    class Meta:
        model = SippyConversation
        fields = [
            "id", "chat_type", "title", "session_id", "trip",
            "messages", "phase", "proposed_trip",
            "created_at", "updated_at",
        ]


class SippyConversationWriteSerializer(serializers.ModelSerializer):
    class Meta:
        model = SippyConversation
        fields = [
            "chat_type", "title", "session_id", "trip",
            "messages", "phase", "proposed_trip",
        ]
