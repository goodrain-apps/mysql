#!/bin/bash

[ $DEBUG ] && set -x

MYSQL_USER="admin"
MYSQL_RANDOM_ROOT_PASSWORD="$(pwgen -1 32)"
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-${MYSQL_PASS:-$MYSQL_RANDOM_ROOT_PASSWORD}}
MYSQL_PASSWORD=$MYSQL_ROOT_PASSWORD

LOGFILE="$DATADIR/logs/error.log"
SLOWLOG="$DATADIR/logs/slow.log"

set -eo pipefail

case ${MEMORY_SIZE:-large} in
    "large")
       export INNODB_BUFFER_POOL_SIZE="256M" MAX_CONN="1000"
       echo "Optimizing Innodb_Buffer_Pool_Size for 1G Memory...."
       ;;
    "2xlarge")
       export INNODB_BUFFER_POOL_SIZE="1G" MAX_CONN="1200"
       echo "Optimizing Innodb_Buffer_Pool_Size for 2G Memory...."
       ;;
    "4xlarge")
       export INNODB_BUFFER_POOL_SIZE="2G" MAX_CONN="1500"
       echo "Optimizing Innodb_Buffer_Pool_Size for 4G Memory...."
       ;;
    "8xlarge")
       export INNODB_BUFFER_POOL_SIZE="4G" MAX_CONN="1800"
       echo "Optimizing Innodb_Buffer_Pool_Size for 8G Memory...."
       ;;
    16xlarge)
       export INNODB_BUFFER_POOL_SIZE="8G" MAX_CONN="2000"
       echo "Optimizing Innodb_Buffer_Pool_Size for 16G Memory...."
       ;;
    32xlarge)
       export INNODB_BUFFER_POOL_SIZE="16G" MAX_CONN="2500"
       echo "Optimizing Innodb_Buffer_Pool_Size for 32G Memory...."
       ;;
    64xlarge)
       export INNODB_BUFFER_POOL_SIZE="32G" MAX_CONN="3000"
       echo "Optimizing Innodb_Buffer_Pool_Size for 64G Memory...."
       ;;
    *)
       export INNODB_BUFFER_POOL_SIZE="256M" MAX_CONN="1000"
       echo "Optimizing Innodb_Buffer_Pool_Size for 1G Memory...."
       ;;
esac

# if command starts with an option, prepend mysqld
if [ "${1:0:1}" = '-' ]; then
	set -- mysqld "$@"
fi

# skip setup if they want an option that stops mysqld
wantHelp=
for arg; do
	case "$arg" in
		-'?'|--help|--print-defaults|-V|--version)
			wantHelp=1
			break
			;;
	esac
done

# replace innodb_buffer_pool_size and max_conn
sed -i -r "s/(innodb_buffer_pool_size)(.*)=.*/\1\2= $INNODB_BUFFER_POOL_SIZE/" $CONFDIR/my.cnf 
sed -i -r "s/(max_connections)(.*)=.*/\1\2= $MAX_CONN/" $CONFDIR/my.cnf 

if [ "$1" = 'mysqld' -a -z "$wantHelp" ]; then

	if [ ! -d "$DATADIR/data/mysql" ]; then
		if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
			echo >&2 'error: database is uninitialized and password option is not specified '
			echo >&2 '  You need to specify one of MYSQL_ROOT_PASSWORD, MYSQL_ALLOW_EMPTY_PASSWORD and MYSQL_RANDOM_ROOT_PASSWORD'
			exit 1
		fi
		
		# create data dirtctory
 		/bin/bash -c "mkdir -pv $DATADIR/{data,logs,tmp}" 
		chown -R mysql:mysql "$DATADIR"

		echo 'Initializing database'
		mysql_install_db --user=mysql --datadir="${DATADIR}/data" --rpm --keep-my-cnf
		echo 'Database initialized'
		
		"$@" --skip-networking &
		pid="$!"

		mysql=( mysql --protocol=socket -uroot )

		for i in {30..0}; do
			if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
				break
			fi
			echo 'MySQL init process in progress...'
			sleep 1
		done
		if [ "$i" = 0 ]; then
			echo >&2 'MySQL init process failed.'
			rm -rf $DATADIR/*
			exit 1
		fi

		if [ -z "$MYSQL_INITDB_SKIP_TZINFO" ]; then
			# sed is for https://bugs.mysql.com/bug.php?id=20545
			mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql
		fi

		"${mysql[@]}" <<-EOSQL
			-- What's done in this file shouldn't be replicated
			--  or products like mysql-fabric won't work
			SET @@SESSION.SQL_LOG_BIN=0;

			DELETE FROM mysql.user ;
			CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
			GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;
			DROP DATABASE IF EXISTS test ;
			FLUSH PRIVILEGES ;
		EOSQL

		if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
			mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
		fi

		if [ "$MYSQL_DATABASE" ]; then
			echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
			mysql+=( "$MYSQL_DATABASE" )
		fi

		if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
			echo "CREATE USER '$MYSQL_USER'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' ;" | "${mysql[@]}"
			echo "GRANT ALL ON *.* TO '$MYSQL_USER'@'%' ;" | "${mysql[@]}"
			echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
		fi

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)     echo "$0: running $f"; . "$f" ;;
				*.sql)    echo "$0: running $f"; "${mysql[@]}" < "$f"; echo ;;
				*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${mysql[@]}"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done

		if [ ! -z "$MYSQL_ONETIME_PASSWORD" ]; then
			"${mysql[@]}" <<-EOSQL
				ALTER USER 'root'@'%' PASSWORD EXPIRE;
			EOSQL
		fi
		if ! kill -s TERM "$pid" || ! wait "$pid"; then
			echo >&2 'MySQL init process failed.'
			exit 1
		fi

		echo
		echo 'MySQL init process done. Ready for start up.'
		echo
	fi
	
	chown -R mysql:mysql "$DATADIR"

fi

tail -F $LOGFILE &
tail -f $SLOWLOG &

# run mysql-sniffer
/opt/bin/mysql-sniffer \
-i=eth1 \
-P=3306 \
--service_id=${SERVICE_ID} \
--tenant_id=${TENANT_ID} \
--zmq_addr=tcp://172.30.42.1:7388 \
--topic=cep.mysql.sniff.${SERVICE_ID} \
-v=false &

exec "$@"
