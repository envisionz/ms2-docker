FROM tomcat:9-jre11-openjdk-slim-bullseye

# Tomcat specific options
ENV JAVA_OPTS="${JAVA_OPTS}  -Xms512m -Xmx512m"

ARG MS2_TAG=v2021.01.04
ARG GEOSTORE_VERS=v1.6.0

RUN apt-get update && apt-get install -y postgresql-client jq xmlstarlet gettext curl unzip git && apt-get clean

ARG MS2_USER=mapstore
ARG MS2_GROUP=mapstore
ARG MS2_UID=5005
ARG MS2_GID=50005

RUN groupadd -r ${MS2_GROUP} -g ${MS2_GID} && \
    useradd -m -d /home/${MS2_USER}/ -u ${MS2_UID} --gid ${MS2_GID} -s /bin/bash -G ${MS2_GROUP} ${MS2_USER}

RUN chown -R "${MS2_USER}:${MS2_GROUP}" ${CATALINA_HOME}

# Download and extract Mapstore2 WAR files
RUN cd ${CATALINA_HOME}/webapps && \
    curl -L -o mapstore.war https://github.com/geosolutions-it/MapStore2/releases/download/${MS2_TAG}/mapstore.war && \
    curl -L -o mapstore-printing.zip https://github.com/geosolutions-it/MapStore2/releases/download/${MS2_TAG}/mapstore-printing.zip && \
    mkdir ./mapstore && \
    cd ./mapstore && unzip ../mapstore.war && \
    unzip ../mapstore-printing.zip && cd .. && \
    rm mapstore.war mapstore-printing.zip && \
    chown -R "${MS2_USER}:${MS2_GROUP}" ./mapstore

# Dowonload Geostore and extract sql scripts
RUN git clone https://github.com/geosolutions-it/geostore.git -b ${GEOSTORE_VERS} && \
    mkdir -p /internal-config/sql && cp -R geostore/doc/sql/. /internal-config/sql && rm -rf geostore

# Copy files required for customization
COPY ./config/ /internal-config/
# Set variable to better handle terminal commands
ENV TERM xterm

RUN mkdir -p /h2db \
    && chown "${MS2_USER}:${MS2_GROUP}" /h2db /internal-config/user_init_list.xml

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV MS2_SCRIPT_DIR=/scripts
RUN mkdir -p ${MS2_SCRIPT_DIR}

# Get common tomcat function for paths and proxy
RUN curl -o ${MS2_SCRIPT_DIR}/tc_common.sh https://raw.githubusercontent.com/envisionz/docker-common/18906e698a9de3c8bc4ae81557b3df6611132ea4/tomcat/tomcat-common.sh \
    && chown "${MS2_USER}:${MS2_GROUP}" ${MS2_SCRIPT_DIR}/tc_common.sh \
    && chmod +x ${MS2_SCRIPT_DIR}/tc_common.sh

# Get tomcat healthcheck script
RUN curl -o ${MS2_SCRIPT_DIR}/tc_healthcheck.sh https://raw.githubusercontent.com/envisionz/docker-common/18906e698a9de3c8bc4ae81557b3df6611132ea4/tomcat/healthcheck.sh \
    && chown "${MS2_USER}:${MS2_GROUP}" ${MS2_SCRIPT_DIR}/tc_healthcheck.sh \
    && chmod +x ${MS2_SCRIPT_DIR}/tc_healthcheck.sh
ENV HEALTH_URL_FILE=/home/${MS2_USER}/health_url.txt

USER ${MS2_USER}

ENTRYPOINT [ "/entrypoint.sh" ]

EXPOSE 8080
