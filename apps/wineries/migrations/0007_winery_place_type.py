from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('wineries', '0006_wine_price'),
    ]

    operations = [
        migrations.AddField(
            model_name='winery',
            name='place_type',
            field=models.CharField(
                choices=[('winery', 'Winery'), ('brewery', 'Brewery'), ('restaurant', 'Restaurant'), ('other', 'Other')],
                default='winery', max_length=20,
            ),
        ),
    ]
