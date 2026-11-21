# An Ubuntu 24.04 server: sshd, sudo for the ops user, and the revenue API.
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-server sudo python3 logrotate tar procps iproute2 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd
COPY entrypoint.sh /usr/local/sbin/entrypoint.sh
COPY revenue_api.py /opt/revenue/revenue_api.py
RUN useradd -m -s /bin/bash ops \
 && echo 'ops ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/ops && chmod 440 /etc/sudoers.d/ops \
 && useradd -r -s /sbin/nologin revenue \
 && ssh-keygen -A \
 && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/; s/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && chmod 755 /usr/local/sbin/entrypoint.sh
EXPOSE 22 8080
CMD ["/usr/local/sbin/entrypoint.sh"]
