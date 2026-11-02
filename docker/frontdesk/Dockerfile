FROM debian:12-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends -qq \
        python3 python3-venv python3-pip \
        openssh-server cron supervisor \
        libxml2-dev libxslt1-dev \
        curl netcat-traditional \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/sshd /var/log/supervisor /opt/shared

RUN python3 -m venv /opt/venv
COPY docker/frontdesk/requirements.txt /opt/app/requirements.txt
RUN /opt/venv/bin/pip install -q --no-cache-dir --retries 10 --timeout 120 \
        -r /opt/app/requirements.txt

COPY docker/generate_flags.py /opt/shared/generate_flags.py
COPY docker/flagcrypto.py /opt/shared/flagcrypto.py
COPY docker/frontdesk/app.py /opt/app/app.py
COPY docker/frontdesk/entrypoint.sh /opt/entrypoint.sh
COPY docker/frontdesk/supervisord.conf /etc/supervisor/conf.d/ctf.conf

RUN chmod +x /opt/entrypoint.sh
RUN useradd -m -s /bin/bash clerk

EXPOSE 22 5000

ENTRYPOINT ["/opt/entrypoint.sh"]
