import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('trips', '0003_trip_budget_notes_trip_description_trip_end_date_and_more'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        # Allow user to be nullable (for external invites)
        migrations.AlterField(
            model_name='tripmember',
            name='user',
            field=models.ForeignKey(
                blank=True, null=True,
                on_delete=django.db.models.deletion.CASCADE,
                related_name='trip_memberships',
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        # Remove unique_together (replaced by model-level validation)
        migrations.AlterUniqueTogether(
            name='tripmember',
            unique_together=set(),
        ),
        # Add invitation fields
        migrations.AddField(
            model_name='tripmember',
            name='invite_email',
            field=models.EmailField(blank=True, max_length=254),
        ),
        migrations.AddField(
            model_name='tripmember',
            name='invite_first_name',
            field=models.CharField(blank=True, max_length=150),
        ),
        migrations.AddField(
            model_name='tripmember',
            name='invite_last_name',
            field=models.CharField(blank=True, max_length=150),
        ),
        migrations.AddField(
            model_name='tripmember',
            name='invite_message',
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name='tripmember',
            name='invited_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='tripmember',
            name='responded_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
