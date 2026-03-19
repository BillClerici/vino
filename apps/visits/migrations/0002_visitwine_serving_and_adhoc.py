import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('visits', '0001_initial'),
        ('wineries', '0003_winery_image_url'),
    ]

    operations = [
        # Allow wine FK to be nullable (for ad-hoc entries)
        migrations.AlterField(
            model_name='visitwine',
            name='wine',
            field=models.ForeignKey(
                blank=True, null=True,
                on_delete=django.db.models.deletion.CASCADE,
                related_name='visit_records',
                to='wineries.wine',
            ),
        ),
        # Remove unique_together (wine can be null now)
        migrations.AlterUniqueTogether(
            name='visitwine',
            unique_together=set(),
        ),
        # Add new fields
        migrations.AddField(
            model_name='visitwine',
            name='wine_name',
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name='visitwine',
            name='wine_type',
            field=models.CharField(blank=True, max_length=100),
        ),
        migrations.AddField(
            model_name='visitwine',
            name='serving_type',
            field=models.CharField(
                choices=[('tasting', 'Tasting'), ('glass', 'Glass'), ('flight', 'Flight'), ('bottle', 'Bottle'), ('split', 'Split')],
                default='tasting', max_length=20,
            ),
        ),
    ]
