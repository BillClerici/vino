from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('trips', '0004_tripmember_invitation_fields'),
    ]

    operations = [
        migrations.AddField(
            model_name='tripmember',
            name='notes',
            field=models.TextField(blank=True),
        ),
    ]
