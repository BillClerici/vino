from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('wineries', '0005_wine_image_url'),
    ]

    operations = [
        migrations.AddField(
            model_name='wine',
            name='price',
            field=models.DecimalField(blank=True, decimal_places=2, max_digits=8, null=True),
        ),
    ]
