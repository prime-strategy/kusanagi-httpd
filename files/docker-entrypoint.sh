#!/bin/sh

function env2cert {
    file=$1
    var="$2"
    (echo "$var" | sed 's/"//g' | grep '^-----' > /dev/null) && 
    (echo "$var" | sed -e 's/"//g' -e 's/\r//g' | sed -e 's/- /-\n/' -e 's/ -/\n-/' | sed -e '2s/ /\n/g' > $file) && 
    echo -n $file || echo -n
}

[ "x$SSL_CERT" != "x" -a ! -f "$SSL_CERT" ] && SSL_CERT=$(env2cert /etc/httpd/default.pem "$SSL_CERT")
[ "x$SSL_KEY" != "x" -a ! -f "$SSL_KEY" ] && SSL_KEY=$(env2cert /etc/httpd/default.key "$SSL_KEY")

#//---------------------------------------------------------------------------
#// Improv security
#//---------------------------------------------------------------------------
# Improv Sec
if [ ! -e /etc/httpd/ssl_sess_ticket.key ] ; then
	openssl rand 48 > /etc/httpd/ssl_sess_ticket.key
fi
if [ ! -e /etc/httpd/dhparam.key ] ; then
    env2cert /etc/httpd/dhparam.key "$SSL_DHPARAM" > /dev/null
    test -f /etc/httpd/dhparam.key || openssl dhparam 2048 > /etc/httpd/dhparam.key 2> /dev/null
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
    SSL_CERT=${SSL_CERT:-/etc/httpd/default.crt} \
    SSL_KEY=${SSL_KEY:-/etc/httpd/default.key} \
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

if [ -f /etc/httpd/default.key -o -f /etc/httpd/default.crt ]; then
	/bin/true
else
	openssl genrsa -rand /proc/cpuinfo:/proc/dma:/proc/filesystems:/proc/interrupts:/proc/ioports:/proc/uptime 2048 > /etc/httpd/default.key 2> /dev/null

	cat <<-EOF | openssl req -new -key /etc/httpd/default.key \
		-x509 -sha256 -days 365 -set_serial 1 -extensions v3_req \
		-out /etc/httpd/default.crt 2>/dev/null
--
SomeState
SomeCity
SomeOrganization
SomeOrganizationalUnit
${FQDN}
root@${FQDN}
	EOF
fi

#sed -i "s/^\(127.0.0.1.*\)\$/\1 $FQDN/" /etc/hosts || \
#	 (sed "s/\(^127.0.0.1.*$\)/\1 $FQDN/" /etc/hosts > /tmp/hosts && \
#	   cat /tmp/hosts > /etc/hosts && rm /tmp/hosts)

#//---------------------------------------------------------------------------
#// execute httpd
#//---------------------------------------------------------------------------
exec "$@"

