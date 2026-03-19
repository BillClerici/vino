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
            name='ControlPointGroup',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('is_active', models.BooleanField(default=True)),
                ('name', models.CharField(max_length=100, unique=True)),
                ('description', models.TextField(blank=True)),
                ('sort_order', models.PositiveIntegerField(default=0)),
            ],
            options={
                'ordering': ['sort_order', 'name'],
                'db_table': 'rbac_control_point_group',
            },
        ),
        migrations.CreateModel(
            name='ControlPoint',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('is_active', models.BooleanField(default=True)),
                ('code', models.CharField(db_index=True, max_length=100, unique=True)),
                ('label', models.CharField(max_length=255)),
                ('description', models.TextField(blank=True)),
                ('group', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='control_points', to='rbac.controlpointgroup')),
            ],
            options={
                'ordering': ['group__sort_order', 'group__name', 'label'],
                'db_table': 'rbac_control_point',
            },
        ),
        migrations.CreateModel(
            name='Role',
            fields=[
                ('id', models.UUIDField(default=uuid.uuid4, editable=False, primary_key=True, serialize=False)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('is_active', models.BooleanField(default=True)),
                ('name', models.CharField(max_length=100, unique=True)),
                ('description', models.TextField(blank=True)),
                ('control_points', models.ManyToManyField(blank=True, related_name='roles', to='rbac.controlpoint')),
            ],
            options={
                'ordering': ['name'],
                'db_table': 'rbac_role',
            },
        ),
    ]
