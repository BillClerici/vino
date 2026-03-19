import factory
from apps.users.models import User
from apps.lookup.models import LookupValue


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
