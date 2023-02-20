#//----------------------------------------------------------------------------
#// Apache HTTP Server ( for KUSANAGI Run on Docker )
#//----------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM alpine:3.17.2
LABEL maintainer=kusanagi@prime-strategy.co.jp

ENV HTTPD_VERSION=2.4.55
ENV HTTPD_SHA256=11d6ba19e36c0b93ca62e47e6ffc2d2f2884942694bce0f23f39c71bdc5f69ac
ENV HTTPD_PREFIX /usr/local/apache2
ENV PATH $HTTPD_PREFIX/bin:$PATH

RUN : \
	&& apk add --no-cache --virtual .user shadow \
	&& groupadd -g 1001 www \
	&& useradd -d $HTTPD_PREFIX -s /bin/sh -g www -m -u 1001 httpd \
	&& groupadd -g 1000 kusanagi \
	&& useradd -d /home/kusanagi -s /bin/false -g kusanagi -G www -u 1000 -m kusanagi \
	&& chmod 755 /home/kusanagi \
	&& apk del --purge .user \
	&& mkdir /tmp/build \
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
		binutils \
		ca-certificates \
		coreutils \
		dpkg-dev \
		dpkg \
		gcc \
		patch \
		gnupg \
		libc-dev \
		curl-dev=7.87.0-r2 \
		jansson-dev \
		libxml2-dev \
		lua5.3-dev \
		luajit-dev \
		make \
		mariadb-dev \
		nghttp2-dev \
		nghttp2-libs \
		openssl \
		openssl-dev \
		brotli \
		brotli-dev \
		pcre2-dev \
		tar \
		zlib-dev \
		gettext \
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
		LIBS='-lluajit-5.1' \
		--enable-modules=all \
		--enable-mods-shared=all \
		--enable-proxy-fdpass \
		--enable-mpms-shared='prefork worker event' \
		--enable-lua=static \
		--enable-luajit \
		--enable-sed \
		--enable-http2 \
		--enable-ssl \
		--enable-unique-id \
		--enable-xml2enc \
		--enable-proxy-html \
		--enable-so \
		--enable-brotli \
		--enable-suexec \
		--with-z=/usr \
		--with-lua=/usr/lua5.3 \
		--with-luajit=/usr \
		--with-brotli=/usr \
		--with-nghttp2=/usr \
		--with-ssl=/usr \
		--with-mpm=event \
		--sysconfdir=/etc/httpd \
		--includedir=/usr/include/httpd \
		--libexecdir=/etc/httpd/modules \
	&& make -j "$(nproc)" \
	&& make install  \
	&& cd .. \
	&& rm -rf src $HTTPD_PREFIX/man $HTTPD_PREFIX/manual $HTTPD_PREFIX/icons \
	&& mv /usr/bin/envsubst /tmp \
	&& runDeps="$runDeps $( \
		scanelf --needed --nobanner --format '%n#p' --recursive /tmp/envsubst /usr/local /etc/httpd \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)" \
	&& apk add --virtual .httpd-rundeps $runDeps openssl luajit \
	&& apk del .build-deps \
	&& mv /tmp/envsubst /usr/bin \
	&& cd /tmp \
	&& rm -rf /tmp/build \
	&& httpd -v \
	&& HTTPDIR="/etc/httpd/conf.d /etc/httpd/modules.d /var/www/html /tmp/httpd " \
	&& mkdir -p -m 750 $HTTPDIR \
	&& chown -R httpd:www /etc/httpd /var/www/html /tmp/httpd \
	&& :


COPY files/httpd/ /etc/
COPY files/httpd/httpd.conf /etc/httpd/
COPY files/httpd/conf.d/ /etc/httpd/conf.d/
COPY files/httpd/conf.modules.d/ /etc/httpd/conf.modules.d/
COPY files/httpd/modsecurity.d/ /etc/httpd/modsecurity.d
COPY files/docker-entrypoint.sh /

RUN : \
	&& apk add --no-cache --virtual .curl curl \
	&& curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /tmp \
	&& /tmp/trivy filesystem --skip-files /tmp/trivy --exit-code 1 --no-progress / \
    && rm /tmp/trivy \
	&& apk del .curl \
	&& :

EXPOSE 8080
EXPOSE 8443
VOLUME /home/kusanagi
VOLUME /etc/letsencrypt

USER httpd
WORKDIR $HTTPD_PREFIX
ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "httpd", "-DFOREGROUND" ]
