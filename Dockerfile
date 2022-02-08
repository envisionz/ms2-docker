FROM node:12-buster AS ms2-builder

RUN npm install -g npm@6.14.13

RUN git clone --recursive --branch 2021.02.02-print https://github.com/envisionz/MapStore2.git

RUN cd MapStore2 \
    && npm install

RUN cd MapStore2 \
    && npm run compile

RUN pwd

FROM tomcat:9-jre8-openjdk-buster

ARG MS2_TAG=v2021.02.02
ENV GEOSTORE_VERS=v1.7.0

RUN apt-get update && apt-get install --no-install-recommends -y \
    postgresql-client jq xmlstarlet gettext curl unzip zip git ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG MS2_USER=mapstore
ARG MS2_GROUP=mapstore
ARG MS2_UID=5005
ARG MS2_GID=50005

RUN groupadd -r ${MS2_GROUP} -g ${MS2_GID} && \
    useradd -m -d /home/${MS2_USER}/ -u ${MS2_UID} --gid ${MS2_GID} -s /bin/bash -G ${MS2_GROUP} ${MS2_USER}

RUN chown -R "${MS2_USER}:${MS2_GROUP}" ${CATALINA_HOME}
ENV MS2_DIR=/srv/mapstore

# Download and extract Mapstore2 WAR files
RUN mkdir -p ${MS2_DIR} && cd /srv && \
    curl -L -o mapstore.war https://github.com/geosolutions-it/MapStore2/releases/download/${MS2_TAG}/mapstore.war && \
    curl -L -o mapstore-printing.zip https://github.com/geosolutions-it/MapStore2/releases/download/${MS2_TAG}/mapstore-printing.zip && \
    cd ./mapstore && unzip ../mapstore.war && \
    if [ -d ./mapstore/WEB-INF ]; then cd .. && mv ./mapstore/mapstore ./mapstore_tmp && rm -rf ./mapstore && mv ./mapstore_tmp ./mapstore && cd ./mapstore; fi && \
    unzip ../mapstore-printing.zip && cd .. && \
    rm mapstore.war mapstore-printing.zip && \
    chown -R "${MS2_USER}:${MS2_GROUP}" ./mapstore

COPY --from=ms2-builder --chown=${MS2_USER}:${MS2_GROUP} /MapStore2/web/client/dist/ /srv/mapstore/dist/

# Dowonload Geostore and extract sql scripts
RUN git clone https://github.com/geosolutions-it/geostore.git -b ${GEOSTORE_VERS} && \
    mkdir -p /internal-config/sql && cp -R geostore/doc/sql/. /internal-config/sql && rm -rf geostore

# Replace extremely outdated Postgres jbdc driver with a modern version
# Note Mapstore2 2022.01.00 should have a newer driver, and this can be dropped
RUN [ -f ${MS2_DIR}/WEB-INF/lib/postgresql-8.4-702.jdbc3.jar ] \
    && rm ${MS2_DIR}/WEB-INF/lib/postgresql-8.4-702.jdbc3.jar \
    && curl -L -o ${MS2_DIR}/WEB-INF/lib/postgresql-42.3.1.jar https://jdbc.postgresql.org/download/postgresql-42.3.1.jar \
    && chown "${MS2_USER}:${MS2_GROUP}" ${MS2_DIR}/WEB-INF/lib/postgresql-42.3.1.jar

# Copy the favicon from product/assets/img/ to dist/web/client/product/assets/img/
RUN cp ${MS2_DIR}/product/assets/img/favicon.ico ${MS2_DIR}/dist/web/client/product/assets/img/favicon.ico

ENV MS2_SCRIPT_DIR=/scripts
ENV MS2_DATA_DIR=/srv/mapstore_data

RUN mkdir -p ${MS2_SCRIPT_DIR} ${MS2_DATA_DIR} \
    && chown "${MS2_USER}:${MS2_GROUP}" ${MS2_DATA_DIR}

# Get common tomcat function for paths and proxy
RUN curl -o ${MS2_SCRIPT_DIR}/tc_common.sh https://raw.githubusercontent.com/envisionz/docker-common/3442a7b5860647524d52a662d704d8cc5d814d99/tomcat/tomcat-common.sh \
    && chown "${MS2_USER}:${MS2_GROUP}" ${MS2_SCRIPT_DIR}/tc_common.sh \
    && chmod +x ${MS2_SCRIPT_DIR}/tc_common.sh

# Get tomcat healthcheck script
RUN curl -o ${MS2_SCRIPT_DIR}/tc_healthcheck.sh https://raw.githubusercontent.com/envisionz/docker-common/18906e698a9de3c8bc4ae81557b3df6611132ea4/tomcat/healthcheck.sh \
    && chown "${MS2_USER}:${MS2_GROUP}" ${MS2_SCRIPT_DIR}/tc_healthcheck.sh \
    && chmod +x ${MS2_SCRIPT_DIR}/tc_healthcheck.sh
ENV HEALTH_URL_FILE=/home/${MS2_USER}/health_url.txt

# Copy files required for customization
COPY ./config/ /internal-config/
# Set variable to better handle terminal commands
ENV TERM xterm

RUN mkdir -p /h2db \
    && chown "${MS2_USER}:${MS2_GROUP}" /h2db /internal-config/user_init_list.xml

COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER ${MS2_USER}

ENTRYPOINT [ "/entrypoint.sh" ]

EXPOSE 8080
