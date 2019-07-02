#//----------------------------------------------------------------------------
#// Apache HTTP Server ( for KUSANAGI Run on Docker )
#//----------------------------------------------------------------------------
FROM alpine:3.10
MAINTAINER kusanagi@prime-strategy.co.jp

ENV HTTPD_VERSION=2.4.39
ENV HTTPD_SHA256=b4ca9d05773aa59b54d66cd8f4744b945289f084d3be17d7981d1783a5decfa2

ENV HTTPD_PREFIX /usr/local/apache2
ENV PATH $HTTPD_PREFIX/bin:$PATH
RUN : \
        && apk update \
        && apk upgrade \
        && apk add --no-cache --virtual .user shadow \
        && groupadd -g 1001 www \
        && useradd -d $HTTPD_PREFIX -s /bin/nologin -g www -m -u 1001 httpd \
        && groupadd -g 1000 kusanagi \
        && useradd -d /home/kusanagi -s /bin/nologin -g kusanagi -G www -u 1000 -m kusanagi \
        && chmod 755 /home/kusanagi \
        && apk del --purge .user \
        && mkdir /tmp/build \
        && : # END of RUN

WORKDIR $HTTPD_PREFIX

RUN :\
	&& APACHE_DIST_URLS=' \
	https://www.apache.org/dyn/closer.cgi?action=download&filename= \
	https://www-us.apache.org/dist/  \
	https://www.apache.org/dist/  \
	https://archive.apache.org/dist/' \
	&& runDeps=' \
		apr-dev \
		apr-util-dev \
		apr-util-ldap \
		perl ' \
	&& apk add --no-cache --virtual .build-deps \
		$runDeps \
		ca-certificates \
		coreutils \
		dpkg-dev dpkg \
		gcc \
		gnupg \
		libc-dev \
		curl-dev \
		jansson-dev \
		libxml2-dev \
		lua-dev \
		make \
		nghttp2-dev \
		openssl \
		openssl-dev \
		pcre-dev \
		tar \
		zlib-dev \
	&& cd /tmp \
	&& ddist() { \
		local f="$1"; shift; \
		local distFile="$1"; shift; \
		local success=; \
		local distUrl=; \
		for distUrl in $APACHE_DIST_URLS; do \
			if wget -O "$f" "$distUrl$distFile" && [ -s "$f" ]; then \
				success=1; \
				break; \
			fi; \
		done; \
		[ -n "$success" ]; \
	} \
	&& ddist 'httpd.tar.bz2' "httpd/httpd-$HTTPD_VERSION.tar.bz2" \
	&& echo "$HTTPD_SHA256 *httpd.tar.bz2" | sha256sum -c - \
	&& ddist 'httpd.tar.bz2.asc' "httpd/httpd-$HTTPD_VERSION.tar.bz2.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& for key in \
# gpg: key 791485A8: public key "Jim Jagielski (Release Signing Key) <jim@apache.org>" imported
		A93D62ECC3C8EA12DB220EC934EA76E6791485A8 \
# gpg: key 995E35221AD84DFF: public key "Daniel Ruggeri (https://home.apache.org/~druggeri/) <druggeri@apache.org>" imported
		B9E8213AEFB861AF35A41F2C995E35221AD84DFF \
	; do \
		gpg --batch --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
	done \
	&& gpg --batch --verify httpd.tar.bz2.asc httpd.tar.bz2 \
	&& command -v gpgconf && gpgconf --kill all || : \
	&& rm -rf "$GNUPGHOME" httpd.tar.bz2.asc \
	&& mkdir -p src \
	&& tar -xf httpd.tar.bz2 -C src --strip-components=1 \
	&& rm httpd.tar.bz2 \
	&& cd src \
	&& ./configure \
		--enable-modules=all \
		--enable-mods-shared=all \
		--enable-proxy-fdpass \
		--enable-mpms-shared='prefork worker event' \
		--enable-lua \
		--enable-sed \
		--enable-http2 \
		--enable-ssl \
		--enable-unique-id \
		--enable-xml2enc \
		--enable-proxy-html \
		--with-nghttp2=/usr \
		--with-ssl=/usr \
		--enable-so \
		--enable-deflate \
		--enable-suexec \
		--with-mpm=event \
		--sysconfdir=/etc/httpd \
		--includedir=/usr/include/httpd \
		--libexecdir=/etc/httpd/modules \
		--with-installbuilddir=/lib/httpd/build \
	&& make -j "$(nproc)" \
	&& make install  \
	&& cd .. \
	&& rm -rf src \
	&& runDeps="$runDeps $( \
		scanelf --needed --nobanner --format '%n#p' --recursive /usr/local \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)" \
	&& apk add --virtual .httpd-rundeps $runDeps \
	&& apk del .build-deps \
	&& httpd -v \
	&& mkdir -p /etc/httpd/conf.d /etc/httpd/modules.d \
	&& : # END OF RUN


COPY files/httpd /etc

ARG MICROSCANNER_TOKEN
RUN if [ x${MICROSCANNER_TOKEN} != x ] ; then \
	apk add --no-cache --virtual .ca ca-certificates \
	&& update-ca-certificates\
	&& wget --no-check-certificate https://get.aquasec.com/microscanner \
	&& chmod +x microscanner \
	&& ./microscanner ${MICROSCANNER_TOKEN} || exit 1\
	&& rm ./microscanner \
	&& apk del --purge .ca ;\
    fi

EXPOSE 8080
EXPOSE 8443
VOLUME /home/kusanagi
VOLUME /etc/letsencrypt

USER httpd
COPY files/docker-entrypoint.sh /
ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "httpd", "-DFOREGROUND" ]
