#!/bin/bash

#admin list
#last |cut -d' ' -f1 |grep -vwP 'root|reboot|wtmp' |grep . |sort |uniq -c |sort -nr |awk '{print $2}'
export usersList=''

cat ${KUBECONFIG} >~/.kubeconfig.bck
echo "${usersList}" |while read userLogin ;do
  if [ -f /etc/debian_version ]; then
    # Debian-based distribution
    usermod -aG sudo ${userLogin}
  elif [ -f /etc/redhat-release ]; then
    # RedHat-based distribution
    usermod -aG wheel ${userLogin}
  fi
  userHome=$(cat /etc/passwd |grep ^${userLogin}: |cut -d: -f6 )
  kubectl config set-context --current --namespace=home-${userLogin}
  kubectl config view --raw >${userHome}/.kube/config
  oc adm policy add-scc-to-user privileged -z default -n home-${userLogin} 2>/dev/null #add root for OPENSHIFT
done
cat ~/.kubeconfig.bck >${KUBECONFIG}
