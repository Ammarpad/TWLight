from datetime import datetime, timedelta
import logging

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand
from django.db.models import Prefetch, Q
from django.urls import reverse

from TWLight.applications.models import Application
from TWLight.resources.models import Partner
from TWLight.users.signals import Notice
from TWLight.users.models import Authorization, get_company_name, Editor

logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "Sends advance notice to users with expiring authorizations, prompting them to apply for renewal."

    def handle(self, *args, **options):
        # Get all authorization objects with an expiry date in the next
        # two weeks, for which we haven't yet sent a reminder email, and
        # exclude users who disabled these emails and who have already filed
        # for a renewal.
        editor_qs = Editor.objects.select_related("user")
        applications_for_renewal = (
            Application.objects.prefetch_related(Prefetch("editor", queryset=editor_qs))
            .values("editor__user__pk", "partner__pk")
            .filter(
                ~Q(partner__authorization_method=Partner.BUNDLE),
                status__in=[Application.PENDING, Application.QUESTION],
                parent__isnull=False,
                editor__isnull=False,
            )
            .order_by("-date_created")
        )

        user_qs = User.objects.select_related("userprofile")
        expiring_authorizations = (
            Authorization.objects.prefetch_related(Prefetch("user", queryset=user_qs))
            .filter(
                date_expires__lt=datetime.today() + timedelta(weeks=2),
                date_expires__gte=datetime.today(),
                reminder_email_sent=False,
                partners__isnull=False,
            )
            .exclude(user__userprofile__send_renewal_notices=False)
            # The partners join makes one row for each partner. Use distinct()
            # so that an authorization with many partners (a Bundle
            # authorization that has an expiry date) gets only one email.
            .distinct()
        )

        # Create a set of the primary keys of the authorizations that already
        # have a renewal application.
        #
        # Collect the primary keys. Do not collect the querysets. A list of
        # querysets becomes a list of scalar sub-queries in SQL. An empty
        # sub-query gives NULL, and "pk NOT IN (NULL, ...)" is never true. This
        # removed every authorization from the result and stopped all of the
        # emails (T407250).
        no_email_list = set()
        for application in applications_for_renewal:
            no_email_list.update(
                expiring_authorizations.filter(
                    partners=application["partner__pk"],
                    user=application["editor__user__pk"],
                ).values_list("pk", flat=True)
            )

        # Iterate through all expiring authorizations except the ones that have
        # a renewal
        for authorization_object in expiring_authorizations.exclude(
            pk__in=no_email_list
        ):
            try:
                responses = Notice.user_renewal_notice.send(
                    sender=self.__class__,
                    user_wp_username=authorization_object.user.editor.wp_username,
                    user_email=authorization_object.user.email,
                    user_lang=authorization_object.user.userprofile.lang,
                    partner_name=get_company_name(authorization_object),
                    partner_link=reverse("users:my_library"),
                )
            except Exception:
                # Do not stop the batch if one send fails. Do not mark the
                # authorization. The next run tries again.
                logger.exception(
                    "Failed to send renewal notice for authorization %s.",
                    authorization_object.pk,
                )
                continue

            # Record that we sent the email so that we only send one. Mark the
            # authorization only if the email was really sent. If we mark it
            # after a failed send, the user never gets a reminder (T407250).
            email_sent = any(response for receiver, response in responses)
            if email_sent:
                authorization_object.reminder_email_sent = True
                authorization_object.save()
            else:
                logger.warning(
                    "Renewal notice was not sent for authorization %s. "
                    "reminder_email_sent stays False for a retry.",
                    authorization_object.pk,
                )
