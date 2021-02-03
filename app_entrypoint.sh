#!/bin/sh
set -eu
[[ -d ${HOME}/config ]] || mkdir -p ${HOME}/config
[[ -f ${HOME}/config/config.xml ]] || /bin/syncthing -generate="${HOME}/config"
chown -R ${PUID} ${HOME} && chgrp -R ${PGID} ${HOME}
sed -i "s/<apikey>.*<\/apikey>/<apikey>$(cat /configs/apikey)<\/apikey>/" ${HOME}/config/config.xml
if [ "$(id -u)" = '0' ]; then
  chown "${PUID}:${PGID}" "${HOME}" \
    && exec su-exec "${PUID}:${PGID}" \
       env HOME="$HOME" "$@"
else
  exec "$@"
fi