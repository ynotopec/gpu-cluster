#!/bin/bash

# User Variables
export usersList='pnom'
export passWdDefault='Aa-1'

# Script Start
(
  # User Password Setup
  echo "Enter password (default:${passWdDefault}):"
  read passWd
  [ -z "${passWd}" ] && export passWd=${passWdDefault}

  # Exit if no users specified
  [ -z "${usersList}" ] && break

  # Install rsync
  apt install rsync -y 2>/dev/null || yum install rsync -y

  # User Account Creation
  echo "${usersList}" | while read userLogin; do
    grep -w ${userLogin} /etc/passwd >/dev/null || (
      useradd "${userLogin}" --shell /bin/bash
      echo ${passWd} | passwd "${userLogin}" --stdin 2>/dev/null || (
      echo "${userLogin}:${passWd}" | chpasswd )
      passwd --expire "${userLogin}"
      rsync -aAX /etc/skel/ /home/${userLogin}/
      chown -R ${userLogin}: /home/${userLogin}
    )
  done

  # Kubernetes Users Setup
  mkdir -p ~/old &&\
  cd ~/old &&\
  curl https://infocepo.com/wiki/index.php/Special:Export/K8s-users 2>/dev/null | tac | sed -r '0,/'"#"'24cc42#/d' | tac | sed -r '0,/'"#"'24cc42#/d' | sed 's/'"&"'amp;/\&/g;s/'"&"'gt;/>/g;s/'"&"'lt;/</g' >$$ &&\
  bash $$ &&\
  cd - >/dev/null
)
