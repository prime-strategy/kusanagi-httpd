#//----------------------------------------------------------------------------
#// Apache HTTP Server ( for KUSANAGI Run on Docker )
#//----------------------------------------------------------------------------
FROM centos:7
MAINTAINER kusanagi@prime-strategy.co.jp

ENV KUSANAGI_VERSION		7.8.2-2
ENV KUSANAGI_WP_VERSION		4.5.2-1
ENV KUSANAGI_HTTPD_VERSION	2.4.18-5
ENV KUSANAGI_NGHTTP2_VERSION	1.6.0-2
ENV KUSANAGI_OPENSSL_VERSION	1.0.2h-1

RUN groupadd -g 1000 www \
	&& groupadd -g 1001 kusanagi \
	&& useradd -d /home/httpd -c '' -s /bin/false -G www -M -u 1000 httpd \
	&& useradd -d /home/kusanagi -c '' -s /bin/bash -g kusanagi -G www -u 1001 kusanagi \
	&& chmod 755 /home/kusanagi

RUN \
	curl -fSL https://repo.prime-strategy.co.jp/rpm/noarch/kusanagi-${KUSANAGI_VERSION}.noarch.rpm -o kusanagi.rpm \
	&& curl -fSL https://repo.prime-strategy.co.jp/rpm/noarch/kusanagi-wp-${KUSANAGI_WP_VERSION}.noarch.rpm -o kusanagi-wp.rpm \
	&& curl -fSL https://repo.prime-strategy.co.jp/rpm/noarch/kusanagi-httpd-${KUSANAGI_HTTPD_VERSION}.noarch.rpm -o kusanagi-httpd.rpm \
	&& curl -fSL https://repo.prime-strategy.co.jp/rpm/noarch/kusanagi-nghttp2-${KUSANAGI_NGHTTP2_VERSION}.noarch.rpm -o kusanagi-nghttp2.rpm \
	&& curl -fSL https://repo.prime-strategy.co.jp/rpm/noarch/kusanagi-openssl-${KUSANAGI_OPENSSL_VERSION}.noarch.rpm -o kusanagi-openssl.rpm \
	&& rpm --nodeps -Uvh kusanagi.rpm kusanagi-openssl.rpm \
	&& yum install -y epel-release \
	&& yum localinstall -y kusanagi-wp.rpm \
	&& rpm -ivh http://rpms.famillecollet.com/enterprise/remi-release-7.rpm \
	&& yum --enablerepo=remi,remi-php56 localinstall -y kusanagi-httpd.rpm kusanagi-nghttp2.rpm \
	&& yum install -y wget openssl \
	&& rm -f kusanagi*.rpm \
	&& yum clean all

RUN mkdir -p /var/log/nginx /etc/nginx/conf.d /etc/httpd/conf.d \
	&& sed -i 's/^sed.*\/etc\/hosts/#sed/' /usr/lib/kusanagi/lib/virt.sh \
	&& sed -i 's/systemctl/\/bin\/true/g' /usr/lib/kusanagi/lib/virt.sh

RUN cp /etc/httpd/mime.types /etc/mime.types

VOLUME /home/kusanagi
VOLUME /etc/nginx/conf.d
VOLUME /etc/httpd/conf.d
VOLUME /etc/kusanagi.d

# libphp5-zts.so: cannot open shared object file: No such file or directory
COPY files/10-php.conf /etc/httpd/conf.modules.d/10-php.conf

COPY files/docker-entrypoint.sh /
ENTRYPOINT [ "/docker-entrypoint.sh" ]
CMD [ "/usr/sbin/httpd", "-DFOREGROUND" ]
