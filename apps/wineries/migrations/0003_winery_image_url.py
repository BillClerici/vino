from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('wineries', '0002_favoritewinery'),
    ]

    operations = [
        migrations.AddField(
            model_name='winery',
            name='image_url',
            field=models.URLField(blank=True, max_length=1000),
        ),
    ]
