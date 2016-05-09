FROM debian:jessie

# ENV
ENV MYSQL_MAJOR 5.6
ENV MYSQL_VERSION 5.6.30-1debian8
ENV DATADIR /data
ENV CONFDIR /etc/mysql


# timezone
RUN echo "Asia/Shanghai" > /etc/timezone;dpkg-reconfigure -f noninteractive tzdata

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -g 200 -r mysql && useradd -u 200 -r -g mysql mysql

RUN mkdir /docker-entrypoint-initdb.d

# FATAL ERROR: please install the following Perl modules before executing /usr/local/mysql/scripts/mysql_install_db:
# File::Basename
# File::Copy
# Sys::Hostname
# Data::Dumper
RUN apt-get update && apt-get install -y perl wget pwgen --no-install-recommends && rm -rf /var/lib/apt/lists/*

# gpg: key 5072E1F5: public key "MySQL Release Engineering <mysql-build@oss.oracle.com>" imported
RUN apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys A4A9406876FCBD3C456770C88C718D3B5072E1F5

RUN echo "deb http://repo.mysql.com/apt/debian/ jessie mysql-${MYSQL_MAJOR}" > /etc/apt/sources.list.d/mysql.list

# the "/var/lib/mysql" stuff here is because the mysql-server postinst doesn't have an explicit way to disable the mysql_install_db codepath besides having a database already "configured" (ie, stuff in /var/lib/mysql/mysql)
# also, we set debconf keys to make APT a little quieter
RUN { \
		echo mysql-community-server mysql-community-server/data-dir select ''; \
		echo mysql-community-server mysql-community-server/root-pass password ''; \
		echo mysql-community-server mysql-community-server/re-root-pass password ''; \
		echo mysql-community-server mysql-community-server/remove-test-db select false; \
	} | debconf-set-selections \
	&& apt-get update && apt-get install -y mysql-server="${MYSQL_VERSION}" && rm -rf /var/lib/apt/lists/* \
	&& rm -rf /var/lib/mysql && mkdir -p /var/lib/mysql

# add mysql-sniffer for cep monitor
RUN mkdir /opt/bin && apt-get update && apt-get install -y libpgm-5.1-0 libpcap0.8 \
    && wget http://lang.goodrain.me/public/libzmq.so.4 -O /usr/lib/x86_64-linux-gnu/libzmq.so.4 \
    && wget http://lang.goodrain.me/public/mysql-sniffer -O /opt/bin/mysql-sniffer \
    && chmod 755 /opt/bin/mysql-sniffer

VOLUME /data

# copy etc dir
COPY 5.6/etc /etc

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh # backwards compat

# clear unnecessary files
RUN rm -rf /usr/share/doc && \
    rm -rf /usr/share/man && \

ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 3306
CMD ["mysqld"]
