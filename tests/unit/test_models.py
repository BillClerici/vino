import pytest

from apps.lookup.models import LookupValue

pytestmark = pytest.mark.django_db


class TestBaseModelConventions:
    def test_user_has_uuid_pk(self, user_factory):
        user = user_factory()
        assert user.pk is not None
        assert len(str(user.pk)) == 36  # UUID format

    def test_lookup_has_uuid_pk(self, lookup_factory):
        lookup = lookup_factory()
        assert lookup.pk is not None
        assert len(str(lookup.pk)) == 36

    def test_soft_delete(self, lookup_factory):
        """Test soft delete using LookupValue which uses ActiveManager."""
        item = lookup_factory()
        item.is_active = False
        item.save()
        assert LookupValue.objects.filter(pk=item.pk).count() == 0
        assert LookupValue.all_objects.filter(pk=item.pk).count() == 1

    def test_timestamps_set(self, user_factory):
        user = user_factory()
        assert user.created_at is not None
        assert user.updated_at is not None


class TestLookupValue:
    def test_parent_child_hierarchy(self, lookup_factory):
        parent = lookup_factory(parent=None, code="STATUS")
        child = lookup_factory(parent=parent, code="ACTIVE", label="Active")
        assert child.parent == parent
        assert parent.children.count() == 1

    def test_unique_together(self, lookup_factory):
        parent = lookup_factory(parent=None, code="TYPE")
        lookup_factory(parent=parent, code="A")
        with pytest.raises(Exception):
            lookup_factory(parent=parent, code="A")
