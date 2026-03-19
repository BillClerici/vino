from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('visits', '0003_visitwine_vintage_quantity'),
    ]

    operations = [
        migrations.AddField(
            model_name='visitwine',
            name='is_favorite',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='visitwine',
            name='purchased',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='visitwine',
            name='purchased_quantity',
            field=models.PositiveSmallIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='visitwine',
            name='purchased_price',
            field=models.DecimalField(blank=True, decimal_places=2, max_digits=8, null=True),
        ),
        migrations.AddField(
            model_name='visitwine',
            name='purchased_notes',
            field=models.TextField(blank=True),
        ),
    ]
