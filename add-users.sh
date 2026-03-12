#!/bin/bash

# User Variables
usersList="$1"
usersSsh="$2"
runRemoteBootstrap="${RUN_REMOTE_K8S_USERS_BOOTSTRAP:-1}"

# Generate a fallback random password if mkpasswd is unavailable.
if command -v mkpasswd >/dev/null 2>&1; then
  passWdDefault="$(mkpasswd | tr -c '[:alnum:]' '+')"
else
  passWdDefault="$(openssl rand -base64 18 | tr -c '[:alnum:]' '+')"
fi

# Script Start
(
  # User Password Setup
  echo "Enter password (default:${passWdDefault}):"
  read passWd
  [ -z "${passWd}" ] && passWd="${passWdDefault}"

  # Exit if no users specified
  [ -z "${usersList}" ] && exit 0

  # Install rsync
  apt install rsync -y 2>/dev/null || yum install rsync -y

  # User Account Creation
  echo "${usersList}" | while read -r userLogin; do
    [ -z "${userLogin}" ] && continue
    grep -w "${userLogin}" /etc/passwd >/dev/null || (
      useradd "${userLogin}" --shell /bin/bash
      echo "${passWd}" | passwd "${userLogin}" --stdin 2>/dev/null || (
      echo "${userLogin}:${passWd}" | chpasswd )
      passwd --expire "${userLogin}"
      rsync -aAX /etc/skel/ "/home/${userLogin}/"
      mkdir -p "/home/${userLogin}/.ssh"
      echo "${usersSsh}" >>/home/${userLogin}/.ssh/authorized_keys
      chmod 600 /home/${userLogin}/.ssh/authorized_keys
      chown -R "${userLogin}": "/home/${userLogin}"
    )
  done

  # Kubernetes Users Setup
  if [ "${runRemoteBootstrap}" = "1" ]; then
    mkdir -p ~/old &&\
    cd ~/old &&\
    tmpScript="$(mktemp)" &&\
    curl -fsSL https://infocepo.com/wiki/index.php/Special:Export/K8s-users 2>/dev/null | tac | sed -r '0,/'"#"'24cc42#/d' | tac | sed -r '0,/'"#"'24cc42#/d' | sed 's/'"&"'amp;/\&/g;s/'"&"'gt;/>/g;s/'"&"'lt;/</g' >"${tmpScript}" &&\
    bash "${tmpScript}" &&\
    rm -f "${tmpScript}" &&\
    cd - >/dev/null
  fi
)
