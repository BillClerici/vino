import factory
from django.utils import timezone

from apps.lookup.models import LookupValue
from apps.palate.models import PalateProfile
from apps.trips.models import Trip, TripMember, TripStop
from apps.users.models import User
from apps.visits.models import VisitLog, VisitWine
from apps.wineries.models import FavoritePlace, MenuItem, Place


class UserFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = User

    email = factory.Sequence(lambda n: f"user{n}@example.com")
    first_name = factory.Faker("first_name")
    last_name = factory.Faker("last_name")
    is_active = True

    @classmethod
    def _create(cls, model_class, *args, **kwargs):
        obj = super()._create(model_class, *args, **kwargs)
        obj.set_unusable_password()
        obj.save(update_fields=["password"])
        return obj


class LookupValueFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = LookupValue

    code = factory.Sequence(lambda n: f"CODE_{n}")
    label = factory.Sequence(lambda n: f"Label {n}")
    sort_order = 0


class PlaceFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Place

    name = factory.Sequence(lambda n: f"Test Winery {n}")
    place_type = "winery"
    city = "Napa"
    state = "CA"
    latitude = factory.Faker("latitude")
    longitude = factory.Faker("longitude")


class MenuItemFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = MenuItem

    place = factory.SubFactory(PlaceFactory)
    name = factory.Sequence(lambda n: f"Wine {n}")
    varietal = "Cabernet Sauvignon"
    vintage = 2022


class FavoritePlaceFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = FavoritePlace

    user = factory.SubFactory(UserFactory)
    place = factory.SubFactory(PlaceFactory)


class VisitLogFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = VisitLog

    user = factory.SubFactory(UserFactory)
    place = factory.SubFactory(PlaceFactory)
    visited_at = factory.LazyFunction(timezone.now)
    rating_overall = 4


class VisitWineFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = VisitWine

    visit = factory.SubFactory(VisitLogFactory)
    wine_name = factory.Sequence(lambda n: f"Ad Hoc Wine {n}")
    wine_type = "Red"
    serving_type = "tasting"
    rating = 4


class TripFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = Trip

    name = factory.Sequence(lambda n: f"Test Trip {n}")
    created_by = factory.SubFactory(UserFactory)
    status = "draft"
    scheduled_date = factory.LazyFunction(lambda: timezone.now().date())


class TripMemberFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = TripMember

    trip = factory.SubFactory(TripFactory)
    user = factory.SubFactory(UserFactory)
    role = "organizer"
    rsvp_status = "accepted"


class TripStopFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = TripStop

    trip = factory.SubFactory(TripFactory)
    place = factory.SubFactory(PlaceFactory)
    order = factory.Sequence(lambda n: n)


class PalateProfileFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = PalateProfile

    user = factory.SubFactory(UserFactory)
    preferences = {"sweetness": 3, "acidity": 4, "body": 3}
