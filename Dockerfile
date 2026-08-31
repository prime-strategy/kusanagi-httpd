#//----------------------------------------------------------------------------
#// Apache HTTP Server ( for KUSANAGI Run on Docker )
#//----------------------------------------------------------------------------
#// httpd_check is pure Go (no cgo), so it cross-compiles on the native build
#// platform instead of paying for emulation.
FROM --platform=$BUILDPLATFORM golang:1.26.7-alpine3.24 AS build-go
ARG TARGETOS TARGETARCH TARGETVARIANT
COPY files/httpd_check.go /tmp
RUN set -eux; \
	export CGO_ENABLED=0 GOOS="$TARGETOS" GOARCH="$TARGETARCH"; \
	if [ "$TARGETARCH" = "arm" ]; then export GOARM="${TARGETVARIANT#v}"; fi; \
	go build -o /go/httpd_check /tmp/httpd_check.go

#// Built once per target platform: httpd is compiled for the target arch, under
#// emulation when the runner is not native. Do NOT pin this to $BUILDPLATFORM --
#// that silently ships amd64 binaries under every arch of the manifest list.
FROM alpine:3.24.1
ARG TARGETARCH
LABEL maintainer=kusanagi@prime-strategy.co.jp

ENV HTTPD_VERSION=2.4.68
ENV HTTPD_SHA256=68c74d4df38c26bed4dfbdb8f3baf1eb532f3872357becc1bba5d136f6b63c06
ENV HTTPD_PREFIX=/usr/local/apache2
ENV PATH=$HTTPD_PREFIX/bin:$PATH
ENV FQDN=localhost
COPY files/lua_vmprep.patch /tmp/
COPY --from=build-go /go/httpd_check /usr/local/bin/httpd_check

WORKDIR /tmp
RUN : \
	`#// LuaJIT has no RISC-V port, so Alpine ships no luajit/luajit-dev on` \
	`#// riscv64. That target falls back to stock Lua 5.3 for mod_lua.` \
	&& if [ "$TARGETARCH" = "riscv64" ]; then \
		luaBuildDeps=''; \
		luaRunDeps=''; \
		luaLibs=''; \
		luaOpts='--enable-lua=static --with-lua=/usr/lua5.3'; \
	else \
		luaBuildDeps='luajit-dev'; \
		luaRunDeps='luajit'; \
		luaLibs='-lluajit-5.1'; \
		luaOpts='--enable-lua=static --enable-luajit --with-lua=/usr/lua5.3 --with-luajit=/usr'; \
	fi \
	&& apk upgrade --no-cache \
		busybox \
		musl \
		musl-utils \
		zlib\
		openssl \
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
		gnupg \
		libc-dev \
		curl \
		curl-dev \
		jansson-dev \
		libxml2-dev \
		lua5.3-dev \
		$luaBuildDeps \
		make \
		mariadb-dev \
		nghttp2-dev \
		nghttp2-libs \
		openssl-dev \
		brotli \
		brotli-dev \
		pcre2-dev \
		tar \
		zlib-dev \
		gettext \
		patch \
	&& ddist() { \
		local f="$1"; shift; \
		local distFile="$1"; shift; \
		local success=; \
		local distUrl=; \
		for distUrl in $APACHE_DIST_URLS; do \
			if curl -4Lo "$f" "$distUrl$distFile" && [ -s "$f" ]; then \
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
	&& (cd src \
		&& patch -p1 < /tmp/lua_vmprep.patch \
		&& ./configure \
			CFLAGS='-O2 -g -Wimplicit-function-declaration' \
			LIBS="$luaLibs" \
			--enable-modules=all \
			--enable-mods-shared=all \
			--enable-proxy-fdpass \
			--enable-mpms-shared='prefork worker event' \
			$luaOpts \
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
			--with-brotli=/usr \
			--with-nghttp2=/usr \
			--with-ssl=/usr \
			--with-mpm=event \
			--sysconfdir=/etc/httpd \
			--includedir=/usr/include/httpd \
			--libexecdir=/etc/httpd/modules \
		&& make -j "$(nproc)" install ) \
	&& grep -rl ELF $HTTPD_PREFIX/bin | xargs strip \
	&& rm -rf src $HTTPD_PREFIX/man $HTTPD_PREFIX/manual $HTTPD_PREFIX/icons \
	&& mv /usr/bin/envsubst /tmp \
	&& runDeps="$( \
		scanelf --needed --nobanner --format '%n#p' --recursive /tmp/envsubst /usr/local /etc/httpd \
			| tr ',' '\n' \
			| sort -u \
			| awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
	)" \
	&& apk add --no-cache --virtual .httpd-rundeps $runDeps openssl $luaRunDeps perl \
	&& apk del --purge .build-deps \
	&& mv /tmp/envsubst /usr/bin \
	&& rm -rf /tmp/build /tmp/httpd /tmp/lua_vmprep.patch \
	&& httpd -v \
	&& HTTPDIR="/etc/httpd/conf.d /etc/httpd/modules.d  /etc/ssl/httpd /var/www/html /tmp/httpd" \
	&& mkdir -p -m 750 $HTTPDIR \
	&& chown -R httpd:www /etc/httpd /etc/ssl/httpd /var/www/html /tmp/httpd \
	&& :


COPY files/httpd/ /etc/
COPY files/httpd/httpd.conf /etc/httpd/
COPY files/httpd/conf.d/ /etc/httpd/conf.d/
COPY files/httpd/conf.modules.d/ /etc/httpd/conf.modules.d/
COPY files/httpd/modsecurity.d/ /etc/httpd/modsecurity.d
COPY files/docker-entrypoint.sh /

#// The trivy scan used to live here as an in-build RUN. That cannot work once
#// the image is really cross-built: trivy publishes no riscv64 binary at all,
#// and on big-endian targets trivy-db (a native-endian bbolt file) fails to
#// open. The scan now runs natively on the runner against the built image --
#// see .github/workflows/docker-publish.yml.

EXPOSE 8080
EXPOSE 8443
VOLUME /home/kusanagi
VOLUME /etc/letsencrypt

USER httpd
WORKDIR $HTTPD_PREFIX
HEALTHCHECK --interval=10s --timeout=3s CMD /usr/local/bin/httpd_check
ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "httpd", "-DFOREGROUND" ]
