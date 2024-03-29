#!/bin/sh

function env2cert {
    file=$1
    var="$2"
    (echo "$var" | sed 's/"//g' | grep '^-----' > /dev/null) && 
    (echo "$var" | sed -e 's/"//g' -e 's/\r//g' | sed -e 's/- /-\n/' -e 's/ -/\n-/' | sed -e '2s/ /\n/g' > $file) &&
    echo -n $file || echo -n
}

[ "x$SSL_CERT" != "x" -a ! -f "$SSL_CERT" ] && SSL_CERT=$(env2cert /etc/ssl/httpd/default.pem "$SSL_CERT")
[ "x$SSL_KEY" != "x" -a ! -f "$SSL_KEY" ] && SSL_KEY=$(env2cert /etc/ssl/httpd/default.key "$SSL_KEY")

#//---------------------------------------------------------------------------
#// Improv security
#//---------------------------------------------------------------------------
# Improv Sec
if [ ! -e /etc/ssl/httpd/ssl_sess_ticket.key ] ; then
    openssl rand 48 > /etc/ssl/httpd/ssl_sess_ticket.key
fi
if [ ! -e /etc/ssl/httpd/dhparam.key ] ; then
    env2cert /etc/ssl/httpd/dhparam.key "$SSL_DHPARAM" > /dev/null
    test -f /etc/ssl/httpd/dhparam.key || openssl dhparam 2048 > /etc/ssl/httpd/dhparam.key 2> /dev/null
fi

# Generate localhost.pem and localhost.key
if [[ ! -e /etc/ssl/httpd/localhost.key \
    && ! -e /etc/ssl/httpd/localhost.pem ]]; then
    keyfile=$(mktemp /tmp/k_ssl_key.XXXXXX)
    certfile=$(mktemp /tmp/k_ssl_cert.XXXXXX)
    trap "rm -f ${keyfile} ${certfile}" SIGINT
    (echo --; echo SomeState; echo SomeCity; echo SomeOrganization; \
     echo SomeOrganizationalUnit; echo localhost.localdomain; \
     echo root@localhost.localdomain) | \
    openssl req -newkey rsa:2048 -keyout "${keyfile}" -nodes -x509 \
                -days 365 -out "${certfile}" 2> /dev/null
    mv "${keyfile}" /etc/ssl/httpd/localhost.key
    chmod 0600 /etc/ssl/httpd/localhost.key
    mv "${certfile}" /etc/ssl/httpd/localhost.pem
    chmod 0644 /etc/ssl/httpd/localhost.pem
fi

NO_SSL_REDIRECT=${NO_SSL_REDIRECT:-0}
NO_USE_NAXSI=${NO_USE_NAXSI:-1}
NO_USE_SSLST=${NO_USE_SSLST:-1}

#//---------------------------------------------------------------------------
#// generate httpd configuration file
#//---------------------------------------------------------------------------
cd /etc/httpd/conf.d \
&& env FQDN=${FQDN:-localhost.localdomain} \
    DOCUMENTROOT=${DOCUMENTROOT:-/var/www/html} \
    KUSANAGI_PROVISION=${KUSANAGI_PROVISION:-lamp} \
    SSL_CERT=${SSL_CERT:-/etc/ssl/httpd/default.pem} \
    SSL_KEY=${SSL_KEY:-/etc/ssl/httpd/default.key} \
    USE_SSL_CT=${USE_SSL_CT:-Off} \
    USE_SSL_OSCP=${USE_SSL_OSCP:-Off} \
    NO_SSL_REDIRECT=$([ $NO_SSL_REDIRECT -gt 0 2> /dev/null ] && echo off|| echo on ) \
    NO_USE_NAXSI=$([ $NO_USE_NAXSI -gt 0 2> /dev/null ] && echo \# || echo -n ) \
    NO_USE_SSLST=$([ $NO_USE_SSLST -gt 0 2> /dev/null ] && echo \# || echo -n ) \
    NAXSI_APP=$([ "x$KUSANAGI_PROVISION" = "xwp" ] && echo wp || echo general ) \
    /usr/bin/envsubst '$$FQDN $$DOCUMENTROOT $$NO_SSL_REDIRECT 
    $$USE_SSL_CT $$USE_SSL_CT $$USE_SSL_OSCP  $$NO_USE_SSLST
    $$NAXSI_APP $$SSL_CERT $$SSL_KEY $$KUSANAGI_PROVISION $$NO_USE_NAXSI' \
    < default.template > default.conf \
|| exit 1

if ! [ -f /etc/ssl/httpd/default.key -o -f /etc/ssl/httpd/default.pem ]; then
    cp /etc/ssl/httpd/localhost.key /etc/ssl/httpd/default.key
    cp /etc/ssl/httpd/localhost.pem /etc/ssl/httpd/default.pem
fi

#sed -i "s/^\(127.0.0.1.*\)\$/\1 $FQDN/" /etc/hosts || \
#	 (sed "s/\(^127.0.0.1.*$\)/\1 $FQDN/" /etc/hosts > /tmp/hosts && \
#	   cat /tmp/hosts > /etc/hosts && rm /tmp/hosts)

#//---------------------------------------------------------------------------
#// execute httpd
#//---------------------------------------------------------------------------
exec "$@"

