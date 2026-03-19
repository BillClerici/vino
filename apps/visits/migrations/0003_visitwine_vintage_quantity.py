from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('visits', '0002_visitwine_serving_and_adhoc'),
    ]

    operations = [
        migrations.AddField(
            model_name='visitwine',
            name='wine_vintage',
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='visitwine',
            name='quantity',
            field=models.PositiveSmallIntegerField(default=1),
        ),
    ]
