# A CentOS Stream 9 server: sshd, sudo for the ops user, and the revenue API.
FROM quay.io/centos/centos:stream9
RUN dnf -y install --setopt=install_weak_deps=False openssh-server sudo python3 logrotate tar procps-ng iproute \
 && dnf clean all
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
