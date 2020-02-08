#!/usr/bin/bash

CMD="$1"
SVC="$2"

SVCS=/usr/bin/svcs
SVCADM=/usr/sbin/svcadm

if [[ ! "${CMD}" =~ ^refresh$|^restart$ ]] || [[ -z "${SVC}" ]]; then
	echo "Usage: $0 <refresh|restart> <smf_service>"
	exit 1
fi

state="$(${SVCS} -Ho state "${SVC}")"
rc="$?"

[[ $? -ne 0 ]] && return "${rc}"

[[ "${state}" == "maintenance" ]] && CMD="clear"
[[ "${state}" == "disabled" ]] && CMD="enable"

${SVCADM} "${CMD}" "${SVC}"
