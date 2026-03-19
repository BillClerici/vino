from django.db import migrations, models
import django.db.models.deletion
import uuid


class Migration(migrations.Migration):

    initial = True

    dependencies = [
        ('core', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='LookupValue',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('is_active', models.BooleanField(default=True)),
                ('code', models.CharField(db_index=True, max_length=100)),
                ('label', models.CharField(max_length=255)),
                ('description', models.TextField(blank=True)),
                ('sort_order', models.PositiveIntegerField(default=0)),
                ('metadata', models.JSONField(blank=True, default=dict)),
                ('parent', models.ForeignKey(
                    blank=True,
                    help_text='Null = this record IS a lookup type. Non-null = this is a value within that type.',
                    null=True,
                    on_delete=django.db.models.deletion.PROTECT,
                    related_name='children',
                    to='lookup.lookupvalue',
                )),
            ],
            options={
                'ordering': ['sort_order', 'label'],
                'unique_together': {('parent', 'code')},
            },
        ),
    ]
