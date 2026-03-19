from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('wineries', '0003_winery_image_url'),
    ]

    operations = [
        migrations.AddField(
            model_name='winery',
            name='wine_menu_last_scraped',
            field=models.DateTimeField(blank=True, null=True),
        ),
    ]
