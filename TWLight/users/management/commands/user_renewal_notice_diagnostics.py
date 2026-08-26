from datetime import datetime, timedelta

from django.conf import settings
from django.contrib.auth.models import User
from django.core.management.base import BaseCommand
from django.db.models import Count, Prefetch, Q
from django.utils import timezone

from djmail.models import Message

from TWLight.applications.models import Application
from TWLight.resources.models import Partner
from TWLight.users.models import Authorization, Editor


class Command(BaseCommand):
    help = (
        "READ-ONLY diagnostics for the user_renewal_notice command (T407250). "
        "Reports why expiry-notice emails may not be going out. "
        "Sends no email and writes no data."
    )

    # English subject from user_renewal_notice-subject.html. Non-English
    # messages are stored translated, so this match is best-effort; the
    # Authorization-side counts and the global djmail stats do not depend
    # on it.
    RENEWAL_SUBJECT_FRAGMENT = "access may soon expire"

    def add_arguments(self, parser):
        parser.add_argument(
            "--days",
            type=int,
            default=100,
            help="Window (days) for the recent djmail message stats. "
            "Default matches the djmail_delete_old_messages retention (100).",
        )

    def handle(self, *args, **options):
        days = options["days"]
        today = datetime.today()

        w = self.stdout.write

        w("== user_renewal_notice diagnostics (READ-ONLY) ==")
        w("Today: {}".format(today.date()))

        # --- 1. Config sanity ------------------------------------------------
        real_backend = getattr(
            settings,
            "DJMAIL_REAL_BACKEND",
            "django.core.mail.backends.console.EmailBackend",
        )
        w("")
        w("[Config]")
        w("  EMAIL_BACKEND       : {}".format(getattr(settings, "EMAIL_BACKEND", "?")))
        w("  DJMAIL_REAL_BACKEND : {}".format(real_backend))

        # --- 2. What the command WOULD email today --------------------------
        # This replicates user_renewal_notice.Command.handle() exactly, but
        # only counts. Keep in sync with that command.
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
                date_expires__lt=today + timedelta(weeks=2),
                date_expires__gte=today,
                reminder_email_sent=False,
                partners__isnull=False,
            )
            .exclude(user__userprofile__send_renewal_notices=False)
            # The partners join makes one row for each partner. Use distinct()
            # so that an authorization with many partners (a Bundle
            # authorization that has an expiry date) gets only one email.
            .distinct()
        )

        # Collect the primary keys, not the querysets. See the note in
        # user_renewal_notice.py: a list of querysets makes SQL that removes
        # every authorization (T407250).
        no_email_list = set()
        for application in applications_for_renewal:
            no_email_list.update(
                expiring_authorizations.filter(
                    partners=application["partner__pk"],
                    user=application["editor__user__pk"],
                ).values_list("pk", flat=True)
            )

        would_email = expiring_authorizations.exclude(pk__in=no_email_list).count()

        # Show the result of the old, defective exclusion too. A big difference
        # between the two numbers shows that the defect is present.
        legacy_no_email_list = [
            expiring_authorizations.values_list("pk").filter(
                partners=application["partner__pk"],
                user=application["editor__user__pk"],
            )
            for application in applications_for_renewal
        ]
        legacy_would_email = expiring_authorizations.exclude(
            pk__in=legacy_no_email_list
        ).count()

        w("")
        w(
            "[Query] authorizations the command WOULD email today: {}".format(
                would_email
            )
        )
        w(
            "  (in-window & un-reminded, before renewal-filed exclusion: {})".format(
                expiring_authorizations.count()
            )
        )
        w(
            "  excluded because a renewal was already filed: {}".format(
                len(no_email_list)
            )
        )
        w(
            "  same count with the old (defective) exclusion: {}{}".format(
                legacy_would_email,
                "   <-- DEFECT PRESENT" if legacy_would_email != would_email else "",
            )
        )

        # --- 3. Sticky-flag suppression (Authorization-side, locale-neutral) -
        marked = Authorization.objects.filter(reminder_email_sent=True)
        marked_total = marked.count()
        marked_not_expired = marked.filter(date_expires__gte=today).count()
        marked_in_window = marked.filter(
            date_expires__gte=today,
            date_expires__lt=today + timedelta(weeks=2),
        ).count()

        w("")
        w("[Suppression] reminder_email_sent=True ...")
        w("  total                                   : {}".format(marked_total))
        w(
            "  AND not yet expired (date_expires>=today): {}   <-- marked but access still live".format(
                marked_not_expired
            )
        )
        w(
            "  AND still inside the 2-week notice window: {}   <-- would email if flag were reset".format(
                marked_in_window
            )
        )

        # --- 4. djmail send-path health -------------------------------------
        status_names = {
            Message.STATUS_DRAFT: "DRAFT",
            Message.STATUS_PENDING: "PENDING",
            Message.STATUS_SENT: "SENT",
            Message.STATUS_FAILED: "FAILED",
            Message.STATUS_DISCARDED: "DISCARDED",
        }

        def status_breakdown(qs):
            counts = {
                row["status"]: row["c"]
                for row in qs.values("status").annotate(c=Count("pk"))
            }
            return {status_names.get(k, k): v for k, v in sorted(counts.items())}

        # created_at is a DateTimeField; use an aware value under USE_TZ.
        since = timezone.now() - timedelta(days=days)
        recent = Message.objects.filter(created_at__gte=since)

        w("")
        w("[djmail] ALL messages, last {} days".format(days))
        w("  total                 : {}".format(recent.count()))
        w("  by status             : {}".format(status_breakdown(recent)))
        w(
            "  with recorded exception: {}".format(
                recent.exclude(exception="").exclude(exception__isnull=True).count()
            )
        )

        latest_exc = (
            Message.objects.exclude(exception="")
            .exclude(exception__isnull=True)
            .order_by("-created_at")
            .first()
        )
        if latest_exc:
            exc_text = (latest_exc.exception or "").strip().replace("\n", " ")
            w(
                "  latest exception ({}): {}".format(
                    latest_exc.created_at.date(), exc_text[:300]
                )
            )
        else:
            w("  latest exception      : (none recorded)")

        # --- 5. Renewal-subject messages (best-effort, English only) --------
        renewal_msgs = Message.objects.filter(
            subject__icontains=self.RENEWAL_SUBJECT_FRAGMENT
        )
        w("")
        w(
            "[djmail] renewal-notice messages (subject ~ '{}', English only)".format(
                self.RENEWAL_SUBJECT_FRAGMENT
            )
        )
        w("  total                 : {}".format(renewal_msgs.count()))
        w("  by status             : {}".format(status_breakdown(renewal_msgs)))
        if renewal_msgs.exists():
            oldest = renewal_msgs.order_by("created_at").first().created_at.date()
            newest = renewal_msgs.order_by("-created_at").first().created_at.date()
            w("  date range            : {} .. {}".format(oldest, newest))

        # --- 6. Interpretation ----------------------------------------------
        w("")
        w("[How to read this]")
        w(
            "  * Many 'marked but not yet expired' + few SENT renewal messages"
            " => sticky-flag suppression (auths marked reminded without delivery)."
        )
        w(
            "  * djmail DRAFT/FAILED with exceptions => the real backend is failing;"
            " the async command exits 0 and marks reminder_email_sent anyway."
        )
        w(
            "  * would-email=0 AND no in-window auths => genuinely nobody to notify"
            " (not a bug)."
        )
        w(
            "  * 'DEFECT PRESENT' above => the old exclusion removed everybody."
            " Deploy the T407250 fix in user_renewal_notice.py."
        )
        w("")
        w("Done. No data was modified.")
