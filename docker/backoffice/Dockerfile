FROM debian:12-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends -qq \
        python3 python3-venv python3-pip supervisor libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/supervisor /opt/shared

RUN python3 -m venv /opt/venv
COPY docker/backoffice/requirements.txt /opt/app/requirements.txt
RUN /opt/venv/bin/pip install -q --no-cache-dir --retries 10 --timeout 120 \
        -r /opt/app/requirements.txt

COPY docker/generate_flags.py /opt/shared/generate_flags.py
COPY docker/backoffice/app.py /opt/app/app.py
COPY docker/backoffice/entrypoint.sh /opt/entrypoint.sh
COPY docker/backoffice/supervisord.conf /etc/supervisor/conf.d/ctf.conf

RUN chmod +x /opt/entrypoint.sh

# The app runs as this unprivileged account (not root) -- the pickle RCE
# in app.py therefore does NOT hand you root directly; you still need
# the SUID privesc below. "ops" is a honeypot: a real account that
# exists and shows up in /etc/passwd, with no valid path to it at all.
RUN useradd -m -s /usr/sbin/nologin svc
RUN useradd -m -s /bin/bash ops

# Privesc (Stage 9): SUID bit on `find` (GTFOBins' `-exec` technique --
# verified reliable: find's -exec is a direct execve with no built-in
# privilege-dropping, unlike some awk/system() implementations, and
# unlike modern perl, which no longer supports setuid scripts at all).
RUN REAL_FIND=$(readlink -f /usr/bin/find) && chmod u+s "$REAL_FIND" && ls -la "$REAL_FIND"

EXPOSE 6000
# Never published in docker-compose.yml -- internal-only on purpose.

ENTRYPOINT ["/opt/entrypoint.sh"]
