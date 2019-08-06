# -*- coding: utf-8 -*-
# Generated by Django 1.11.22 on 2019-08-06 05:51
from __future__ import unicode_literals

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('resources', '0071_auto_20190801_1703'),
    ]

    operations = [
        migrations.AddField(
            model_name='partner',
            name='requested_access_duration',
            field=models.BooleanField(default=False, help_text='Mark as true if the authorization method of this partner is proxy and requires the duration of the access (expiry) be specified.'),
        ),
    ]
