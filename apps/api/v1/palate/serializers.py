from rest_framework import serializers

from apps.palate.models import PalateProfile


class PalateProfileSerializer(serializers.ModelSerializer):
    class Meta:
        model = PalateProfile
        fields = [
            "id", "preferences", "pinecone_vector_id",
            "last_analyzed_at", "analysis_version",
            "created_at", "updated_at",
        ]
        read_only_fields = fields
