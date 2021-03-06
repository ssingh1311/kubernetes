FROM centos:6

# install dependencies
RUN yum update -y \
 && yum install -y java-1.8.0-openjdk-devel patch git unzip

# environmental variables
ENV JAVA_HOME /etc/alternatives/jre

ENV HOST_URL localhost:8080
ENV FRONTEND_URL http://localhost:8080

ENV DB_TYPE h2
ENV DB_URL database_server_url
ENV DB_USER database_user
ENV DB_PASS database_password
ENV DB_SSL --no-db-ssl

# install into the /opt directory
WORKDIR /opt

# install the backend
RUN curl -sL https://s3.amazonaws.com/app-takipi-com/deploy/takipi-server/takipi-server-java.tar.gz | tar -xvzf -

# install Grafana
RUN curl -sL https://s3-us-west-2.amazonaws.com/grafana-releases/release/grafana-5.3.4.linux-amd64.tar.gz | tar -xzvf -

# install oo-influx-backend
RUN git clone https://github.com/takipi/overops-influx-backend.git

# configure Grafana
RUN cp -Rf overops-influx-backend/grafana/. grafana-5.3.4/.

WORKDIR /opt/grafana-5.3.4/

# install boomtable plugin
RUN curl -sL https://grafana.com/api/plugins/yesoreyeram-boomtable-panel/versions/0.4.6/download -o boomtable-panel.zip \
 && mkdir -p data/plugins \
 && unzip -d data/plugins boomtable-panel.zip \
 && rm boomtable-panel.zip

# configure Grafana - OO API runs in same container
RUN sed -e "s/\${TAKIPI_API_URL}/http:\/\/localhost:8080/g" -i conf/provisioning/datasources/oo.yaml

WORKDIR /opt


# use mount to make .properties files available
RUN mkdir private \
 && mv /opt/takipi-server/conf/tomcat-original/my.server.properties private/my.server.properties \
 && mv /opt/takipi-server/conf/tomcat-original/smtp.properties private/smtp.properties \
 && mv /opt/takipi-server/conf/tomcat-original/smtpserver.properties private/smtpserver.properties \
 && touch private/my.agentsettings.properties \
 && mkdir -p /opt/takipi-server/conf/tomcat/shared \
 && ln -s /opt/private/my.server.properties /opt/takipi-server/conf/tomcat/shared/my.server.properties \
 && ln -s /opt/private/smtp.properties /opt/takipi-server/conf/tomcat/shared/smtp.properties \
 && ln -s /opt/private/smtpserver.properties /opt/takipi-server/conf/tomcat/shared/smtpserver.properties \
 && ln -s /opt/private/my.agentsettings.properties /opt/takipi-server/conf/tomcat/shared/my.agentsettings.properties
VOLUME ["/opt/private"]

# use a volume to store data
VOLUME ["/opt/takipi-server/storage"]

# create a run script
RUN echo "#!/bin/bash" > run.sh \
 && echo "cat /opt/takipi-server/VERSION" >> run.sh \
 && echo "if [ -r /opt/takipi-server/storage/s3/data/onprem-sparktale/125/93/kd/KD.class ]" >> run.sh \
 && echo "then" >> run.sh \
 && echo "cp -p /opt/takipi-server/storage/s3/data/onprem-sparktale/125/93/kd/KD.class /opt/takipi-server/conf/tomcat/shared/." >> run.sh \
 && echo "fi" >> run.sh \
 && echo "sed -e \"s|\\\${TAKIPI_HOST_URL}|\${FRONTEND_URL}|g\" -i /opt/grafana-5.3.4/conf/custom.ini" >> run.sh \
 && echo "sed -e \"s|\/\/\\\$apiHost:\\\$apiPort\/|\${FRONTEND_URL}\/|g\" -i /opt/grafana-5.3.4/conf/provisioning/dashboards/overops/*.json" >> run.sh \
 && echo "pushd grafana-5.3.4; nohup ./bin/grafana-server web &> grafana.log &" >> run.sh \
 && echo "popd" >> run.sh \
 && echo "/opt/takipi-server/bin/takipi-server.sh -u \${HOST_URL} --frontend-url \${FRONTEND_URL} --db-type \${DB_TYPE} --db-url \${DB_URL} --db-user \${DB_USER} --db-password \${DB_PASS} \${DB_SSL} start" >> run.sh \
 && echo "/bin/sleep 10" >> run.sh \
 && echo "/usr/bin/tail -f /opt/takipi-server/log/tomcat/stdout -f /opt/takipi-server/log/tomcat/stderr -f -f /opt/takipi-server/log/tomcat/tomcat/catalina.log" >> run.sh \
 && chmod +x run.sh

# print version
RUN cat /opt/takipi-server/VERSION

EXPOSE 8080

# run the service, printing logs to stdout
CMD ["./run.sh"]