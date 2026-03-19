from django.db import migrations, models
import uuid


class Migration(migrations.Migration):

    initial = True

    dependencies = []

    operations = [
        # BaseModel is abstract — no table created.
        # This migration exists so Django recognises the core app.
    ]
