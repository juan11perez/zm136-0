# FROM	 	nvidia/cuda:11.2.0-cudnn8-devel-ubuntu20.04
FROM		phusion/baseimage:master
# LABEL maintainer=""

ENV		DEBCONF_NONINTERACTIVE_SEEN="true" \
		DEBIAN_FRONTEND="noninteractive" \
		DISABLE_SSH="true" \
		HOME="/root" \
		LC_ALL="en_US.UTF-8" \
		LANG="en_US.UTF-8" \
		LANGUAGE="en_US.UTF-8" \
		TZ="Etc/UTC" \
		TERM="xterm" \
		PHP_VERS="7.4" \
		ZM_VERS="1.36" \
		PUID="99" \
		PGID="100"\
		OPEN_CV_VERSION="4.5.3"

COPY		defaults/ /root/
COPY		init/ /etc/my_init.d/
RUN		chmod +x /etc/my_init.d/*

# RUN 		apt-get update && \
		# apt-get -y install software-properties-common runit-systemd && \
RUN		add-apt-repository -y ppa:iconnor/zoneminder-$ZM_VERS && \
		add-apt-repository ppa:ondrej/php && \
		add-apt-repository ppa:ondrej/apache2 && \
		apt-get update && \
		apt-get -y upgrade -o Dpkg::Options::="--force-confold" && \
		apt-get -y dist-upgrade -o Dpkg::Options::="--force-confold" && \
		apt-get -y install apache2 mariadb-server && \
		apt-get -y install ssmtp mailutils net-tools wget sudo make cmake gcc curl git && \
		apt-get -y install php$PHP_VERS php$PHP_VERS-fpm libapache2-mod-php$PHP_VERS php$PHP_VERS-mysql php$PHP_VERS-gd && \
		apt-get -y install libcrypt-mysql-perl libyaml-perl libjson-perl libavutil-dev ffmpeg libx11-dev && \
		apt-get -y install --no-install-recommends libvlc-dev libvlccore-dev vlc-bin vlc-plugin-base vlc-plugin-video-output && \
		apt-get -y install zoneminder

RUN		rm /etc/mysql/my.cnf && \
		cp /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/my.cnf && \
		adduser www-data video && \
		a2enmod php$PHP_VERS proxy_fcgi ssl rewrite expires headers && \
		a2enconf php$PHP_VERS-fpm zoneminder && \
		echo "extension=apcu.so" > /etc/php/$PHP_VERS/mods-available/apcu.ini && \
		echo "extension=mcrypt.so" > /etc/php/$PHP_VERS/mods-available/mcrypt.ini && \
		perl -MCPAN -e "force install Net::WebSocket::Server" && \
		perl -MCPAN -e "force install LWP::Protocol::https" && \
		perl -MCPAN -e "force install Config::IniFiles" && \
		perl -MCPAN -e "force install Net::MQTT::Simple" && \
		perl -MCPAN -e "force install Net::MQTT::Simple::Auth" && \
		perl -MCPAN -e "force install Time::Piece"

RUN		apt-get -y install python3-pip && \
		apt-get -y install libopenblas-dev liblapack-dev libblas-dev && \
		pip3 install future && pip3 install face_recognition && \
		cd /root && git clone https://github.com/zoneminder/zmeventnotification.git && \
		cd zmeventnotification && git fetch --tags && \
		git checkout $(git describe --tags $(git rev-list --tags --max-count=1)) 2>/dev/null && \	
		# Replace certificate path in secrets.ini file
		sed -i 's#/path/to/cert/file.pem#/etc/apache2/ssl/zoneminder.crt#g'  /root/zmeventnotification/secrets.ini  && \
		sed -i 's#/path/to/key/file.pem#/etc/apache2/ssl/zoneminder.key#g'  /root/zmeventnotification/secrets.ini && \
		yes | INSTALL_CORAL_EDGETPU=yes INSTALL_YOLOV3=yes INSTALL_YOLOV4=yes INSTALL_TINYYOLOV3=no INSTALL_TINYYOLOV4=yes ./install.sh

		# install coral usb libraries
RUN 		echo "deb https://packages.cloud.google.com/apt coral-edgetpu-stable main" | tee /etc/apt/sources.list.d/coral-edgetpu.list && \
		curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
		apt-get update && apt-get -y install gasket-dkms libedgetpu1-std python3-pycoral

RUN		cd /root && \
		chown -R www-data:www-data /usr/share/zoneminder/ && \
		echo "ServerName localhost" >> /etc/apache2/apache2.conf && \
		sed -i "s|^;date.timezone =.*|date.timezone = ${TZ}|" /etc/php/$PHP_VERS/apache2/php.ini && \
		service mysql start && \
		mysql -e "drop database zm;" && \
		mysql -uroot < /usr/share/zoneminder/db/zm_create.sql && \
		mysql -uroot -e "grant all on zm.* to 'zmuser'@localhost identified by 'zmpass';" && \
		mysqladmin -uroot reload && \
		mysql -sfu root < "mysql_secure_installation.sql" && \
		rm mysql_secure_installation.sql && \
		mysql -sfu root < "mysql_defaults.sql" && \
		rm mysql_defaults.sql

RUN		mv /root/zoneminder /etc/init.d/zoneminder && \
		chmod +x /etc/init.d/zoneminder && \
		service mysql restart && \
		sleep 5 && \
		service apache2 start && \
		service zoneminder start

# RUN		touch /usr/lib/tmpfiles.d/zoneminder.conf && \
RUN		systemd-tmpfiles --create zoneminder.conf && \
		mv /root/default-ssl.conf /etc/apache2/sites-enabled/default-ssl.conf && \
		mkdir /etc/apache2/ssl/ && \
		mkdir -p /var/lib/zmeventnotification/images && \
		chown -R www-data:www-data /var/lib/zmeventnotification/ && \
		chmod -R +x /etc/my_init.d/ && \
		cp -p /etc/zm/zm.conf /root/zm.conf && \
		# mkdir /etc/cron.weekly/ && \	
		echo "#!/bin/sh\n\n/usr/bin/zmaudit.pl -f" >> /etc/cron.weekly/zmaudit && \
		chmod +x /etc/cron.weekly/zmaudit && \
		chown -R root:root /etc/cron.d/e2scrub_all && \
		cp /etc/apache2/ports.conf /etc/apache2/ports.conf.default && \
		cp /etc/apache2/sites-enabled/default-ssl.conf /etc/apache2/sites-enabled/default-ssl.conf.default && \
		apt install -y syslog-ng && \
		sed -i s#3.13#3.25#g /etc/syslog-ng/syslog-ng.conf && \
		sed -i 's#use_dns(no)#use_dns(yes)#' /etc/syslog-ng/syslog-ng.conf

RUN		cd /root && \
		wget -q -O opencv.zip https://github.com/opencv/opencv/archive/${OPEN_CV_VERSION}.zip && \
		wget -q -O opencv_contrib.zip https://github.com/opencv/opencv_contrib/archive/${OPEN_CV_VERSION}.zip && \
		unzip opencv.zip && \
		unzip opencv_contrib.zip && \
		mv $(ls -d opencv-*) opencv && \
		mv opencv_contrib-${OPEN_CV_VERSION} opencv_contrib && \
		rm *.zip && \
		cd /root/opencv && \
		mkdir build && \
		cd build && \
		cmake -D CMAKE_BUILD_TYPE=RELEASE -D CMAKE_INSTALL_PREFIX=/usr/local -D INSTALL_PYTHON_EXAMPLES=OFF -D INSTALL_C_EXAMPLES=OFF -D OPENCV_ENABLE_NONFREE=ON -D OPENCV_EXTRA_MODULES_PATH=/root/opencv_contrib/modules -D HAVE_opencv_python3=ON -D PYTHON_EXECUTABLE=/usr/bin/python3 -D PYTHON2_EXECUTABLE=/usr/bin/python2 -D BUILD_EXAMPLES=OFF .. >/dev/null && \
		make -j4 && \
		make install && \
		cd /root && \
		rm -r opencv*

RUN		apt-get -y clean && \
		apt-get -y autoremove && \
		rm -rf /tmp/* /var/tmp/* /root/zmeventnotification* /root/my_init && \
		chmod +x /etc/my_init.d/*.sh

VOLUME \
		["/config"] \
		["/var/cache/zoneminder"]

EXPOSE		80 443 9000

CMD		["/sbin/my_init"]



# Added line 97 "mkdir /etc/cron.weekly/ && \" when trying to build from nvidia image
# HEALTHCHECK 	--interval=30s --timeout=5s --start-period=5s CMD curl --fail http://localhost:$SERVER_PORT/health || exit 1
