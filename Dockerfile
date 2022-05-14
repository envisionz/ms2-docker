ARG MS2_VERS=2022.01.01

FROM node:12-bullseye AS ms2-builder

ARG MS2_VERS

RUN apt-get update && apt-get install --no-install-recommends -y \
    curl unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g npm@6.14.13

RUN git clone --recursive --branch ${MS2_VERS}-envisionz https://github.com/envisionz/MapStore2.git

WORKDIR /MapStore2

RUN npm install
RUN npm run compile

RUN mkdir /mapstore
WORKDIR /mapstore
RUN mkdir -p mapstore-bin && cd mapstore-bin \
    && curl -L -o ./mapstore-bin.zip https://github.com/geosolutions-it/MapStore2/releases/download/v${MS2_VERS}/mapstore2-${MS2_VERS}-bin.zip \
    && unzip mapstore-bin.zip && cd .. \
    && curl -L -o ../mapstore-printing.zip https://github.com/geosolutions-it/MapStore2/releases/download/v${MS2_VERS}/mapstore-printing.zip \
    && unzip ./mapstore-bin/mapstore2/webapps/mapstore.war \
    && unzip ../mapstore-printing.zip \
    && rm ../mapstore-printing.zip \
    && rm -rf ./mapstore-bin \
    && cp -a /MapStore2/web/client/dist/. ./dist

FROM tomcat:9-jre11-openjdk-bullseye

ARG MS2_VERS
ENV GEOSTORE_VERS=v1.8.1

RUN apt-get update && apt-get install --no-install-recommends -y \
    postgresql-client jq xmlstarlet gettext curl unzip zip git ca-certificates python3 \
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
ENV MS2_SCRIPT_DIR=/scripts
ENV MS2_DATA_DIR=/srv/mapstore_data
ENV MS2_PLUGIN_PATCH_DIR=/plugin-patch

RUN mkdir -p ${MS2_SCRIPT_DIR} ${MS2_DATA_DIR}/configs ${MS2_DATA_DIR}/extensions ${MS2_PLUGIN_PATCH_DIR} \
    && chown -R "${MS2_USER}:${MS2_GROUP}" ${MS2_DATA_DIR} ${MS2_PLUGIN_PATCH_DIR}

# Get common tomcat function for paths and proxy
RUN curl -o ${MS2_SCRIPT_DIR}/tc_common.sh https://raw.githubusercontent.com/envisionz/docker-common/3442a7b5860647524d52a662d704d8cc5d814d99/tomcat/tomcat-common.sh \
    && chown "${MS2_USER}:${MS2_GROUP}" ${MS2_SCRIPT_DIR}/tc_common.sh \
    && chmod +x ${MS2_SCRIPT_DIR}/tc_common.sh

# Get tomcat healthcheck script
RUN curl -o ${MS2_SCRIPT_DIR}/tc_healthcheck.sh https://raw.githubusercontent.com/envisionz/docker-common/18906e698a9de3c8bc4ae81557b3df6611132ea4/tomcat/healthcheck.sh \
    && chown "${MS2_USER}:${MS2_GROUP}" ${MS2_SCRIPT_DIR}/tc_healthcheck.sh \
    && chmod +x ${MS2_SCRIPT_DIR}/tc_healthcheck.sh
ENV HEALTH_URL_FILE=/home/${MS2_USER}/health_url.txt

# Download and extract Mapstore2 WAR files
COPY --from=ms2-builder --chown=${MS2_USER}:${MS2_GROUP} /mapstore/ /srv/mapstore/

# Copy the favicon from product/assets/img/ to dist/web/client/product/assets/img/
RUN cp ${MS2_DIR}/product/assets/img/favicon.ico ${MS2_DIR}/dist/web/client/product/assets/img/favicon.ico

# Copy files required for customization
COPY ./config/ /internal-config/

RUN cp ${MS2_DIR}/configs/localConfig.json /internal-config/localConfig.json \
    && chown "${MS2_USER}:${MS2_GROUP}" /internal-config/localConfig.json

# Set variable to better handle terminal commands
ENV TERM xterm

RUN mkdir -p /h2db \
    && chown "${MS2_USER}:${MS2_GROUP}" /h2db /internal-config/user_init_list.xml

COPY ./entrypoint.sh ./pluginPatch/pluginPatch.py /scripts/
RUN chmod +x /scripts/entrypoint.sh

USER ${MS2_USER}

ENTRYPOINT [ "/scripts/entrypoint.sh" ]

EXPOSE 8080
