from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('wineries', '0004_winery_wine_menu_last_scraped'),
    ]

    operations = [
        migrations.AddField(
            model_name='wine',
            name='image_url',
            field=models.URLField(blank=True, max_length=1000),
        ),
    ]
