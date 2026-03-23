from rest_framework import serializers

from apps.trips.models import Trip, TripMember, TripStop

from ..places.serializers import PlaceListSerializer
from ..users.serializers import UserSummarySerializer


class TripStopSerializer(serializers.ModelSerializer):
    place = PlaceListSerializer(read_only=True)

    class Meta:
        model = TripStop
        fields = [
            "id", "place", "order", "arrival_time", "duration_minutes",
            "travel_minutes", "travel_miles", "description", "notes",
            "meeting_details", "travel_details", "created_at",
        ]
        read_only_fields = ["id", "created_at"]


class TripStopWriteSerializer(serializers.ModelSerializer):
    class Meta:
        model = TripStop
        fields = [
            "place", "order", "arrival_time", "duration_minutes",
            "travel_minutes", "travel_miles", "description", "notes",
            "meeting_details", "travel_details",
        ]


class TripMemberSerializer(serializers.ModelSerializer):
    user = UserSummarySerializer(read_only=True)
    display_name = serializers.CharField(read_only=True)
    display_initial = serializers.CharField(read_only=True)

    class Meta:
        model = TripMember
        fields = [
            "id", "user", "role", "rsvp_status", "notes",
            "invite_email", "invite_first_name", "invite_last_name",
            "invite_message", "invited_at", "responded_at",
            "display_name", "display_initial", "created_at",
        ]
        read_only_fields = ["id", "display_name", "display_initial", "created_at"]


class TripListSerializer(serializers.ModelSerializer):
    member_count = serializers.IntegerField(read_only=True, default=0)
    stop_count = serializers.IntegerField(read_only=True, default=0)
    created_by_name = serializers.SerializerMethodField()

    class Meta:
        model = Trip
        fields = [
            "id", "name", "status", "scheduled_date", "end_date",
            "member_count", "stop_count", "created_by_name", "created_at",
        ]
        read_only_fields = ["id", "created_at"]

    def get_created_by_name(self, obj):
        return obj.created_by.full_name


class TripDetailSerializer(serializers.ModelSerializer):
    trip_stops = TripStopSerializer(many=True, read_only=True, source="active_stops")
    trip_members = TripMemberSerializer(many=True, read_only=True, source="active_members")
    created_by = UserSummarySerializer(read_only=True)

    class Meta:
        model = Trip
        fields = [
            "id", "name", "description", "status",
            "scheduled_date", "end_date",
            "meeting_location", "meeting_time", "meeting_notes",
            "transportation", "budget_notes", "notes",
            "created_by", "trip_stops", "trip_members",
            "created_at", "updated_at",
        ]
        read_only_fields = ["id", "created_by", "created_at", "updated_at"]


class TripWriteSerializer(serializers.ModelSerializer):
    copy_from = serializers.UUIDField(required=False, write_only=True)

    class Meta:
        model = Trip
        fields = [
            "name", "description", "status", "scheduled_date", "end_date",
            "meeting_location", "meeting_time", "meeting_notes",
            "transportation", "budget_notes", "notes", "copy_from",
        ]

    def create(self, validated_data):
        copy_from_id = validated_data.pop("copy_from", None)
        user = self.context["request"].user
        validated_data["created_by"] = user
        trip = Trip.objects.create(**validated_data)

        # Make creator the organizer
        TripMember.objects.create(
            trip=trip, user=user,
            role=TripMember.Role.ORGANIZER,
            rsvp_status="accepted",
        )

        # Copy stops from another trip if requested
        if copy_from_id:
            try:
                source = Trip.objects.get(pk=copy_from_id, members=user, is_active=True)
                for stop in source.trip_stops.filter(is_active=True).order_by("order"):
                    TripStop.objects.create(
                        trip=trip,
                        place=stop.place,
                        order=stop.order,
                        duration_minutes=stop.duration_minutes,
                        description=stop.description,
                        notes=stop.notes,
                    )
            except Trip.DoesNotExist:
                pass

        return trip


class TripStopReorderSerializer(serializers.Serializer):
    stops = serializers.ListField(
        child=serializers.DictField(child=serializers.CharField()),
        help_text="List of {id, order} pairs",
    )


class TripInviteSerializer(serializers.Serializer):
    email = serializers.EmailField()
    first_name = serializers.CharField(required=False, default="")
    last_name = serializers.CharField(required=False, default="")
    message = serializers.CharField(required=False, default="")


class TripMemberUpdateSerializer(serializers.Serializer):
    role = serializers.ChoiceField(choices=TripMember.Role.choices, required=False)
    rsvp_status = serializers.ChoiceField(
        choices=TripMember.RSVP_CHOICES, required=False
    )
