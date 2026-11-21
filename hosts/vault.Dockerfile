# The backup host: sshd and a /backups volume the ops user writes to.
FROM ubuntu:24.04
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openssh-server tar \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd /backups \
 && useradd -m -s /bin/bash ops && chown ops:ops /backups \
 && ssh-keygen -A \
 && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/; s/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
CMD ["sh", "-c", "install -d -m 700 -o ops -g ops /home/ops/.ssh && install -m 600 -o ops -g ops /run/keys/fleet.pub /home/ops/.ssh/authorized_keys && exec /usr/sbin/sshd -D -e"]
